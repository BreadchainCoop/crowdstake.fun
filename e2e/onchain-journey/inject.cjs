/* Install the test wallet into a Playwright browser context:
 *  - expose the Node-side signer as window.__csWallet (the key never enters the page)
 *  - inject an EIP-1193 window.ethereum shim that proxies every call to it
 *  - announce a distinct EIP-6963 wallet + preseed wagmi so it auto-reconnects
 *    with no modal and no prompt
 */
const { handle, account } = require("./lib.cjs");

const WALLET_RDNS = "fun.crowdstake.testwallet";
const WALLET_NAME = "Crowdstake Test";

async function installShim(context) {
  // The only bridge to the key. The page calls window.__csWallet({method,params}).
  await context.exposeFunction("__csWallet", (payload) =>
    handle(payload.method, payload.params || []),
  );

  // In-page EIP-1193 provider — a pure proxy. No key, no viem in the page.
  await context.addInitScript(
    ({ rdns, name }) => {
      const listeners = {};
      const emit = (ev, ...a) => (listeners[ev] || []).forEach((f) => f(...a));
      const provider = {
        isMetaMask: false,
        _isCrowdstakeTestShim: true,
        isConnected: () => true,
        request: ({ method, params = [] }) =>
          window.__csWallet({ method, params }),
        on(ev, fn) {
          (listeners[ev] = listeners[ev] || []).push(fn);
          return this;
        },
        removeListener(ev, fn) {
          listeners[ev] = (listeners[ev] || []).filter((f) => f !== fn);
          return this;
        },
        removeAllListeners() {
          for (const k in listeners) listeners[k] = [];
          return this;
        },
      };
      try {
        Object.defineProperty(window, "ethereum", {
          value: provider,
          configurable: true,
          writable: true,
        });
      } catch {
        window.ethereum = provider;
      }
      const announce = () =>
        window.dispatchEvent(
          new CustomEvent("eip6963:announceProvider", {
            detail: Object.freeze({
              info: {
                uuid: "11111111-1111-1111-1111-111111111111",
                name,
                icon: 'data:image/svg+xml,<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32"><rect width="32" height="32" fill="%23e4572e"/></svg>',
                rdns,
              },
              provider,
            }),
          }),
        );
      window.addEventListener("eip6963:requestProvider", announce);
      announce();
      setTimeout(() => emit("connect", { chainId: "0x64" }), 0);
    },
    { rdns: WALLET_RDNS, name: WALLET_NAME },
  );

  // Preseed wagmi so reconnectOnMount connects our provider — zero clicks.
  await context.addInitScript(
    ({ address, id, name }) => {
      try {
        localStorage.setItem("wagmi.recentConnectorId", JSON.stringify(id));
        localStorage.setItem(
          "wagmi.store",
          JSON.stringify({
            state: {
              chainId: 100,
              current: id,
              connections: {
                __type: "Map",
                value: [
                  [
                    id,
                    {
                      accounts: [address],
                      chainId: 100,
                      connector: { id, name, type: "injected", uid: id },
                    },
                  ],
                ],
              },
            },
            version: 2,
          }),
        );
      } catch {}
    },
    { address: account.address, id: WALLET_RDNS, name: WALLET_NAME },
  );
}

module.exports = { installShim, WALLET_NAME };
