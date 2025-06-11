const { run } = require("hardhat");

async function main() {
  try {
    await run("verify:verify", {
      address: "0x510145405896aA0Ad7CA29A86a14093DD0199C2D",
      constructorArguments: [],
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