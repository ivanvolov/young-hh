ta:
	clear && forge test -vv --match-contract Test

t:
	clear && forge test -vvvv --match-contract ALMTest --match-test "test_simulate_chainlink_automation"
t1:
	clear && forge test -vvvv --match-contract ALMTest --match-test "test_oracle"
tl:
	clear && forge test -vv --match-contract ALMTest --match-test "test_simulate_chainlink_automation"

spell:
	clear && cspell "**/*.*"