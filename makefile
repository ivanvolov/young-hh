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

t2:
	clear && forge test -vv --match-test test_new_ALM_concept

t2l:
	clear && forge test -vvvv --match-test test_new_ALM_concept

spell:
	clear && cspell "**/*.*"