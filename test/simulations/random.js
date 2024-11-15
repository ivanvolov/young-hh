const fs = require("fs");
const { BigNumber, utils } = require("ethers");

const packedHexString = process.argv[2];

function hexToBuffer(hex) {
  return Buffer.from(hex.replace(/^0x/, ""), "hex");
}

const packedBuffer = hexToBuffer(packedHexString);

function decodeSwapData(buffer) {
  const randomCap = BigNumber.from(buffer.slice(0, 32)).toNumber(); // uint256 (32 bytes)
  return { randomCap };
}

const { randomCap } = decodeSwapData(packedBuffer);
const randomNumber = Math.floor(Math.random() * randomCap)+1;

// ** This is for testing only
// const csvFilePath = "test/snapshots/temp.txt";
// const csvData = `${randomNumber},${randomCap}\n`;
// fs.appendFileSync(csvFilePath, csvData, "utf8");
// console.log(randomNumber);

const resultBuffer = utils.defaultAbiCoder.encode(["uint256"], [randomNumber]);
console.log(resultBuffer.toString("hex"));
