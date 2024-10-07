ta:
	clear && forge test -vv
tl:
	clear && forge test -vvvv --match-test test_lending_adapter_migration
t:
	clear && forge test -vv --match-test test_lending_adapter_migration

spell:
	clear && cspell "**/*.*"