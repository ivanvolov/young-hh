const fs = require("fs");
const { BigNumber } = require("ethers");

// Input: Hex string representing packed swap data
const packedHexString = process.argv[2];
const csvFilePath = "test/snapshots/swaps.csv";

// Helper function to convert hex string to Buffer
function hexToBuffer(hex) {
    return Buffer.from(hex.replace(/^0x/, ""), "hex");
}

function decodeInt256(buffer, offset) {
    // Get the 32-byte slice and interpret as an unsigned BigInt
    let intValue = BigInt('0x' + buffer.slice(offset, offset + 32).toString('hex'));

    // Check if the most significant bit (sign bit for int256) is set
    const isNegative = intValue >= (1n << 255n);

    // If negative, convert to the correct signed 256-bit integer
    if (isNegative) {
        intValue -= 1n << 256n;
    }

    // Convert the result to a string and return
    return intValue.toString();
}

// Helper function to decode packed swap data
function decodeSwapData(buffer) {
    const amount = BigNumber.from(buffer.slice(0, 32)).toString();
    const zeroForOne = buffer.readUInt8(32) === 1;
    const _in = buffer.readUInt8(33) === 1;
    const blockNumber = BigNumber.from(buffer.slice(34, 66)).toString();

    const delta0 = decodeInt256(buffer, 66);
    const delta1 = decodeInt256(buffer, 98);
    const delta0c = decodeInt256(buffer, 130);
    const delta1c = decodeInt256(buffer, 162);

    return { amount, zeroForOne, _in, blockNumber, delta0, delta1, delta0c, delta1c };
}

// Decode the hex string
const packedBuffer = hexToBuffer(packedHexString);
const { amount, zeroForOne, _in, blockNumber, delta0, delta1, delta0c, delta1c } = decodeSwapData(packedBuffer);

// Append swap data to CSV file
const csvData = `${amount},${zeroForOne},${_in},${blockNumber},${delta0},${delta1},${delta0c},${delta1c}\n`;
fs.appendFileSync(csvFilePath, csvData, "utf8");
console.log(`Swap data written to ${csvFilePath}`);
