#!/bin/zsh
# Run RobytyCore tests. Does not install the app. Does not touch live data.
# Extra args go to the runner (example: --filter skipClose).
set -euo pipefail

REPO="${0:A:h:h}"
cd "${REPO}"

echo "→ Робити tests"
swift run RobytyTestRunner -- "$@"
