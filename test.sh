#!/bin/sh
set -eu
cd "$(dirname "$0")"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/finder-click-fix-tests.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT HUP INT TERM
xcrun clang -std=c17 -fobjc-arc -O0 -g -Wall -Wextra -Werror -mmacosx-version-min=13.0 \
    tests.m -framework AppKit -framework ApplicationServices -framework CoreFoundation -framework ServiceManagement \
    -o "$test_dir/tests"
"$test_dir/tests"
