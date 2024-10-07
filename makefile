ta:
	clear && forge test -vv
tl:
	clear && forge test -vvvv --match-test test_swap_price_down_rebalance
t:
	clear && forge test -vv --match-test test_swap_price_down_rebalance

spell:
	clear && cspell "**/*.*"