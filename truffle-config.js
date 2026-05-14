const HDWalletProvider = require("@truffle/hdwallet-provider");
const fs = require("fs");

const rawSecret = fs.existsSync(".secret")
  ? fs.readFileSync(".secret").toString().trim()
  : "";

const secret = rawSecret.split(/\r?\n/).reduce((acc, line) => {
  const [key, ...rest] = line.split("=");
  if (!key) return acc;
  acc[key.trim()] = rest.join("=").trim();
  return acc;
}, {});

const mnemonic = secret.MNEMONIC || "";
const etherscanApiKey = secret.ETHERSCAN_API || "";

if (!mnemonic) {
  console.warn("Warning: MNEMONIC is missing in .secret file");
}

module.exports = {
  // contracts_build_directory: "./src/contracts/",
  networks: {
    development: {
      host: "127.0.0.1", // Localhost (default: none)
      port: 8545, // Standard BSC port (default: none)
      network_id: "*", // Any network (default: none)
    },
    bsc_testnet: {
      provider: () =>
        new HDWalletProvider(
          mnemonic,
          `https://data-seed-prebsc-1-s1.binance.org:8545`
        ),
      network_id: 97,
      confirmations: 10,
      timeoutBlocks: 200,
      skipDryRun: true,
    },
    bsc: {
      provider: () =>
        new HDWalletProvider(mnemonic, `https://bsc-dataseed1.binance.org`),
      network_id: 56,
      confirmations: 10,
      timeoutBlocks: 200,
      skipDryRun: true,
    },
  },

  mocha: {
    // timeout: 100000
  },

  // Configure your compilers

  compilers: {
    solc: {
      version: "^0.8.0", // A version or constraint - Ex. "^0.5.0"
      parser: "solcjs",  // Leverages solc-js purely for speedy parsing
      settings: {
        optimizer: {
          enabled: true,
          runs: 200,  // Optimize for how many times you intend to run the code
        },
      },
    },
  },

  plugins: ['truffle-plugin-verify'],
  api_keys: {
    etherscan: etherscanApiKey,
  },
};
