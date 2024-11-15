const { utils } = require("ethers");

const packedHexString = process.argv[2];
const [randomCap] = decodeHexString(packedHexString, ["uint256"]);

const randomNumber = Math.floor(Math.random() * randomCap) + 1;

// ** This is for testing only
// const csvFilePath = "test/snapshots/temp.txt";
// const csvData = `${randomNumber},${randomCap}\n`;
// fs.appendFileSync(csvFilePath, csvData, "utf8");
// console.log(randomNumber);

const resultBuffer = utils.defaultAbiCoder.encode(["uint256"], [randomNumber]);
console.log(resultBuffer.toString("hex"));
