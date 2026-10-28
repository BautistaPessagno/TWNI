#!/bin/sh
set -eu

cd "$CI_PRIMARY_REPOSITORY_PATH"
swift test --package-path CoreTests
