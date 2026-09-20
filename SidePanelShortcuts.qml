import QtQuick
import qs.Commons

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

      SidePanelActionButton {
        id: close
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        icon: "\uf00d"
        text: "Close"
        foreground: root.foreground
        onClicked: root.closeRequested()
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
            id: shortcutRow
            required property var modelData
            width: list.width
            height: shortcutRow.modelData.section ? Math.round(Style.space(28))
              : Math.max(Math.round(Style.space(34)), action.implicitHeight + Style.space(8))

            Text {
              visible: !!shortcutRow.modelData.section
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: shortcutRow.modelData.section || ""
              color: root.foreground
              opacity: 0.6
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }

            Rectangle {
              id: keysChip
              visible: !shortcutRow.modelData.section
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              width: Math.min(Math.round(Style.space(174)), parent.width * 0.52)
              height: Math.max(Math.round(Style.space(24)), parent.height - Style.space(8))
              radius: Style.cornerRadius
              color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.07)
              Text {
                anchors.fill: parent
                anchors.margins: Style.space(4)
                text: shortcutRow.modelData.keys || ""
                textFormat: Text.PlainText
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                color: Color.accent
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
              }
            }

            Text {
              id: action
              visible: !shortcutRow.modelData.section
              anchors.left: keysChip.right
              anchors.leftMargin: Style.space(10)
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: shortcutRow.modelData.action || ""
              textFormat: Text.PlainText
              wrapMode: Text.WordWrap
              color: root.foreground
              opacity: 0.78
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }
          }
        }
      }
    }
  }
}
