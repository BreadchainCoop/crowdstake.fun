"use client";

import { useReadContract } from "wagmi";
import { instanceMetadataAbi } from "@/lib/abis";
import { CHAIN_ID } from "@/lib/constants";
import { useInstance } from "@/components/instance-provider";
import { useTx } from "@/hooks/use-tx";

/**
 * The active instance's on-chain artwork URIs, read from its distribution
 * manager (the canonical instance key). Instances on the older implementation
 * simply revert these reads, so the hook degrades to undefined (no image).
 */
export function useInstanceMetadata() {
  const a = useInstance();
  const query = { chainId: CHAIN_ID, query: { retry: false } } as const;
  const tokenImage = useReadContract({
    address: a.distributionManager,
    abi: instanceMetadataAbi,
    functionName: "tokenImageURI",
    ...query,
  });
  const bannerImage = useReadContract({
    address: a.distributionManager,
    abi: instanceMetadataAbi,
    functionName: "bannerImageURI",
    ...query,
  });
  return {
    tokenImageURI: (tokenImage.data as string | undefined) || undefined,
    bannerImageURI: (bannerImage.data as string | undefined) || undefined,
    refetch: () => {
      void tokenImage.refetch();
      void bannerImage.refetch();
    },
  };
}

/** Update the active instance's artwork URIs (instance owner only). */
export function useSetInstanceMetadata() {
  const a = useInstance();
  const tx = useTx();
  const set = (tokenImageURI: string, bannerImageURI: string) =>
    tx.run({
      address: a.distributionManager,
      abi: instanceMetadataAbi,
      functionName: "setInstanceMetadata",
      args: [tokenImageURI, bannerImageURI],
    });
  return { set, ...tx };
}
