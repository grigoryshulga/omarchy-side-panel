import QtQuick

// Drop-in host for a transformed standard Omarchy KeyboardPanel. It preserves
// the panel's content tree but renders it inside Drawer rather than mapping a
// separate layer-shell surface.
Item {
    id: root

    property Item anchorItem: null
    property var owner: null
    property var bar: null
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

    function fittedContentWidth(width, cap) {
        var desired = Math.max(1, Number(width) || 1);
        var maximum = cap === undefined ? width : Number(cap);
        return Math.round(Math.min(desired, maximum > 0 ? maximum : desired));
    }

    function fittedContentHeight(height, cap) {
        var desired = Math.max(1, Number(height) || 1);
        var maximum = cap === undefined ? height : Number(cap);
        return Math.round(Math.min(desired, maximum > 0 ? maximum : desired));
    }

    function cappedContentHeight(height) {
        return Math.round(Math.min(Math.max(1, Number(height) || 1), root.height));
    }

    visible: open
    onOpenChanged: {
        if (open && focusTarget)
            Qt.callLater(function() {
            if (root.open && root.focusTarget)
                root.focusTarget.forceActiveFocus();

        });

    }

    Item {
        id: contentHolder

        anchors.fill: parent
    }

}
