ta:
	clear && forge test -vv --match-contract Test

t:
	clear && forge test -vvvv --match-contract ALMTest --match-test "test_swap_price_down"
t1:
	clear && forge test -vvvv --match-contract ChainlinkTest --match-test "test"
tl:
	clear && forge test -vv --match-contract ALMTest --match-test "test_swap_price_down_out"

spell:
	clear && cspell "**/*.*"