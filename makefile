ta:
	clear && forge test -vv
ts:
	clear && forge test -vv --match-test test_simulation_start --ffi
tsl:
	clear && forge test -vvvv --match-test test_simulation_start --ffi
tl:
	clear && forge test -vvvv --match-test test_swap_price_down_withdraw
t:
	clear && forge test -vv --match-test test_swap_price_down_withdraw

spell:
	clear && cspell "**/*.*"