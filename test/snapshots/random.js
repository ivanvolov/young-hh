const randomCap = parseInt(process.argv[2], 10);

const randomNumber = Math.floor(Math.random() * randomCap);

process.stdout.write(randomNumber.toString());