pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons

// The inline folder name field, in the sidebar or in the narrow header.
Rectangle {
    id: root
    objectName: "folderEditor"
    required property var app
    property bool wide: false
    implicitHeight: layout.implicitHeight + Style.space(10)
    color: Style.focusFillColor
    border.color: Commons.Color.accent
    border.width: 1
    GridLayout {
        id: layout
        anchors.fill: parent
        anchors.margins: Style.space(5)
        columns: root.wide ? 3 : 2
        columnSpacing: Style.space(5)
        rowSpacing: Style.space(5)
        Field {
            id: field
            objectName: "folderField"
            Layout.columnSpan: root.wide ? 1 : 2
            Layout.fillWidth: true
            implicitHeight: Style.space(27)
            bad: root.app.folderError !== ""
            font.pixelSize: Style.font.bodySmall // qmllint disable missing-property
            placeholderText: "Folder name"
            Accessible.name: "Folder name"
            maximumLength: 256
            onTextEdited: root.app.folderText = text
            onAccepted: root.app.saveFolderName()
            Component.onCompleted: { text = root.app.folderText; forceActiveFocus(); selectAll(); }
        }
        KeepButton {
            solid: true
            objectName: "folderSave"
            Layout.fillWidth: !root.wide
            small: true
            label: root.app.folderEdit && root.app.folderEdit.mode === "new" ? "Create" : "Save"
            onClicked: root.app.saveFolderName()
        }
        KeepButton {
            objectName: "folderCancel"
            Layout.fillWidth: !root.wide
            small: true; bordered: true
            label: "Cancel"
            onClicked: root.app.cancelFolderName()
        }
        Label {
            visible: root.app.folderError !== ""
            Layout.columnSpan: root.wide ? 3 : 2
            Layout.fillWidth: true
            text: root.app.folderError
            color: root.app.errorInk
            size: "caption"
            wrapMode: Text.Wrap; elide: Text.ElideNone
        }
    }
}
