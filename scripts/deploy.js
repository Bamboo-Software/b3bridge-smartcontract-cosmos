const hre = require("hardhat");
const { ethers } = require("hardhat");
async function main() {
  const [deployer] = await hre.ethers.getSigners();
  console.log("Deploying contracts with account:", deployer.address);

  const ccipRouter = "0x59F5222c5d77f8D3F56e34Ff7E75A05d2cF3a98A";
  const sourceBridge = "0x300C0A8514864fd23DA2E6fBF916A693F6082589"; // cái này dễ thay đổi
  const sourceChainId = 16015286601757825753n;
  const wNativeToken ="0x42B4fdB1888001BB4C06f8BaFfB8a96B56693614"; // cái này dễ thay đổi
  const validators = [deployer.address];
  const threshold = 1;
  const tokenMapping = [
    {
      tokenId: "0xd6aca1be9729c13d677335161321649cccae6a591554772516700f986f942eaa",
      tokenAddress: "0x53D081260B047F6b306E630298077ADab96660f6", // cái này dễ thay đổi
    },
  ];

  const B3BridgeDest = await hre.ethers.getContractFactory("B3BridgeDest");
  const bridgeDest = await B3BridgeDest.deploy(ccipRouter, sourceBridge, sourceChainId, validators, threshold, wNativeToken);
  await bridgeDest.waitForDeployment();
  console.log("B3BridgeDest deployed to:", await bridgeDest.getAddress());

  for (const { tokenId, tokenAddress } of tokenMapping) {
    const tx = await bridgeDest.setTokenMapping(tokenId, tokenAddress);
    await tx.wait();
    console.log(`Set token mapping: ${tokenId} -> ${tokenAddress}`);
  }
  
  // // Dùng hre.run để verify
  // console.log("Verifying contract on Sei EVM...");
  // try {
  //   await hre.run("verify:verify", {
  //     address: await bridgeDest.getAddress(),
  //     constructorArguments: [ccipRouter, sourceBridge, sourceChainId],
  //   });
  //   console.log("Contract verified successfully.");
  // } catch (error) {
  //   console.error("Verification failed:", error);
  // }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
