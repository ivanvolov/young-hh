test_all:
	clear && forge test -vv
test_all_verbose:
	clear && forge test -vvvv
test_chainlink_automation:
	clear && forge test -vv --match-contract ALMTest --match-test "test_simulate_chainlink_automation"

spell:
	clear && cspell "**/*.*"