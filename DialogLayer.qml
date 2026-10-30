pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons
import qs.Ui as Ui
import "Icons.js" as Icons
import "State.js" as State

// Delete confirmations and the shortcut list, over a dimmed panel.
Rectangle {
    id: root
    objectName: "dialog"
    required property var app
    property string kind: ""
    property var target: null
    readonly property var shortcuts: [
        ["Ctrl F, or / from a bookmark", "Search"], ["Down from search", "First bookmark"], ["Up / Down", "Previous / next bookmark or folder"],
        ["Enter", "Open the page"], ["Left", "Collapse the note, then go to folders"], ["Right", "Enter a folder, or expand a note"],
        ["F", "Move to a folder"], ["E", "Edit the note"], ["R", "Rename bookmark or folder"], ["D", "Delete bookmark or folder"],
        ["Tab", "Next control"], ["Esc", "Back out, then close"], ["Ctrl N", "Add a bookmark"], ["Ctrl Shift N", "New folder"], ["?", "This list"],
        ["Alt Shift K", "In Chrome: save the page"]]
    signal confirmed(string kind, var target)
    signal closed()
    anchors.fill: parent
    visible: kind !== ""
    color: Util.alpha(Commons.Color.background, 0.78)
    function show(newKind, newTarget) {
        target = newTarget || null; kind = newKind;
        Qt.callLater(function() { if (root.kind === "keys") cancel.forceActiveFocus(); else confirm.forceActiveFocus(); });
    }
    function close() {
        if (!kind) return;
        kind = ""; target = null;
        closed();
    }
    MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onClicked: root.close() }
    Ui.BorderSurface {
        anchors.centerIn: parent
        width: Math.min(parent.width - Style.space(27), Style.space(367))
        height: Math.min(parent.height - Style.space(27), box.implicitHeight + Style.space(30))
        color: Commons.Color.background
        borderSpec: Border.flat(root.kind === "keys" ? Commons.Color.accent : Commons.Color.urgent, 2)
        clip: true
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }
        // Shown only when a short panel makes the dialog scroll.
        Rectangle {
            visible: scroller.interactive
            x: parent.width - width - 3
            y: scroller.y + scroller.visibleArea.yPosition * scroller.height
            width: 4
            height: scroller.visibleArea.heightRatio * scroller.height
            color: Commons.Color.muted
        }
        // A short panel scrolls the dialog rather than losing its buttons.
        Flickable {
            id: scroller
            anchors.fill: parent
            anchors.margins: Style.space(15)
            contentHeight: box.implicitHeight
            interactive: contentHeight > height
            boundsBehavior: Flickable.StopAtBounds
            clip: true
            FocusScope {
                width: scroller.width
                height: box.implicitHeight
                Keys.onEscapePressed: root.close()
                Keys.onPressed: function(event) {
                    if (event.key === Qt.Key_Up || event.key === Qt.Key_Down) {
                        let reach = Math.max(0, scroller.contentHeight - scroller.height);
                        scroller.contentY = Math.min(reach, Math.max(0, scroller.contentY + (event.key === Qt.Key_Down ? Style.space(60) : -Style.space(60))));
                    }
                    event.accepted = event.key !== Qt.Key_Tab && event.key !== Qt.Key_Backtab;
                }
                ColumnLayout {
                    id: box
                    width: parent.width
                    spacing: Style.space(8)
                    Label {
                        Layout.fillWidth: true
                        text: root.kind === "keys" ? "Keyboard shortcuts" : root.kind === "bookmark" ? "Delete this bookmark?" : "Delete “" + (root.target ? root.target.name : "") + "”?"
                        color: root.app.hotInk
                        size: "heading"; font.bold: true
                        wrapMode: Text.Wrap; elide: Text.ElideNone
                    }
                    Rectangle {
                        visible: root.kind === "bookmark"
                        Layout.fillWidth: true
                        implicitHeight: what.implicitHeight + Style.space(13)
                        color: Style.hoverFill
                        border.color: root.app.line
                        border.width: 1
                        RowLayout {
                            id: what
                            anchors.fill: parent
                            anchors.margins: Style.space(7)
                            spacing: Style.space(8)
                            Favicon {
                                Layout.alignment: Qt.AlignTop
                                icon: (root.target && root.target.favicon) || ""
                                letter: root.target ? root.app.initial(root.target) : ""
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2
                                Label {
                                    Layout.fillWidth: true
                                    text: root.target ? root.app.rowTitle(root.target) : ""
                                    size: "bodySmall"
                                    wrapMode: Text.WrapAtWordBoundaryOrAnywhere; maximumLineCount: 3
                                }
                                Label {
                                    visible: text !== "Note: "
                                    Layout.fillWidth: true
                                    text: "Note: " + (root.target ? root.target.note : "")
                                    color: root.app.dim
                                    size: "caption"
                                    wrapMode: Text.WrapAtWordBoundaryOrAnywhere; maximumLineCount: 3
                                }
                            }
                        }
                    }
                    Label {
                        visible: root.kind !== "keys"
                        Layout.fillWidth: true
                        text: !root.target ? "" : root.kind === "bookmark" ? (root.target.note ? "The note goes with it. This can't be undone." : "This can't be undone.")
                            : root.target.count ? "Its " + State.plural(root.target.count, "bookmark") + " and their notes stay in All bookmarks. Only the folder goes."
                            : "It's empty, so nothing else changes."
                        size: "bodySmall"
                        wrapMode: Text.Wrap; elide: Text.ElideNone
                    }
                    GridLayout {
                        visible: root.kind === "keys"
                        Layout.fillWidth: true
                        columns: 2
                        columnSpacing: Style.space(12)
                        rowSpacing: Style.space(4)
                        Repeater {
                            model: root.shortcuts.length * 2
                            delegate: Item {
                                id: cell
                                required property int index
                                readonly property var entry: root.shortcuts[Math.floor(index / 2)]
                                readonly property bool isKey: index % 2 === 0
                                Layout.fillWidth: !isKey
                                Layout.alignment: Qt.AlignLeft | Qt.AlignTop
                                implicitWidth: isKey ? keyText.implicitWidth + Style.space(9) : Style.space(100)
                                implicitHeight: keyText.implicitHeight + (cell.isKey ? 2 : 0)
                                Rectangle {
                                    anchors.fill: parent
                                    visible: cell.isKey
                                    color: "transparent"
                                    border.color: root.app.line
                                    border.width: 1
                                }
                                Label {
                                    id: keyText
                                    x: cell.isKey ? Style.space(4) : 0
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: cell.isKey ? implicitWidth : parent.width
                                    wrapMode: cell.isKey ? Text.NoWrap : Text.Wrap
                                    elide: Text.ElideNone
                                    text: cell.entry[cell.isKey ? 0 : 1]
                                    color: cell.isKey ? root.app.hotInk : Commons.Color.foreground
                                    size: cell.isKey ? "caption" : "bodySmall"
                                }
                            }
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: Style.space(5)
                        spacing: Style.space(7)
                        Item { Layout.fillWidth: true }
                        KeepButton {
                            id: cancel
                            objectName: "dialogCancel"
                            bordered: true
                            label: root.kind === "keys" ? "Close" : "Cancel"
                            KeyNavigation.tab: confirm.visible ? confirm : cancel
                            KeyNavigation.backtab: confirm.visible ? confirm : cancel
                            onClicked: root.close()
                        }
                        KeepButton {
                            solid: true
                            id: confirm
                            objectName: "dialogConfirm"
                            visible: root.kind !== "keys"
                            danger: true
                            icon: Icons.trash
                            label: root.kind === "folder" ? "Delete folder" : "Delete bookmark"
                            KeyNavigation.tab: cancel
                            KeyNavigation.backtab: cancel
                            onClicked: { var kind = root.kind, target = root.target; root.close(); root.confirmed(kind, target); }
                        }
                    }
                }
            }
        }
    }
}
