import QtQuick
import qs.Commons
import qs.Ui

Item {
  id: root

  property color foreground: Color.popups.text

  signal closeRequested()

  visible: false

  Column {
    anchors.fill: parent
    anchors.margins: Style.space(14)
    spacing: Style.space(12)

    Item {
      width: parent.width
      height: Math.max(title.implicitHeight, close.height)

      Text {
        id: title
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        text: "SHORTCUTS"
        color: root.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.title
        font.bold: true
      }

      Rectangle {
        id: close
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        readonly property bool expanded: closeHover.containsMouse
        width: expanded ? Math.round(Style.space(80)) : Math.round(Style.space(28))
        height: Math.round(Style.space(28))
        radius: Style.cornerRadius > 0 ? height / 2 : 0
        clip: true
        color: closeHover.containsMouse
          ? Style.hoverFillFor(root.foreground, Color.accent)
          : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.06)

        Behavior on width { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

        Row {
          anchors.centerIn: parent
          spacing: Style.space(5)
          Text { text: "\uf00d"; color: root.foreground; font.family: Style.font.family; font.pixelSize: Style.font.caption }
          Text { visible: close.expanded; text: "Close"; color: root.foreground; font.family: Style.font.family; font.pixelSize: Style.font.caption }
        }

        MouseArea {
          id: closeHover
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.closeRequested()
        }
      }
    }

    Text {
      width: parent.width
      text: "Use these shortcuts while the Side Panel is open. H, J, K and L mirror the arrow keys."
      textFormat: Text.PlainText
      wrapMode: Text.WordWrap
      color: root.foreground
      opacity: 0.7
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
    }

    Flickable {
      id: viewport
      width: parent.width
      height: parent.height - y
      clip: true
      contentWidth: width
      contentHeight: list.height
      boundsBehavior: Flickable.StopAtBounds

      Column {
        id: list
        width: viewport.width
        spacing: Style.space(2)

        Repeater {
          model: [
            { section: "GENERAL" },
            { keys: "Alt + S", action: "Open or close Settings" },
            { keys: "Alt + ?", action: "Open or close this help page" },
            { keys: "Alt + P", action: "Pin or unpin the Side Panel" },
            { keys: "Alt + E", action: "Enter or leave Edit mode" },
            { keys: "Alt + R", action: "Rename the current Side Panel page" },
            { keys: "Alt + 1…9", action: "Switch Side Panel page" },
            { keys: "Alt + ← / →", action: "Previous or next page" },
            { keys: "Ctrl + Tab", action: "Focus next Side Panel item" },
            { keys: "Ctrl + Shift + Tab", action: "Focus previous Side Panel item" },
            { section: "EDIT MODE" },
            { keys: "Alt + C", action: "Create a Side Panel page" },
            { keys: "Alt + X", action: "Remove the current Side Panel page" },
            { keys: "Alt + +", action: "Add a plugin" },
            { keys: "Alt + -", action: "Remove the focused Side Panel item" },
            { keys: "Alt + Space", action: "Expand or collapse the focused item" },
            { keys: "Alt + ↑ / ↓, K / J", action: "Move the focused item vertically" },
            { keys: "Alt + ← / →, H / L", action: "Move the focused item horizontally" },
            { keys: "Alt + Ctrl + ↑ / ↓, K / J", action: "Resize the focused item height" },
            { keys: "Alt + Ctrl + ← / →, H / L", action: "Resize the focused item width" }
          ]

          delegate: Item {
            required property var modelData
            width: list.width
            height: modelData.section ? Math.round(Style.space(28))
              : Math.max(Math.round(Style.space(34)), action.implicitHeight + Style.space(10))

            Text {
              visible: !!parent.modelData.section
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: parent.modelData.section || ""
              color: root.foreground
              opacity: 0.6
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }

            Text {
              id: keys
              visible: !parent.modelData.section
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              width: Math.min(Math.round(Style.space(174)), parent.width * 0.52)
              text: parent.modelData.keys || ""
              textFormat: Text.PlainText
              elide: Text.ElideRight
              color: root.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              font.bold: true
            }

            Text {
              id: action
              visible: !parent.modelData.section
              anchors.left: keys.right
              anchors.leftMargin: Style.space(10)
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: parent.modelData.action || ""
              textFormat: Text.PlainText
              wrapMode: Text.WordWrap
              color: root.foreground
              opacity: 0.72
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }
          }
        }
      }
    }
  }
}
