.PHONY: test run package release-zip install uninstall

test:
	swift test

run:
	scripts/dev-run.sh

package:
	scripts/package-app.sh

release-zip:
	scripts/package-release-zip.sh

install:
	scripts/install-launch-agent.sh

uninstall:
	scripts/uninstall.sh
