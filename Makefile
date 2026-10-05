.PHONY: help build test check package ci release
.DEFAULT_GOAL := help

export VERSION

help:
	@printf '%s\n' 'make build                     Build the native app' 'make test                      Run native model and UI smoke tests' 'make check                     Check project and release metadata' 'make package                   Create universal DMG and ZIP installers' 'make ci                        Run all local checks and package verification' 'make release                   Release the current first version or bump patch' 'make release VERSION=1.1.0     Release a specific version'

build:
	./scripts/build.sh

test:
	./scripts/test.sh

check:
	python3 scripts/check-project.py
	python3 scripts/test-release.py

package:
	./scripts/package.sh

ci:
	./scripts/ci.sh

release:
	python3 scripts/release.py
