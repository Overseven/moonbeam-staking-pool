import "@nomicfoundation/hardhat-toolbox";
import "solidity-docgen";

import * as defaultConfig from "./hardhat.config";

const config = {
  ...defaultConfig.default,
  networks: {
    hardhat: {
      forking: {
        enabled: true,
        url: "https://rpc.api.moonbeam.network",
      },
    },
  },
};

export default config;
