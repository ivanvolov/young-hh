const { decodeHexString, saveToCSV } = require("./common");

const packedHexString = process.argv[2];

const packedBuffer = hexToBuffer(packedHexString);
const [shares1, shares2, actor, blockNumber, dWETH, dUSDC, dWETHc, dUSDCc, dSH, dSHc] = decodeHexString(packedBuffer, [
    "uint256",
    "uint256",
    "address",
    "uint256",
    "uint256",
    "uint256",
    "uint256",
    "uint256",
    "uint256",
    "uint256",
]);

const csvData = `${shares1},${shares2},${actor},${blockNumber},${dWETH},${dWETHc},${dUSDC},${dUSDCc},${dSH},${dSHc}\n`;
saveToCSV("withdraws", csvData);
