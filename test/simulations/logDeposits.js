const { decodeHexString, saveToCSV } = require("./common");

const packedHexString = process.argv[2];

const packedBuffer = hexToBuffer(packedHexString);
const [amount, actor, blockNumber, dWETH, dWETHc, dUSDCc, dUSDCc, dSH, dSHc] = decodeHexString(packedBuffer, [
    "uint256",
    "address",
    "uint256",
    "uint256",
    "uint256",
    "uint256",
    "uint256",
    "uint256",
]);

const csvData = `${amount},${tokeWeth},${tokeWethControl},${tokeUsdcControl},${actor},${blockNumber},${delShares},${delSharesControl}\n`;
saveToCSV("deposits", csvData);
