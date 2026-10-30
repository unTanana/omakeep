pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons
import "Icons.js" as Icons

// Add a bookmark in place, above the list.
Rectangle {
    id: root
    objectName: "addSheet"
    required property var app
    readonly property bool stacked: app.compact
    implicitHeight: layout.implicitHeight + Style.space(20)
    color: Style.normalFill
    function focusLink() { link.forceActiveFocus(); link.selectAll(); }
    Rectangle { width: 2; height: parent.height; color: Commons.Color.accent }
    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Commons.Color.muted }
    ColumnLayout {
        id: layout
        x: Style.space(10)
        y: Style.space(10)
        width: parent.width - Style.space(20)
        spacing: Style.space(7)
        Label {
            Layout.fillWidth: true
            text: "Add bookmark"
            color: root.app.hotInk
            size: "subtitle"; font.bold: true
        }
        GridLayout {
            Layout.fillWidth: true
            columns: root.stacked ? 1 : 2
            columnSpacing: Style.space(8)
            rowSpacing: root.stacked ? Style.space(2) : Style.space(7)
            Label {
                Layout.preferredWidth: Style.space(47)
                text: "Link"
                color: root.app.dim
                size: "bodySmall"
            }
            Field {
                id: link
                objectName: "addLink"
                Layout.fillWidth: true
                bad: root.app.addError !== ""
                text: root.app.addUrl
                placeholderText: "https://…"
                Accessible.name: "Link"
                maximumLength: 16384
                onTextEdited: root.app.addUrl = text
                onAccepted: root.app.submitAdd()
                Component.onCompleted: root.focusLink()
            }
            Item { visible: !root.stacked && problem.visible; implicitWidth: 1 }
            Label {
                id: problem
                objectName: "addError"
                visible: root.app.addError !== ""
                Layout.fillWidth: true
                text: root.app.addError
                color: root.app.errorInk
                size: "caption"
                wrapMode: Text.Wrap; elide: Text.ElideNone
            }
            Item { visible: !root.stacked && duplicate.visible; implicitWidth: 1 }
            Flow {
                id: duplicate
                objectName: "addDuplicate"
                visible: root.app.addDuplicateId !== 0
                Layout.fillWidth: true
                spacing: Style.space(8)
                Label {
                    width: Math.min(implicitWidth, duplicate.width)
                    height: showIt.height
                    text: "Already saved. Its note and folder stay as they are."
                    size: "caption"
                }
                KeepButton {
                    id: showIt
                    objectName: "addShowIt"
                    small: true; bordered: true
                    label: "Show it"
                    onClicked: root.app.showDuplicate()
                }
            }
            Label {
                Layout.preferredWidth: Style.space(47)
                text: "Title"
                color: root.app.dim
                size: "bodySmall"
            }
            Field {
                id: title
                objectName: "addTitle"
                Layout.fillWidth: true
                text: root.app.addTitle
                placeholderText: "Optional. Uses the site name if empty."
                Accessible.name: "Title, optional"
                maximumLength: 4096
                onTextEdited: root.app.addTitle = text
                onAccepted: root.app.submitAdd()
            }
            Label {
                Layout.preferredWidth: Style.space(47)
                text: "Folder"
                color: root.app.dim
                size: "bodySmall"
            }
            KeepButton {
                id: folderButton
                objectName: "addFolder"
                Layout.alignment: Qt.AlignLeft
                bordered: true
                icon: Icons.folder
                label: root.app.folderName(root.app.addFolderId)
                labelLimit: Style.space(220)
                trailing: Icons.down
                onClicked: root.app.pickAddFolder(folderButton)
            }
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(7)
            Item { Layout.fillWidth: true }
            KeepButton {
                objectName: "addCancel"
                bordered: true
                label: "Cancel"
                onClicked: root.app.closeAdd()
            }
            KeepButton {
                solid: true
                objectName: "addSubmit"
                label: "Add bookmark"
                onClicked: root.app.submitAdd()
            }
        }
    }
}
