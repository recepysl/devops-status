.PHONY: build app dmg run install uninstall once selftest test screenshots icon clean

build:
	swift build -c release

app:
	./scripts/build.sh

dmg:
	./scripts/make-dmg.sh

run: app
	open DevOpsStatus.app

install: app
	rm -rf /Applications/DevOpsStatus.app
	cp -R DevOpsStatus.app /Applications/
	open /Applications/DevOpsStatus.app

uninstall:
	./scripts/uninstall.sh

once:
	swift run DevOpsStatus --once

selftest:
	swift run DevOpsStatus --selftest

test:
	./scripts/test.sh

screenshots:
	swift run DevOpsStatus --render-screenshots docs/images

icon:
	./tools/make-icns.sh

clean:
	rm -rf .build DevOpsStatus.app dist
