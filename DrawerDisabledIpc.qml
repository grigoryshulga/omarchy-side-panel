import QtQuick

// Keeps transformed panel source parseable without registering a second IPC
// target that would compete with the live bar widget.
QtObject {
    property string target: ""
    property bool enabled: false
}
