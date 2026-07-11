"use client";

import { useCallback, useEffect, useRef, type ReactNode } from "react";
import { encodeFunctionData, numberToHex, type Hex } from "viem";
import { useAccount } from "wagmi";
import { useSetActiveWallet } from "@privy-io/wagmi";
import {
  useLogin,
  usePrivy,
  useSendTransaction,
  useWallets,
  type ConnectedWallet,
} from "@privy-io/react-auth";
import {
  WalletActionsContext,
  useWalletWrite,
  type SponsoredTxRequest,
  type WalletActions,
} from "@/components/wallet/wallet-actions";

/**
 * Privy provider: connect via Privy (embedded + external wallets), and submit
 * governance writes gaslessly from the embedded wallet via native "App pays"
 * (EIP-7702) sponsorship — a specific `chainId` per call, no network switch, no
 * per-tx prompt (`showWalletUIs: false`). External wallets connected through
 * Privy can't be sponsored, so they fall back to a normal self-paid write.
 *
 * Only mounted inside a `<PrivyProvider>` (privy hooks require that ancestor).
 */
export function PrivyWalletActions({ children }: { children: ReactNode }) {
  const { login } = useLogin();
  const { ready, authenticated, logout } = usePrivy();
  const { wallets } = useWallets();
  const { setActiveWallet } = useSetActiveWallet();
  const { sendTransaction } = useSendTransaction();
  const { address, isConnected } = useAccount();
  const selfPaidWrite = useWalletWrite();

  /**
   * Prefer the embedded (sponsorable) wallet, else the first connected one.
   * `wallets` can be briefly empty right after login while the embedded wallet
   * provisions, so callers must tolerate `undefined`.
   */
  const preferredWallet = useCallback((): ConnectedWallet | undefined => {
    return wallets.find((w) => w.walletClientType === "privy") ?? wallets[0];
  }, [wallets]);

  /**
   * Bridge the authenticated Privy wallet into wagmi. Privy auth alone does NOT
   * make wagmi `isConnected` — without this the UI stays on "Connect" forever
   * and re-clicking calls `login()` on an already-authenticated user (a no-op
   * that throws "use a `link` helper instead"). Runs once per wallet: a ref
   * guards against re-entering while `setActiveWallet` is in flight.
   */
  const bridging = useRef<string | null>(null);
  useEffect(() => {
    if (!ready || !authenticated || isConnected) return;
    const wallet = preferredWallet();
    if (!wallet || bridging.current === wallet.address) return;
    bridging.current = wallet.address;
    void setActiveWallet(wallet).finally(() => {
      bridging.current = null;
    });
  }, [ready, authenticated, isConnected, preferredWallet, setActiveWallet]);

  /** Is the active wallet a Privy embedded wallet (sponsorable)? */
  const activeIsEmbedded = useCallback(() => {
    if (!address) return false;
    const w = wallets.find(
      (x) => x.address?.toLowerCase() === address.toLowerCase(),
    );
    return w?.walletClientType === "privy";
  }, [wallets, address]);

  const sendSponsored = useCallback(
    async (req: SponsoredTxRequest): Promise<Hex> => {
      // External wallet → normal self-paid write (can't be sponsored).
      // Value-carrying txs (native deposits) also self-pay: Privy's sponsorship
      // simulation doesn't credit the account's native balance, so ANY op with
      // value reverts there ("UserOperation reverted during simulation with
      // reason: 0x") — while the same op passes a public bundler's simulation.
      // A wallet sending native value holds native funds by definition, so the
      // (tiny) gas comes from the same balance the deposit UI already reserves.
      if (!activeIsEmbedded() || (req.value !== undefined && req.value > 0n))
        return selfPaidWrite(req);

      const data = encodeFunctionData({
        abi: req.abi as Parameters<typeof encodeFunctionData>[0]["abi"],
        functionName: req.functionName,
        args: req.args as readonly unknown[],
      });
      const { hash } = await sendTransaction(
        {
          to: req.address,
          data,
          chainId: req.chainId,
          ...(req.value !== undefined ? { value: numberToHex(req.value) } : {}),
        },
        { sponsor: true, uiOptions: { showWalletUIs: false } },
      );
      return hash;
    },
    [activeIsEmbedded, selfPaidWrite, sendTransaction],
  );

  const actions: WalletActions = {
    // Already authenticated (e.g. embedded wallet still bridging into wagmi)?
    // Re-running `login()` throws "already logged in" — instead push the Privy
    // wallet into wagmi so `isConnected` flips. Otherwise open the login flow.
    connect: () => {
      if (authenticated) {
        const wallet = preferredWallet();
        if (wallet) void setActiveWallet(wallet);
        return;
      }
      login();
    },
    disconnect: () => void logout(),
    sendSponsored,
    // Embedded Privy wallets are gas-sponsored; external wallets self-pay.
    sponsored: activeIsEmbedded(),
  };

  return (
    <WalletActionsContext.Provider value={actions}>
      {children}
    </WalletActionsContext.Provider>
  );
}
