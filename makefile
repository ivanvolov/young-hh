ta:
	clear && forge test -vv
tl:
	clear && forge test -vvvv --match-test test_swap_price_up_in
t:
	clear && forge test -vv

spell:
	clear && cspell "**/*.*"