.PHONY: test test-release audit build install preflight clean

test:
	swift test

test-release:
	swift test -c release

audit: test test-release
	python3 scripts/quality_gate.py

build:
	bash scripts/build_app.sh

install:
	bash scripts/install_app.sh

preflight:
	bash scripts/release_preflight.sh

clean:
	rm -rf .build dist
