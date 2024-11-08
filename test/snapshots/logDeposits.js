const fs = require("fs");
const { BigNumber } = require("ethers");

// Input: Hex string representing packed deposit data
const packedHexString = process.argv[2];
const csvFilePath = "test/snapshots/deposits.csv";

// Helper function to convert hex string to Buffer
function hexToBuffer(hex) {
    return Buffer.from(hex.replace(/^0x/, ""), "hex");
}

// Helper function to decode packed deposit data
function decodeDepositData(buffer) {
    const amount = BigNumber.from(buffer.slice(0, 32)).toString();
    const actor = '0x' + buffer.slice(32, 52).toString('hex'); // Address is 20 bytes
    const blockNumber = BigNumber.from(buffer.slice(52, 84)).toString(); // Read block number from the right slice
    const tokeWeth = BigNumber.from(buffer.slice(84, 84+32)).toString(); // uint256 (32 bytes)
    const tokeWethControl = BigNumber.from(buffer.slice(84+32, 84+32*2)).toString(); // uint256 (32 bytes)
    const tokeUsdcControl = BigNumber.from(buffer.slice(84+32*2, 84+32*3)).toString(); // uint256 (32 bytes)
    return { amount, actor, blockNumber, tokeWeth, tokeWethControl, tokeUsdcControl };
}

// Decode the hex string
const packedBuffer = hexToBuffer(packedHexString);
const { amount, actor, blockNumber, tokeWeth, tokeWethControl, tokeUsdcControl } = decodeDepositData(packedBuffer);

// Append deposit data to CSV file
const csvData = `${amount},${tokeWeth},${tokeWethControl},${tokeUsdcControl},${actor},${blockNumber}\n`;
fs.appendFileSync(csvFilePath, csvData, "utf8");
console.log(`Deposit data written to ${csvFilePath}`);