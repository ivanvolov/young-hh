const fs = require("fs");

const csvFilePath = "test/snapshots/swaps.csv";

// Delete the file if it exists
if (fs.existsSync(csvFilePath)) {
    fs.unlinkSync(csvFilePath);
}

// Write the header row to the CSV file
const headerRow = "Amount,Zero-For-One,In,Block Number\n";
fs.writeFileSync(csvFilePath, headerRow, "utf8");

console.log("CSV file prepared.");