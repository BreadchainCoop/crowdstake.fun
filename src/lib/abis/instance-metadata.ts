import { parseAbi } from "viem";

/**
 * Instance metadata lives on the distribution manager (the app's canonical
 * per-instance key). ERC-7572 contractURI() is assembled from the two image
 * URIs; setInstanceMetadata is owner-gated.
 */
export const instanceMetadataAbi = parseAbi([
  "function tokenImageURI() view returns (string)",
  "function bannerImageURI() view returns (string)",
  "function contractURI() view returns (string)",
  "function setInstanceMetadata(string tokenImageURI, string bannerImageURI)",
]);
