const fs = require("fs");
const { BigNumber } = require("ethers");

const packedHexString = process.argv[2];
const csvFilePath = "test/snapshots/states.csv";

function hexToBuffer(hex) {
    return Buffer.from(hex.replace(/^0x/, ""), "hex");
}

function decodeInt24BE(buffer, offset) {
    const bytes = buffer.slice(offset, offset + 3);
    
    // Decode big-endian 24-bit (3-byte) signed integer
    const intValue = (bytes[0] << 16) | (bytes[1] << 8) | bytes[2];
    
    // Handle sign extension manually for 24-bit integer
    if (intValue & 0x800000) {
        return intValue | 0xFF000000; // Fill the upper 8 bits with 1s if negative (sign extend to 32-bit)
    }
    
    return intValue;
}

function decodeSwapData(buffer) {
    const liquidity = BigNumber.from(buffer.slice(0, 16)).toString(); // uint128 (16 bytes)
    const sqrtPriceX96 = BigNumber.from(buffer.slice(16, 36)).toString(); // uint160 (20 bytes)

    const tickLower = decodeInt24BE(buffer, 36); // int24 (3 bytes)
    const tickUpper = decodeInt24BE(buffer, 39); // int24 (3 bytes)
    
    const borrowed = BigNumber.from(buffer.slice(42, 74)).toString(); // uint256 (32 bytes)
    const supplied = BigNumber.from(buffer.slice(74, 106)).toString(); // uint256 (32 bytes)
    const collateral = BigNumber.from(buffer.slice(106, 138)).toString(); // uint256 (32 bytes)
    const blockNumber = BigNumber.from(buffer.slice(138, 170)).toString(); // uint256 (32 bytes)
    const sqrtPriceX96Control = BigNumber.from(buffer.slice(170, 170+20)).toString(); // uint160 (20 bytes)


    return { liquidity, sqrtPriceX96, tickLower, tickUpper, borrowed, supplied, collateral, blockNumber, sqrtPriceX96Control };
}

const packedBuffer = hexToBuffer(packedHexString);
// console.log(decodeSwapData(packedBuffer));
const { liquidity, sqrtPriceX96, tickLower, tickUpper, borrowed, supplied, collateral, blockNumber, sqrtPriceX96Control } = decodeSwapData(packedBuffer);

const csvData = `${liquidity},${sqrtPriceX96},${sqrtPriceX96Control},${tickLower},${tickUpper},${borrowed},${supplied},${collateral},${blockNumber}\n`;
fs.appendFileSync(csvFilePath, csvData, "utf8");
console.log(`Swap data written to ${csvFilePath}`);
