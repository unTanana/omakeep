pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui as Ui
import "Icons.js" as Icons

Ui.BorderSurface {
    id: root
    objectName: "toast"
    property string message: ""
    property bool bad: false
    property var undo: null
    readonly property var alert: Commons.Color.polkit
    visible: false
    color: Commons.Color.background
    borderSpec: Border.flat(bad ? alert.textError : Commons.Color.accent, 1)
    width: Math.min(row.implicitWidth + Style.space(17), parent.width - Style.space(20))
    height: Math.max(Style.space(29), row.implicitHeight + Style.space(10))
    function show(text, isBad, undoAction) {
        message = text; bad = !!isBad; undo = undoAction || null;
        visible = true;
        timer.interval = undoAction ? 6000 : 2600;
        timer.restart();
    }
    Timer { id: timer; onTriggered: root.visible = false }
    MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }
    Row {
        id: row
        x: Style.space(10)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(7)
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 7; height: 7; radius: 3.5
            color: root.bad ? root.alert.textError : Commons.Color.accent
        }
        Label {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, root.parent.width - Style.space(46) - (undoButton.visible ? undoButton.width : 0))
            text: root.message
            size: "bodySmall"
        }
        KeepButton {
            id: undoButton
            objectName: "toastUndo"
            anchors.verticalCenter: parent.verticalCenter
            visible: root.undo !== null
            small: true; bordered: true
            icon: Icons.undo; label: "Undo"
            onClicked: { var action = root.undo; root.visible = false; if (action) action(); }
        }
    }
}
