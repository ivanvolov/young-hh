const { decodeHexString, saveToCSV } = require("./common");

const packedHexString = process.argv[2];
const args = decodeHexString(packedHexString, [
    "uint256",
    "uint160",
    "uint128",
    "uint160",
    "int24",
    "int24",
    "uint256",
    "uint256",
    "uint256",
    "uint256",
    "uint256",
    "uint256",
    "uint256",
]);

saveToCSV("states", `${args.join(",")}\n`);
