#!/usr/bin/env bash
# Every test in one go: the theme's, Studio's, the upgrade from an older
# version, and the checks against the Omarchy installed here (which skip
# themselves where there is none, as in CI). Run it after changing the theme
# or Studio, and after `omarchy-update`.
#
#   tests/run.sh           all of it
#   tests/run.sh --quick   without building Studio (the node tests only)
#
# The running shell has a check of its own: ./install.sh --doctor
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

failed=()
step() {
  local name=$1
  shift
  printf '\033[1m==>\033[0m %s\n' "$name"
  "$@" || failed+=("$name")
}

step "the scripts parse" bash -n install.sh backup.sh tests/run.sh studio/run.sh studio/dev.sh studio/install-desktop.sh studio/get.sh studio/package.sh
for test in tests/*.test.js studio/tests/*.test.js; do
  step "$test" node "$test"
done

if [[ ${1:-} != --quick ]]; then
  export QMAKE=${QMAKE:-qmake6}
  step "studio: cargo test" bash -c 'cd studio && cargo test -q'
  step "studio: clippy" bash -c 'cd studio && cargo clippy -q --all-targets -- -D warnings'
  qmltestrunner=$(command -v qmltestrunner6 || command -v qmltestrunner || echo /usr/lib/qt6/bin/qmltestrunner)
  step "studio: QML tests" bash -c "cd studio && QT_QPA_PLATFORM=offscreen '$qmltestrunner' -input tests/qml"
fi

if (( ${#failed[@]} )); then
  printf '\nFailed:\n' >&2
  printf '  %s\n' "${failed[@]}" >&2
  exit 1
fi
printf '\nAll passed\n'
