CONFIG ?= release
VERSION ?= 0.1.0
BUILD_NUMBER ?= 1
ARCHS ?= --arch arm64 --arch x86_64
INSTALL_DIR ?= /Applications
APP = build/Clipjar.app
BIN_DIR = $(shell swift build -c $(CONFIG) $(ARCHS) --show-bin-path)

.PHONY: build test clean

build:
	swift build -c $(CONFIG) $(ARCHS)

test:
	swift test

clean:
	rm -rf .build build
