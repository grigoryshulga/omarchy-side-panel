pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io
import "HyprlandBlur.js" as HyprlandBlur

// Applies or clears the Hyprland blur layer rule for the Side Panel surface.
// Mirrors qml/appearance/DashboardBlurSettings.qml.
Item {
  id: root

  visible: false
  property bool active: false
  property bool pending: false

  function applyRule() {
    if (ruleProc.running) {
      pending = true
      return
    }
    ruleProc.command = ["hyprctl", "eval", HyprlandBlur.ruleExpression(active)]
    ruleProc.running = true
  }

  function scheduleApply() {
    applyTimer.restart()
  }

  Process {
    id: ruleProc
    onExited: function() {
      if (!root.pending) return
      root.pending = false
      Qt.callLater(root.applyRule)
    }
  }

  Timer {
    id: applyTimer
    interval: 200
    repeat: false
    onTriggered: root.applyRule()
  }

  onActiveChanged: scheduleApply()
  Component.onCompleted: scheduleApply()
}
