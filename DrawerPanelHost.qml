import QtQuick

// Drop-in host for a transformed standard Omarchy KeyboardPanel. It preserves
// the panel's content tree but renders it inside Drawer rather than mapping a
// separate layer-shell surface.
Item {
  id: root

  property Item anchorItem: null
  property var owner: null
  property var bar: null
  property var drawerHost: null
  property var page: null
  property bool open: true
  property Item focusTarget: null
  property int padding: 0
  property int margin: 0
  property int gap: 0
  property bool centerOnBar: false
  property var borderSpec: null
  property int contentWidth: width
  property int contentHeight: height
  default property alias contentItem: contentHolder.children

  function fittedContentWidth(value, cap) {
    var desired = Math.max(1, Number(value) || 1)
    var maximum = root.width > 0 ? root.width : desired
    if (cap !== undefined && Number(cap) > 0) maximum = Math.min(maximum, Number(cap))
    return Math.round(Math.min(desired, maximum))
  }

  function fittedContentHeight(value, cap) {
    var desired = Math.max(1, Number(value) || 1)
    var maximum = root.height > 0 ? root.height : desired
    if (cap !== undefined && Number(cap) > 0) maximum = Math.min(maximum, Number(cap))
    return Math.round(Math.min(desired, maximum))
  }

  function cappedContentHeight(value) {
    var desired = Math.max(1, Number(value) || 1)
    return Math.round(Math.min(desired, root.height > 0 ? root.height : desired))
  }

  function focusPanel() {
    if (focusTarget) focusTarget.forceActiveFocus()
  }

  visible: open
  // This sits above the embedded panel's key catcher. Escape must close the
  // containing Drawer rather than only changing the panel's local state.
  Keys.priority: Keys.BeforeItem
  Keys.onPressed: function(event) {
    if (event.key === Qt.Key_Escape && root.open && drawerHost && typeof drawerHost.handleEscape === "function") {
      drawerHost.handleEscape()
      event.accepted = true
    } else if (event.key === Qt.Key_Tab && (event.modifiers & Qt.ControlModifier)
        && drawerHost && typeof drawerHost.focusKeyboardPlugin === "function") {
      drawerHost.focusKeyboardPlugin((event.modifiers & Qt.ShiftModifier) ? -1 : 1)
      event.accepted = true
    }
  }
  onOpenChanged: {
    if (open && focusTarget) {
      Qt.callLater(function() {
        if (root.open && root.focusTarget) root.focusTarget.forceActiveFocus()
      })
    } else if (!open && drawerHost && page && typeof drawerHost.panelClosed === "function") {
      drawerHost.panelClosed(page)
    }
  }

  Item {
    id: contentHolder
    anchors.fill: parent
  }

}
