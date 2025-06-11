const { run } = require("hardhat");

async function main() {
  const ccipRouter = "0xAba60dA7E88F7E8f5868C2B6dE06CB759d693af0";
  const sourceBridge = "0x74C774E7Db3a994FBE78b5174F647b44fB969035";
  const sourceChainId = "16015286601757825753";
  const tokenMapping = [
    // {
    //   tokenId: ethers.keccak256(ethers.toUtf8Bytes("ETH")),
    //   tokenAddress: "0xYourWETHAddress", // Thay bằng địa chỉ wETH trên Sepolia
    // },
    {
      tokenId: ethers.keccak256(ethers.toUtf8Bytes("USDC")),
      tokenAddress: "0x510145405896aA0Ad7CA29A86a14093DD0199C2D", // Thay bằng địa chỉ USDC trên Sepolia
    },
    // {
    //   tokenId: ethers.keccak256(ethers.toUtf8Bytes("USDT")),
    //   tokenAddress: "0xYourUSDTAddress", // Thay bằng địa chỉ USDT trên Sepolia
    // },
  ];
  try {
    await run("verify:verify", {
      address: "0xb28eE71D1Af8b608B0C9d9382Aa94314679F5f06",
      constructorArguments: [ 
        ccipRouter,
        sourceBridge,
        sourceChainId
      ],
    });
    console.log("Verification successful!");
  } catch (error) {
    console.error("Verification failed:", error);
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});