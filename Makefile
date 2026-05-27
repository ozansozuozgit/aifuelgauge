.PHONY: test run package install uninstall

test:
	swift test

run:
	scripts/dev-run.sh

package:
	scripts/package-app.sh

install:
	scripts/install-launch-agent.sh

uninstall:
	scripts/uninstall.sh
