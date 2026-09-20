pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons

// Add-plugin browser, matching the Dashboard's PluginCatalog: searchable,
// keyboard-navigable and built from the shared expanding-pill button.
Rectangle {
  id: root

  property var availablePlugins: []
  property int itemCount: 0
  property int maximumItemCount: 0
  property bool itemLimitReached: false
  property string limitMessage: ""
  property color foreground: Color.popups.text
  property string filterText: ""

  signal closeRequested()
  signal pluginAddRequested(string pluginId)

  readonly property var filteredPlugins: {
    var query = filterText.toLowerCase().trim()
    if (!query) return availablePlugins
    return availablePlugins.filter(function(plugin) {
      return String(plugin.label || "").toLowerCase().indexOf(query) >= 0
        || String(plugin.id || "").toLowerCase().indexOf(query) >= 0
        || String(plugin.description || "").toLowerCase().indexOf(query) >= 0
    })
  }

  function activateCurrent() {
    if (filteredPlugins.length === 0 || itemLimitReached) return
    var index = Math.max(0, Math.min(pluginList.currentIndex, filteredPlugins.length - 1))
    pluginAddRequested(String(filteredPlugins[index].id))
  }

  function moveCurrent(delta) {
    if (filteredPlugins.length === 0) return
    var current = pluginList.currentIndex < 0 ? 0 : pluginList.currentIndex
    pluginList.currentIndex = (current + delta + filteredPlugins.length) % filteredPlugins.length
    pluginList.positionViewAtIndex(pluginList.currentIndex, ListView.Contain)
  }

  anchors.fill: parent
  visible: false
  z: 10
  color: Qt.rgba(Color.background.r, Color.background.g, Color.background.b, 0.78)

  MouseArea {
    anchors.fill: parent
    onClicked: root.closeRequested()
  }

  Rectangle {
    anchors.centerIn: parent
    width: Math.min(parent.width - Style.space(36), Style.space(520))
    height: Math.min(parent.height - Style.space(36), Style.space(560))
    radius: Style.cornerRadius
    color: Color.popups.background
    border.width: 1
    border.color: Color.popups.border

    MouseArea { anchors.fill: parent; onClicked: {} }

    Column {
      anchors.fill: parent
      anchors.margins: Style.spacing.lg
      spacing: Style.spacing.md

      Item {
        id: headerRow
        width: parent.width
        height: Math.max(title.implicitHeight, closeButton.height)

        Text {
          id: title
          textFormat: Text.PlainText
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: root.itemLimitReached
            ? "Panel limit reached"
            : (root.filterText.length > 0
              ? "Add plugin · " + root.filteredPlugins.length + " of " + root.availablePlugins.length
              : "Add plugin · " + root.itemCount + "/" + root.maximumItemCount)
          color: root.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.title
          font.bold: true
          elide: Text.ElideRight
          width: parent.width - closeButton.width - Style.space(8)
        }

        SidePanelActionButton {
          id: closeButton
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          icon: "\uf00d"
          text: "Close"
          foreground: root.foreground
          onClicked: root.closeRequested()
        }
      }

      Rectangle {
        visible: !root.itemLimitReached
        height: visible ? Style.space(42) : 0
        width: parent.width
        radius: Style.cornerRadius
        color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.06)
        border.width: 1
        border.color: filterInput.activeFocus ? Color.accent : Color.popups.border

        TextInput {
          id: filterInput
          anchors.fill: parent
          anchors.margins: Style.spacing.sm
          color: root.foreground
          selectionColor: Color.accent
          selectedTextColor: Color.background
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          maximumLength: 160
          focus: root.visible
          onTextChanged: root.filterText = text
          Keys.onEscapePressed: root.closeRequested()
          Keys.onDownPressed: root.moveCurrent(1)
          Keys.onUpPressed: root.moveCurrent(-1)
          Keys.onReturnPressed: root.activateCurrent()
          Keys.onEnterPressed: root.activateCurrent()
        }
        Text {
          textFormat: Text.PlainText
          anchors.left: parent.left
          anchors.leftMargin: Style.spacing.sm
          anchors.verticalCenter: parent.verticalCenter
          visible: filterInput.text.length === 0
          text: "Search installed plugins…"
          color: root.foreground
          opacity: 0.4
          font.family: Style.font.family
          font.pixelSize: Style.font.body
        }
      }

      ListView {
        id: pluginList
        visible: !root.itemLimitReached
        width: parent.width
        height: parent.height - headerRow.height - Style.space(42) - parent.spacing * 2
        clip: true
        spacing: Style.spacing.sm
        model: root.filteredPlugins
        currentIndex: count > 0 ? 0 : -1
        highlightMoveDuration: 80
        highlight: Rectangle {
          radius: Style.cornerRadius
          color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.16)
          border.width: 1
          border.color: Color.accent
        }

        delegate: Rectangle {
          id: pluginRow
          required property var modelData
          required property int index
          width: ListView.view ? ListView.view.width : 0
          height: Math.round(Style.space(72))
          radius: Style.cornerRadius
          color: rowHover.containsMouse || ListView.isCurrentItem
            ? Style.hoverFillFor(root.foreground, Color.accent)
            : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.035)
          border.width: 1
          border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.1)

          Column {
            anchors.left: parent.left
            anchors.right: addButton.left
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Style.spacing.md
            anchors.rightMargin: Style.spacing.md
            spacing: Style.spacing.xs

            Text {
              textFormat: Text.PlainText
              width: parent.width
              text: String(pluginRow.modelData.label)
              color: root.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              font.bold: true
              elide: Text.ElideRight
            }
            Text {
              textFormat: Text.PlainText
              width: parent.width
              text: String(pluginRow.modelData.description || pluginRow.modelData.id)
              color: root.foreground
              opacity: 0.58
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }
            Text {
              textFormat: Text.PlainText
              width: parent.width
              visible: !pluginRow.modelData.enabled
              text: "Will be enabled when added"
              color: Color.accent
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }
          }

          SidePanelActionButton {
            id: addButton
            anchors.right: parent.right
            anchors.rightMargin: Style.spacing.md
            anchors.verticalCenter: parent.verticalCenter
            icon: "\uf067"
            text: "Add"
            accent: true
            foreground: root.foreground
            onClicked: root.pluginAddRequested(String(pluginRow.modelData.id))
          }

          MouseArea {
            id: rowHover
            anchors.fill: parent
            anchors.rightMargin: addButton.width + Style.spacing.lg
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onDoubleClicked: root.pluginAddRequested(String(pluginRow.modelData.id))
            onClicked: pluginList.currentIndex = pluginRow.index
          }
        }

        Text {
          anchors.centerIn: parent
          visible: pluginList.count === 0
          width: parent.width - Style.space(24)
          text: root.availablePlugins.length === 0
            ? "No other installed plugins were found."
            : "No matching plugins."
          color: root.foreground
          opacity: 0.64
          horizontalAlignment: Text.AlignHCenter
          wrapMode: Text.WordWrap
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
        }
      }

      Text {
        visible: root.itemLimitReached
        anchors.horizontalCenter: parent.horizontalCenter
        width: parent.width - Style.space(24)
        text: "Remove an item before adding another one. " + root.limitMessage
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

  onVisibleChanged: if (visible) {
    filterText = ""
    pluginList.currentIndex = filteredPlugins.length > 0 ? 0 : -1
    Qt.callLater(function() { filterInput.forceActiveFocus() })
  }
  onFilteredPluginsChanged: pluginList.currentIndex = filteredPlugins.length > 0 ? 0 : -1
}
