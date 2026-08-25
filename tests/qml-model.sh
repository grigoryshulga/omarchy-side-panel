#!/usr/bin/env bash
set -euo pipefail

project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
runner=${QMLTESTRUNNER:-/usr/lib/qt6/bin/qmltestrunner}
qml_config_dir=$(mktemp -d)
trap 'rmdir -- "$qml_config_dir" 2>/dev/null || true' EXIT

if [[ ! -x "$runner" ]]; then
  printf 'Qt 6 qmltestrunner not found: %s\n' "$runner" >&2
  exit 1
fi

XDG_CONFIG_HOME="$qml_config_dir" "$runner" \
  -input "$project_dir/tests/qml/tst_SidePanelModel.qml" \
  -import "$project_dir" \
  -o -,txt \
  "$@"
