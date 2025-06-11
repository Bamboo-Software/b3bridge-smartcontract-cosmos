import hre from "hardhat";
const { ethers } = hre;

async function main() {
  const [deployer] = await ethers.getSigners();

  // Thay địa chỉ token và bridge contract của bạn ở đây:
  const tokenAddress = "0x29f4B6073F6900f6132a7630e999C3eF594A59B6"; // Địa chỉ CustomCoin đã deploy
  const bridgeAddress = "0x1Cef4DfB0B9DCbA73f56f71957a9f722516F4BaA"; // Địa chỉ B3BridgeDest đã deploy

  console.log("Deployer address:", deployer.address);
  console.log("Token address:", tokenAddress);
  console.log("Bridge address:", bridgeAddress);

  // Lấy instance token
  const token = await ethers.getContractAt("CustomCoin", tokenAddress);

  // Gọi transferOwnership sang bridge
  const tx = await token.transferOwnership(bridgeAddress);
  await tx.wait();

  console.log(`Transferred ownership of token ${tokenAddress} to bridge ${bridgeAddress}`);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
