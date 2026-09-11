pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import qs.Commons
import qs.Ui as Ui

Rectangle {
    id: row
    required property var app
    required property var bookmark
    property bool selected: false
    property bool editRequested: false
    readonly property bool expanded: app.expandedId === bookmark.id
    readonly property bool ready: app.loadedNoteId === bookmark.id
    readonly property string saveState: {
        var ignored = app.revision;
        return app.store.drafts[bookmark.id] ? app.store.failed ? "Unsaved" : "Saving…" : "Saved";
    }
    signal select()
    signal navigate(int delta)
    color: selected ? Style.selectedAccentFill : "transparent"
    border.color: title.activeFocus ? Color.accent : "transparent"
    border.width: 1
    implicitHeight: body.implicitHeight + Style.space(16)
    function focusTitle() { title.forceActiveFocus(); }
    function focusEditor() {
        if (!editRequested || !ready || !expanded || !title.activeFocus) return;
        editRequested = false;
        editor.forceActiveFocus();
        editor.cursorPosition = editor.length;
    }
    onReadyChanged: if (ready) Qt.callLater(focusEditor)
    onExpandedChanged: if (!expanded) editRequested = false

    ColumnLayout {
        id: body
        x: Style.space(12); y: Style.space(8)
        width: parent.width - Style.space(24)
        spacing: Style.space(10)
        RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(12)
            Item {
                Layout.preferredWidth: Style.space(20); Layout.preferredHeight: Style.space(20)
                Image {
                    id: favicon
                    anchors.fill: parent
                    source: row.bookmark.favicon ? "data:image/png;base64," + row.bookmark.favicon : ""
                    sourceSize: Qt.size(32, 32); fillMode: Image.PreserveAspectFit
                }
                Text { visible: favicon.status !== Image.Ready; anchors.centerIn: parent; text: "◇"; textFormat: Text.PlainText; color: Color.accent; font.family: Style.fontFamily; font.pixelSize: Style.fontToken("body", Style.fontPx(1)) }
            }
            Item {
                id: title
                objectName: "bookmarkTitle"
                Layout.fillWidth: true
                implicitHeight: pageTitle.implicitHeight + Style.space(12)
                activeFocusOnTab: true
                Accessible.role: Accessible.Link
                Accessible.name: row.bookmark.title
                Accessible.description: row.bookmark.url
                Accessible.onPressAction: row.app.openLink(row.bookmark.url)
                Keys.onReturnPressed: row.app.openLink(row.bookmark.url)
                Keys.onEnterPressed: row.app.openLink(row.bookmark.url)
                Keys.onDownPressed: row.navigate(1)
                Keys.onUpPressed: row.navigate(-1)
                Keys.onRightPressed: if (!row.expanded) row.app.expand(row.bookmark.id)
                Keys.onLeftPressed: { if (row.expanded) { row.app.flush(); row.app.expandedId = 0; } else row.app.focusFolders(); }
                Keys.onPressed: function(event) {
                    if (event.text === "/") { row.app.focusSearch(); event.accepted = true; }
                    else if (event.text === "?") { row.app.beginForm("help"); event.accepted = true; }
                    else if (!(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) {
                        if (event.key === Qt.Key_R) { row.app.beginForm("renameBookmark", row.bookmark.id, row.bookmark.title); event.accepted = true; }
                        else if (event.key === Qt.Key_D) { row.app.beginForm("deleteBookmark", row.bookmark.id); event.accepted = true; }
                        else if (event.key === Qt.Key_E) {
                            if (!row.expanded) row.app.expand(row.bookmark.id);
                            row.editRequested = row.expanded;
                            Qt.callLater(row.focusEditor);
                            event.accepted = true;
                        }
                        else if (event.key === Qt.Key_F) {
                            if (!row.expanded) row.app.expand(row.bookmark.id);
                            Qt.callLater(function() {
                                if (row.expanded && title.activeFocus) { folder.forceActiveFocus(); folder.popup.open(); }
                            });
                            event.accepted = true;
                        }
                    }
                }
                onActiveFocusChanged: { if (activeFocus) row.select(); else row.editRequested = false; }
                Text {
                    id: pageTitle
                    anchors.left: parent.left; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                    text: row.bookmark.title; textFormat: Text.PlainText; wrapMode: Text.Wrap
                    color: Color.foreground; font.family: Style.fontFamily; font.pixelSize: Style.fontToken("body", Style.fontPx(1))
                }
                MouseArea { id: mouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { title.forceActiveFocus(); row.app.openLink(row.bookmark.url); } }
                Controls.ToolTip {
                    visible: mouse.containsMouse || title.activeFocus
                    delay: 600
                    contentItem: Text { text: row.bookmark.url; textFormat: Text.PlainText; color: Color.foreground; font.family: Style.fontFamily; wrapMode: Text.Wrap; width: Math.min(implicitWidth, 500) }
                    background: Rectangle { color: Color.background; border.color: Color.accent; border.width: 1 }
                }
            }
            Ui.Button {
                text: row.expanded ? "⌄ Note" : row.bookmark.hasNote ? "› Note" : "› Add note"
                focusable: true
                Accessible.name: row.expanded ? "Collapse note" : "Expand note"
                onClicked: row.app.expand(row.bookmark.id)
            }
        }
        ColumnLayout {
            visible: row.expanded
            Layout.fillWidth: true
            Layout.leftMargin: Style.space(32)
            Controls.ScrollView {
                Layout.fillWidth: true
                Layout.preferredHeight: Style.space(160)
                clip: true
                Controls.TextArea {
                    id: editor
                    objectName: "noteEditor"
                    text: row.app.noteText(row.bookmark.id)
                    textFormat: TextEdit.PlainText
                    enabled: row.ready
                    placeholderText: row.ready ? "Add a note…" : "Loading note…"
                    Accessible.name: "Note for " + row.bookmark.title
                    color: Color.foreground; placeholderTextColor: Qt.alpha(Color.foreground, 0.55)
                    selectionColor: Color.accent; selectedTextColor: Color.background
                    font.family: Style.fontFamily; font.pixelSize: Style.fontToken("body", Style.fontPx(1))
                    wrapMode: TextEdit.Wrap
                    selectByMouse: true
                    background: Rectangle { color: Color.background; border.color: editor.activeFocus ? Color.accent : Style.normalBorderColor; border.width: 1 }
                    onTextChanged: if (activeFocus && row.ready && text !== row.app.noteText(row.bookmark.id)) row.app.editNote(row.bookmark.id, text)
                    onActiveFocusChanged: if (!activeFocus) row.app.flush()
                    Keys.onEscapePressed: { row.app.flush(); row.app.expandedId = 0; row.focusTitle(); }
                    Keys.onTabPressed: folder.forceActiveFocus()
                }
            }
            RowLayout {
                Layout.fillWidth: true
                Text { text: row.ready ? row.saveState : ""; textFormat: Text.PlainText; color: row.saveState === "Unsaved" ? Color.urgent : Color.foreground; opacity: 0.7; font.family: Style.fontFamily; font.pixelSize: Style.fontToken("body-small", Style.fontPx(0.917)) }
                Item { Layout.fillWidth: true }
                FolderPicker {
                    id: folder
                    objectName: "bookmarkFolderPicker"
                    Layout.preferredWidth: Math.min(Style.space(180), row.width / 2)
                    entries: row.app.moveFolders; selectedId: row.bookmark.folderId || 0
                    Accessible.name: "Bookmark folder"
                    onChosen: function(id) { row.app.mutate({ op: "move", id: row.bookmark.id, folderId: id || null }); }
                    Connections {
                        target: folder.popup
                        function onClosed() { Qt.callLater(row.focusTitle); }
                    }
                }
                Ui.Button {
                    text: "More"; focusable: true
                    onClicked: menu.open()
                    Controls.Menu {
                        id: menu
                        Controls.MenuItem { objectName: "copyLink"; text: "Copy link"; onTriggered: row.app.copyLink(row.bookmark.url) }
                        Controls.MenuItem { text: "Rename bookmark"; onTriggered: row.app.beginForm("renameBookmark", row.bookmark.id, row.bookmark.title) }
                        Controls.MenuItem { text: "Delete bookmark…"; onTriggered: row.app.beginForm("deleteBookmark", row.bookmark.id) }
                    }
                }
            }
        }
        Text {
            visible: !row.expanded && row.saveState !== "Saved"
            text: row.saveState; textFormat: Text.PlainText
            color: Color.urgent; font.family: Style.fontFamily; font.pixelSize: Style.fontToken("body-small", Style.fontPx(0.917))
        }
    }
}
