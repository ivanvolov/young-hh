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
const swapsHeaderRow = "Amount,zeroForOne,In,blockNumber,delta0,delta1,delta0c,delta1c\n";
prepareCsvFile(swapsCsvFilePath, swapsHeaderRow);

// Prepare states.csv
const statesHeaderRow = "Liquidity, SqrtPriceX96, SqrtPriceX96c, TickLower, TickUpper, Borrowed, Supplied, Collateral, blockNumber, tvl, tvlControl\n";
prepareCsvFile(statesCsvFilePath, statesHeaderRow);

// Prepare deposits.csv
const depositsHeaderRow = "Amount, tWETH, tWETHc, tUSDCc, Actor, blockNumber\n";
prepareCsvFile(depositsCsvFilePath, depositsHeaderRow);

console.log("All CSV files cleared and headers written.");