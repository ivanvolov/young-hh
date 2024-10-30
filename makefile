ta:
	clear && forge test -vv
tl:
	clear && forge test -vvvv --match-test test_deposit
t:
	clear && forge test -vv --match-test test_deposit

spell:
	clear && cspell "**/*.*"