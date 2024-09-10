ta:
	clear && forge test -vv --match-contract Test

t:
	clear && forge test -vvvv --match-contract ALMTest --match-test "test_deposit"
t1:
	clear && forge test -vvvv --match-contract ChainlinkTest --match-test "test"
tl:
	clear && forge test -vv --match-contract ALMTest --match-test "test_deposit"

spell:
	clear && cspell "**/*.*"