async function main() {
  const recipient = (await hre.ethers.getSigners())[0].address;
  const amountToMint = ethers.parseUnits("100", 6); // 1 triệu wUSDC (6 decimals)

  // Deploy wUSDC
  const coin = await hre.ethers.getContractFactory("CustomCoin");
  const coin_deploy = await coin.deploy();
  await coin_deploy.waitForDeployment();
  console.log("CustomCoin deployed to:", coin_deploy.target);

  // Mint 1 triệu wUSDC
  const txMint = await coin_deploy.mint(recipient, amountToMint);
  await txMint.wait();
  console.log(`Minted ${ethers.formatUnits(amountToMint, 6)} wbUSDC to ${recipient}`);

  // Kiểm tra số dư
  const balance = await coin_deploy.balanceOf(recipient);
  console.log(`Balance of ${recipient}: ${ethers.formatUnits(balance, 6)} wbUSDC`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
