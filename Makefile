.PHONY: test audit build install

test:
	swift test

audit: test
	python3 scripts/quality_gate.py

build:
	bash scripts/build_app.sh

install:
	bash scripts/install_app.sh
