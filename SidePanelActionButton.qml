import QtQuick
import qs.Commons

// Compact expanding pill, matching the Dashboard's Ui.DashboardActionButton so
// both plugins share one control language.
Rectangle {
  id: root

  property string icon: ""
  property string text: ""
  property bool accent: false
  property bool active: false
  property bool expandOnHover: true
  property bool alwaysExpanded: false
  property color foreground: Color.popups.text
  signal clicked()

  readonly property bool hasIcon: icon.length > 0
  readonly property bool expanded: hasIcon && text.length > 0
    && (alwaysExpanded || (expandOnHover && mouse.containsMouse))
  readonly property real compactWidth: Style.space(28)
  readonly property real expandedWidth: content.implicitWidth + Style.space(20)

  width: hasIcon ? (expanded ? Math.max(compactWidth, expandedWidth) : compactWidth)
    : Math.max(Style.space(34), labelOnly.implicitWidth + Style.spacing.md * 2)
  height: Style.space(28)
  radius: Style.cornerRadius > 0 ? height / 2 : 0
  clip: true
  opacity: enabled ? 1 : 0.42
  color: accent ? Color.accent
    : (active ? Style.selectedFillFor(foreground, Color.accent)
      : (mouse.containsMouse ? Style.hoverFillFor(foreground, Color.accent)
        : Qt.rgba(foreground.r, foreground.g, foreground.b, 0.06)))

  Behavior on width { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

  Row {
    id: content
    anchors.centerIn: parent
    spacing: Style.space(5)
    visible: root.hasIcon
    Text {
      textFormat: Text.PlainText
      text: root.icon
      color: root.accent ? Color.background : root.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      font.bold: true
    }
    Text {
      textFormat: Text.PlainText
      visible: root.expanded
      text: root.text
      color: root.accent ? Color.background : root.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }
  }

  Text {
    textFormat: Text.PlainText
    id: labelOnly
    anchors.centerIn: parent
    visible: !root.hasIcon
    text: root.text
    color: root.accent ? Color.background : root.foreground
    font.family: Style.font.family
    font.pixelSize: Style.font.bodySmall
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    enabled: root.enabled
    hoverEnabled: true
    cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: root.clicked()
  }
}
