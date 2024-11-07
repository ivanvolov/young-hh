const fs = require("fs");

// File paths
const swapsCsvFilePath = "test/snapshots/swaps.csv";
const statesCsvFilePath = "test/snapshots/states.csv";
const depositsCsvFilePath = "test/snapshots/deposits.csv";

// Function to clear and write headers to a CSV file
function prepareCsvFile(filePath, headerRow) {
    // Delete the file if it exists
    if (fs.existsSync(filePath)) {
        fs.unlinkSync(filePath);
    }

    // Write the header row to the CSV file
    fs.writeFileSync(filePath, headerRow, "utf8");

    console.log(`${filePath} prepared.`);
}

// Prepare swaps.csv
const swapsHeaderRow = "Amount,zeroForOne,In,blockNumber\n";
prepareCsvFile(swapsCsvFilePath, swapsHeaderRow);

// Prepare states.csv
const statesHeaderRow = "Liquidity, SqrtPriceX96, TickLower, TickUpper, Borrowed, Supplied, Collateral, blockNumber\n";
prepareCsvFile(statesCsvFilePath, statesHeaderRow);

// Prepare deposits.csv
const depositsHeaderRow = "Amount, Actor, blockNumber\n";
prepareCsvFile(depositsCsvFilePath, depositsHeaderRow);

console.log("All CSV files cleared and headers written.");