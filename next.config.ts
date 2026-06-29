import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  webpack: (config) => {
    // Silence optional-dep resolution warnings from the wallet/web3 tree
    // (WalletConnect/pino, MetaMask SDK's React-Native async-storage).
    config.resolve.fallback = {
      ...config.resolve.fallback,
      "pino-pretty": false,
      "@react-native-async-storage/async-storage": false,
    };
    return config;
  },
};

export default nextConfig;
