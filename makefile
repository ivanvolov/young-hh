ta:
	clear && forge test -vv
tl:
	clear && forge test -vvvv --match-test test_swap_price_up_out
t:
	clear && forge test -vv --match-test test_swap_price_up_out

spell:
	clear && cspell "**/*.*"