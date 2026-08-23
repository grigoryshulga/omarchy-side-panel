#!/usr/bin/env bash
set -euo pipefail

project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cache_dir=$(mktemp -d)
trap 'rm -rf "$cache_dir"' EXIT

adapt() {
  local source_dir=$1
  local entry_point=$2
  local output_dir=$3
  bash "$project_dir/bin/omarchy-drawer-adapt" "$source_dir" "$entry_point" "$output_dir" "$project_dir"
}

bluetooth_output=$(adapt /usr/share/omarchy/shell/plugins/panels/bluetooth Panel.qml "$cache_dir/bluetooth")
test -f "$cache_dir/bluetooth/Panel.qml"
test -f "$cache_dir/bluetooth/DrawerPanelHost.qml"
test -f "$cache_dir/bluetooth/DrawerDisabledIpc.qml"
grep -q 'DrawerPanelHost { anchors.fill: parent;' "$cache_dir/bluetooth/Panel.qml"
grep -q 'property var drawerHost: null' "$cache_dir/bluetooth/Panel.qml"
grep -q 'function drawerDeactivate() { root.controller.hide() }' "$cache_dir/bluetooth/Panel.qml"
grep -q 'function close() { if (root.drawerHost) root.drawerHost.close(); else root.controller.hide() }' "$cache_dir/bluetooth/Panel.qml"
grep -q 'if (root.drawerHost) root.drawerHost.close(); else root.controller.hide()' "$cache_dir/bluetooth/Panel.qml"
grep -q 'DrawerDisabledIpc {' "$cache_dir/bluetooth/Panel.qml"
! grep -q 'KeyboardPanel {' "$cache_dir/bluetooth/Panel.qml"
test "$bluetooth_output" = "file://$cache_dir/bluetooth/Panel.qml"

weather_output=$(adapt /usr/share/omarchy/shell/plugins/panels/weather BarWidget.qml "$cache_dir/weather")
test -f "$cache_dir/weather/BarWidget.qml"
test -f "$cache_dir/weather/Panel.qml"
grep -q 'DrawerPanelHost { anchors.fill: parent;' "$cache_dir/weather/Panel.qml"
! grep -q 'KeyboardPanel {' "$cache_dir/weather/Panel.qml"
test "$weather_output" = "file://$cache_dir/weather/Panel.qml"

mkdir "$cache_dir/unsafe-source"
touch "$cache_dir/outside.qml"
if adapt "$cache_dir/unsafe-source" ../outside.qml "$cache_dir/unsafe-output"; then
  exit 1
fi
test ! -e "$cache_dir/unsafe-output"

mkdir "$cache_dir/symlink-source"
ln -s "$cache_dir/symlink-source" "$cache_dir/symlink-output"
if adapt /usr/share/omarchy/shell/plugins/panels/bluetooth Panel.qml "$cache_dir/symlink-output"; then
  exit 1
fi
