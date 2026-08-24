#!/usr/bin/env bash
set -euo pipefail

project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cache_dir=$(mktemp -d)
trap 'rm -rf "$cache_dir"' EXIT

adapt() {
  local source_dir=$1
  local entry_point=$2
  local plugin_id=$3
  bash "$project_dir/bin/omarchy-side-panel-adapt" "$source_dir" "$entry_point" "$cache_dir" "$plugin_id" "$project_dir"
}

bluetooth_output=$(adapt /usr/share/omarchy/shell/plugins/panels/bluetooth Panel.qml omarchy.bluetooth)
bluetooth_panel=${bluetooth_output#file://}
test -f "$bluetooth_panel"
test -f "$(dirname "$bluetooth_panel")/SidePanelHost.qml"
test -f "$(dirname "$bluetooth_panel")/SidePanelDisabledIpc.qml"
test -f "$(dirname "$bluetooth_panel")/SidePanelHiddenBarButton.qml"
grep -q 'property var sidePanelHost: null' "$bluetooth_panel"
grep -q 'SidePanelHost {' "$bluetooth_panel"
grep -q 'anchors.fill: parent' "$bluetooth_panel"
grep -q 'sidePanelHost: root.sidePanelHost' "$bluetooth_panel"
grep -q 'SidePanelDisabledIpc {' "$bluetooth_panel"
grep -q 'SidePanelHiddenBarButton {' "$bluetooth_panel"
! grep -q 'function sidePanelDeactivate()' "$bluetooth_panel"
! grep -q 'KeyboardPanel {' "$bluetooth_panel"
qmllint -I /usr/share/omarchy/shell "$bluetooth_panel"

weather_output=$(adapt /usr/share/omarchy/shell/plugins/panels/weather BarWidget.qml omarchy.weather)
weather_panel=${weather_output#file://}
test -f "$weather_panel"
grep -q 'SidePanelHost {' "$weather_panel"
! grep -q 'KeyboardPanel {' "$weather_panel"
qmllint -I /usr/share/omarchy/shell "$weather_panel"

mkdir "$cache_dir/unsafe-source"
touch "$cache_dir/outside.qml"
if adapt "$cache_dir/unsafe-source" ../outside.qml unsafe.plugin; then
  exit 1
fi

mkdir "$cache_dir/symlink-source"
ln -s /usr/share/omarchy/shell/plugins/panels/bluetooth/Panel.qml "$cache_dir/symlink-source/Panel.qml"
if adapt "$cache_dir/symlink-source" Panel.qml symlink.plugin; then
  exit 1
fi
