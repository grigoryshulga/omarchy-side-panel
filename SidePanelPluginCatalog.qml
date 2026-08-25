import QtQuick
import qs.Commons
import qs.Ui

Rectangle {
  id: root

  property var availablePlugins: []
  property int itemCount: 0
  property int maximumItemCount: 0
  property bool itemLimitReached: false
  property color foreground: Color.popups.text

  signal closeRequested()
  signal pluginAddRequested(string pluginId)

  anchors.fill: parent
  visible: false
  z: 10
  color: Qt.rgba(0, 0, 0, 0.56)

  MouseArea {
    anchors.fill: parent
    onClicked: root.closeRequested()
  }

  Rectangle {
    anchors.centerIn: parent
    width: Math.min(parent.width - Style.space(36), Style.space(420))
    height: Math.min(parent.height - Style.space(36), Style.space(520))
    radius: Style.cornerRadius
    color: Color.popups.background
    border.width: 1
    border.color: Color.popups.border

    MouseArea { anchors.fill: parent; onClicked: {} }

    Item {
      anchors.fill: parent
      anchors.margins: Style.space(14)

      Item {
        id: titleRow
        anchors.top: parent.top
        width: parent.width
        height: Math.max(title.implicitHeight, close.implicitHeight)

        Text {
          id: title
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: root.itemLimitReached ? "PANEL LIMIT REACHED"
            : "ADD PLUGIN · " + root.itemCount + "/" + root.maximumItemCount
          color: root.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.title
          font.bold: true
        }

        Text {
          id: close
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          text: "x"
          color: root.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.subtitle

          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.closeRequested()
          }
        }
      }

      ListView {
        visible: !root.itemLimitReached
        anchors.top: titleRow.bottom
        anchors.topMargin: Style.space(10)
        anchors.bottom: parent.bottom
        width: parent.width
        clip: true
        spacing: Style.space(5)
        model: root.availablePlugins

        delegate: Rectangle {
          required property var modelData
          width: ListView.view ? ListView.view.width : 0
          height: Math.round(Style.space(48))
          radius: Style.cornerRadius / 2
          color: rowHover.containsMouse
            ? Style.hoverFillFor(root.foreground, Color.accent)
            : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.035)

          Text {
            anchors.left: parent.left
            anchors.leftMargin: Style.space(10)
            anchors.right: add.left
            anchors.rightMargin: Style.space(10)
            anchors.top: parent.top
            anchors.topMargin: Style.space(6)
            text: String(modelData.label)
            textFormat: Text.PlainText
            color: root.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            elide: Text.ElideRight
          }

          Text {
            anchors.left: parent.left
            anchors.leftMargin: Style.space(10)
            anchors.right: add.left
            anchors.rightMargin: Style.space(10)
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Style.space(6)
            text: modelData.enabled ? String(modelData.description) : "Enable and add to side panel"
            textFormat: Text.PlainText
            color: root.foreground
            opacity: 0.56
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }

          Text {
            id: add
            anchors.right: parent.right
            anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            text: "+"
            color: root.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.subtitle
          }

          MouseArea {
            id: rowHover
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.pluginAddRequested(String(modelData.id))
          }
        }

        Text {
          anchors.centerIn: parent
          visible: root.availablePlugins.length === 0
          text: "All installed plugins are already in this list."
          color: root.foreground
          opacity: 0.64
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
        }
      }

      Text {
        visible: root.itemLimitReached
        anchors.centerIn: parent
        width: parent.width - Style.space(24)
        text: "Remove a plugin before adding another one. The Side Panel can contain up to "
          + root.maximumItemCount + " plugins."
        textFormat: Text.PlainText
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        color: root.foreground
        opacity: 0.7
        font.family: Style.font.family
        font.pixelSize: Style.font.body
      }
    }
  }
}
