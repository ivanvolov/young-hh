const fs = require("fs");
const { BigNumber } = require("ethers");

// Input: Hex string representing packed swap data
const packedHexString = process.argv[2];
const csvFilePath = "test/snapshots/swaps.csv";

// Helper function to convert hex string to Buffer
function hexToBuffer(hex) {
    return Buffer.from(hex.replace(/^0x/, ""), "hex");
}

// Helper function to decode packed swap data
function decodeSwapData(buffer) {
    const amount = BigNumber.from(buffer.slice(0, 32)).toString();
    const zeroForOne = buffer.readUInt8(32) === 1;
    const _in = buffer.readUInt8(33) === 1;
    const blockNumber = BigNumber.from(buffer.slice(34, 66)).toString();
    return { amount, zeroForOne, _in, blockNumber };
}

// Decode the hex string
const packedBuffer = hexToBuffer(packedHexString);
const { amount, zeroForOne, _in, blockNumber } = decodeSwapData(packedBuffer);

// Append swap data to CSV file
const csvData = `${amount},${zeroForOne},${_in},${blockNumber}\n`;
fs.appendFileSync(csvFilePath, csvData, "utf8");
console.log(`Swap data written to ${csvFilePath}`);