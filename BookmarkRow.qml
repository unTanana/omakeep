pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons
import qs.Ui as Ui
import "Icons.js" as Icons
import "State.js" as State

// One bookmark. At rest it is plain text, which is what keeps a long list smooth:
// the real buttons, grip, drag, tooltip and note card load when the pointer or the keyboard arrives.
Item {
    id: row
    required property var app
    required property var bookmark
    property bool selected: false
    // Copies, because the model object vanishes before anything loaded in this row is gone.
    readonly property int rowId: bookmark.id
    readonly property string url: bookmark.url
    readonly property string title: app.rowTitle(bookmark)
    readonly property int folderId: bookmark.folderId
    readonly property bool hasNote: bookmark.hasNote
    readonly property bool expanded: app.expandedId === rowId
    readonly property bool renaming: app.renamingId === rowId
    readonly property bool lifted: app.dragBookmark !== null && app.dragBookmark.id === rowId
    readonly property string query: app.appliedQuery
    readonly property string noteState: { var ignored = app.revision; return State.noteState(app.store, rowId, app.savedNoteId); }
    readonly property string note: { var ignored = app.revision; return app.rowNote(bookmark); }
    readonly property bool hot: hover.hovered && !app.modal && app.dragBookmark === null
    readonly property bool titleHot: hot && !actsHover.hovered && !noteHover.hovered && !gripHover.hovered
    readonly property bool linkFound: query !== "" && url.toLowerCase().indexOf(query.toLowerCase()) >= 0
    readonly property bool showNote: note !== "" && !expanded && !renaming
    signal select()
    signal keepInView()
    implicitHeight: column.y + line1.height + line2.height + (showNote ? noteLine.height : 0) + (card.active ? card.height + Style.space(7) : 0) + Style.space(4) + 1
    // What a small KeepButton looks like at rest, drawn where it would draw it.
    component RestButton: Row {
        property alias icon: glyph.text
        property alias label: word.text
        property color ink
        readonly property real room: Style.space(23) - glyph.width
        height: Style.space(23)
        leftPadding: label ? Style.space(7) + 1 : Math.round(room / 2)
        rightPadding: label ? Style.space(7) + 1 : room - leftPadding
        spacing: Style.space(4)
        Glyph { id: glyph; anchors.verticalCenter: parent.verticalCenter; color: parent.ink; font.pixelSize: Style.space(13) }
        Label { id: word; visible: text !== ""; anchors.verticalCenter: parent.verticalCenter; color: parent.ink; size: "caption" }
    }
    opacity: lifted ? 0.35 : 1
    Accessible.role: Accessible.Link
    Accessible.name: title
    Accessible.description: url
    Accessible.onPressAction: app.openLink(url)
    onHeightChanged: if (expanded) keepInView()

    function snapshot() { return app.rowSnapshot(app.rowIndex(rowId)); }
    function menu(x, y) {
        var at = row.mapToItem(app.overlay, x, y);
        app.rowMenu(snapshot(), { x: at.x, y: at.y });
    }

    Rectangle {
        anchors.fill: parent
        color: row.expanded ? Style.normalFill : area.pressed && !row.renaming ? Style.pressedFill : row.hot ? Style.hoverFill : "transparent"
    }
    Rectangle {
        anchors.fill: parent
        visible: row.app.flashId === row.rowId
        color: Style.selectionFill
        opacity: row.app.flashLevel
    }
    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: row.expanded ? Commons.Color.muted : row.app.softLine }
    HoverHandler { id: hover; enabled: !row.app.modal }
    MouseArea {
        id: area
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
        cursorShape: row.expanded || row.renaming ? Qt.ArrowCursor : Qt.PointingHandCursor
        onClicked: function(mouse) {
            row.select();
            if (mouse.button === Qt.RightButton) row.menu(mouse.x, mouse.y);
            else if (mouse.button === Qt.MiddleButton) row.app.openLink(row.url);
            else if (!row.renaming && (!row.expanded || mouse.y < column.y + line1.height)) row.app.openLink(row.url);
        }
    }
    Item {
        visible: !row.app.narrow && !row.expanded
        width: Style.space(11)
        height: parent.height
        HoverHandler { id: gripHover; cursorShape: Qt.OpenHandCursor }
    }
    Favicon {
        x: Style.space(12)
        y: Style.space(5)
        line: row.app.line
        icon: row.bookmark.favicon
        letter: row.app.initial(row.bookmark)
    }
    Item {
        id: column
        x: Style.space(38)
        y: Style.space(5)
        width: row.width - x - Style.space(7)
        Item {
            id: line1
            width: parent.width
            height: row.renaming ? renameBox.height : row.expanded ? Math.max(Style.space(18), wholeTitle.implicitHeight) : Style.space(18)
            HighlightText {
                id: oneLine
                objectName: "bookmarkTitle"
                visible: !row.renaming && !row.expanded
                width: parent.width - outIcon.width - Style.space(7)
                height: parent.height
                source: row.title
                query: row.query
                color: row.titleHot ? Commons.Color.accent : Commons.Color.foreground
                font.underline: row.titleHot
            }
            Loader {
                id: wholeTitle
                active: row.expanded && !row.renaming
                width: parent.width - outIcon.width - Style.space(7)
                sourceComponent: WrappedText {
                    text: row.title
                    query: row.query
                    color: row.titleHot ? Commons.Color.accent : row.app.hotInk
                }
            }
            Glyph {
                id: outIcon
                visible: !row.renaming
                anchors.right: parent.right
                anchors.rightMargin: Style.space(3)
                y: Math.round((Style.space(18) - height) / 2)
                text: Icons.open
                color: row.titleHot ? Commons.Color.accent : row.app.dim
                opacity: row.titleHot ? 1 : 0.65
                font.pixelSize: Style.space(13)
            }
            Loader {
                id: renameBox
                active: row.renaming
                width: parent.width - Style.space(4)
                height: active ? Style.space(23) : 0
                sourceComponent: RowLayout {
                    spacing: Style.space(5)
                    Field {
                        objectName: "renameField"
                        Layout.fillWidth: true
                        implicitHeight: Style.space(23)
                        bad: row.app.renameError !== ""
                        accent: Commons.Color.accent
                        Accessible.name: "Bookmark title"
                        maximumLength: 4096
                        onTextEdited: row.app.renameText = text
                        onAccepted: row.app.saveRename()
                        Component.onCompleted: { text = row.app.renameText; forceActiveFocus(); selectAll(); }
                    }
                    KeepButton { solid: true; objectName: "renameSave"; small: true; label: "Save"; onClicked: row.app.saveRename() }
                    KeepButton { objectName: "renameCancel"; small: true; bordered: true; label: "Cancel"; onClicked: row.app.cancelRename() }
                }
            }
        }
        Item {
            id: line2
            y: line1.height
            width: parent.width
            height: row.expanded ? Math.max(Style.space(23), wholeLink.implicitHeight) : Style.space(23)
            readonly property real room: width - (acts.visible ? acts.width + Style.space(5) : 0) - (chip.active ? chip.width + Style.space(5) : 0)
            Label {
                visible: row.renaming && row.app.renameError !== ""
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                text: row.app.renameError
                color: row.app.errorInk
                size: "caption"
            }
            Row {
                id: meta
                visible: !(row.renaming && row.app.renameError !== "") && !row.expanded
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(7)
                HighlightText {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.max(0, Math.min(sourceWidth, line2.room - (tag.visible ? tag.width + meta.spacing : 0)))
                    source: row.hot && !row.renaming || row.linkFound ? row.url : row.app.rowHost(row.bookmark)
                    query: row.query
                    color: row.app.dim
                    size: "caption"
                }
                Row {
                    id: tag
                    visible: !row.app.folderId && row.folderId !== 0
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(implicitWidth, line2.room / 2)
                    spacing: 2
                    Glyph {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Icons.folder
                        color: row.app.dim
                        font.pixelSize: Style.space(12)
                    }
                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.min(implicitWidth, line2.room / 2 - Style.space(15))
                        text: tag.visible ? row.app.folderName(row.folderId) : ""
                        color: row.app.dim
                        size: "caption"
                    }
                }
            }
            Loader {
                id: wholeLink
                active: row.expanded
                y: Math.max(0, Math.round((line2.height - implicitHeight) / 2))
                width: line2.room
                sourceComponent: WrappedText {
                    text: row.url
                    query: row.query
                    color: row.app.dim
                    size: "caption"
                }
            }
            Loader {
                id: chip
                active: row.noteState === "failed" && !row.expanded
                anchors.right: acts.left
                anchors.rightMargin: Style.space(5)
                anchors.verticalCenter: parent.verticalCenter
                sourceComponent: Row {
                    objectName: "notSavedChip"
                    spacing: Style.space(3)
                    Glyph {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Icons.alert
                        color: row.app.errorInk
                        font.pixelSize: Style.space(13)
                    }
                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Not saved"
                        color: row.app.errorInk
                        size: "caption"
                    }
                }
            }
            Item {
                id: acts
                visible: !row.renaming
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: rest.width
                height: rest.height
                HoverHandler { id: actsHover }
                // Stands in for the real buttons, and keeps their place while they are up.
                Row {
                    id: rest
                    opacity: live.active ? 0 : 1
                    spacing: Style.space(3)
                    RestButton {
                        icon: row.expanded ? Icons.up : row.hasNote || row.app.compact ? Icons.note : Icons.plus
                        label: row.expanded ? "Close" : row.app.compact ? "" : "Note"
                        ink: row.hasNote ? Commons.Color.accent : row.app.dim
                    }
                    RestButton { visible: !row.expanded; icon: Icons.move; label: row.app.compact ? "" : "Move"; ink: row.app.dim }
                    RestButton { visible: !row.expanded; icon: Icons.more; ink: row.app.dim }
                }
                Loader {
                    active: live.active
                    anchors.right: parent.right
                    sourceComponent: Row {
                        spacing: Style.space(3)
                        KeepButton {
                            objectName: "noteButton"
                            visible: !row.expanded
                            small: true
                            focusable: row.selected || activeFocus
                            bordered: row.hot
                            ink: row.hasNote ? Commons.Color.accent : row.hot ? Commons.Color.foreground : row.app.dim
                            icon: row.hasNote || row.app.compact ? Icons.note : Icons.plus
                            label: row.app.compact ? "" : "Note"
                            tooltipText: row.hasNote ? "Open note" : "Add a note"
                            Accessible.name: row.hasNote ? "Open note" : "Add a note"
                            onClicked: { row.select(); row.app.expand(row.rowId, true); }
                            onRightClicked: row.menu(x + acts.x, line2.y)
                        }
                        KeepButton {
                            id: moveButton
                            objectName: "moveButton"
                            visible: !row.expanded
                            small: true
                            focusable: row.selected || activeFocus
                            bordered: row.hot
                            ink: row.hot ? Commons.Color.foreground : row.app.dim
                            icon: Icons.move
                            label: row.app.compact ? "" : "Move"
                            tooltipText: "Move to a folder"
                            Accessible.name: "Move to a folder"
                            onClicked: { row.select(); row.app.pickFolderFor(row.snapshot(), { anchor: moveButton }); }
                            onRightClicked: row.menu(x + acts.x, line2.y)
                        }
                        KeepButton {
                            id: moreButton
                            objectName: "moreButton"
                            visible: !row.expanded
                            small: true
                            focusable: row.selected || activeFocus
                            bordered: row.hot
                            ink: row.hot ? Commons.Color.foreground : row.app.dim
                            icon: Icons.more
                            tooltipText: "More actions"
                            Accessible.name: "More actions"
                            onClicked: { row.select(); row.app.rowMenu(row.snapshot(), { anchor: moreButton }); }
                            onRightClicked: row.menu(x + acts.x, line2.y)
                        }
                        Loader {
                            active: row.expanded
                            visible: active
                            sourceComponent: KeepButton {
                                objectName: "closeNote"
                                small: true
                                ink: Commons.Color.accent
                                icon: Icons.up
                                label: "Close"
                                tooltipText: "Close note"
                                onClicked: row.app.expand(row.rowId, false)
                            }
                        }
                    }
                }
            }
        }
        Item {
            id: noteLine
            objectName: "noteLine"
            visible: row.showNote
            y: line1.height + line2.height + 2
            width: parent.width - Style.space(4)
            height: Style.space(15)
            HoverHandler { id: noteHover; cursorShape: Qt.IBeamCursor }
            Rectangle { width: 2; height: parent.height; color: Commons.Color.accent }
            HighlightText {
                x: Style.space(7)
                width: parent.width - x
                height: parent.height
                source: row.note
                query: row.query
                color: noteHover.hovered ? row.app.hotInk : Commons.Color.foreground
                size: "caption"
                font.underline: noteHover.hovered
            }
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                cursorShape: Qt.IBeamCursor
                onClicked: function(mouse) {
                    row.select();
                    if (mouse.button === Qt.RightButton) row.menu(column.x + mouse.x, column.y + noteLine.y + mouse.y);
                    else row.app.expand(row.rowId, true);
                }
            }
        }
        Loader {
            id: card
            active: row.expanded
            y: line1.height + line2.height + Style.space(3)
            width: parent.width - Style.space(4)
            sourceComponent: ColumnLayout {
                id: note
                readonly property bool ready: row.app.loadedNoteId === row.rowId
                spacing: Style.space(5)
                Controls.ScrollView {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.max(Style.space(103), Math.min(editor.contentHeight + editor.topPadding + editor.bottomPadding, Style.space(283)))
                    clip: true
                    Controls.TextArea {
                        id: editor
                        objectName: "noteEditor"
                        readonly property bool wanted: note.ready && row.app.editorWanted
                        text: row.app.noteText(row.rowId)
                        textFormat: TextEdit.PlainText
                        enabled: note.ready
                        placeholderText: note.ready ? "Write a note. It saves as you type." : "Loading note…"
                        placeholderTextColor: Qt.darker(Commons.Color.foreground, 1.6)
                        Accessible.name: "Note for " + row.title
                        color: Commons.Color.foreground
                        selectionColor: Style.selectionFill
                        selectedTextColor: Commons.Color.foreground
                        font.family: Style.font.family // qmllint disable missing-property
                        font.pixelSize: Style.font.body // qmllint disable missing-property
                        wrapMode: TextEdit.Wrap
                        selectByMouse: true
                        leftPadding: Style.space(8); rightPadding: Style.space(8)
                        topPadding: Style.space(7); bottomPadding: Style.space(7)
                        background: Ui.BorderSurface {
                            color: Commons.Color.background
                            borderSpec: Border.flat(row.noteState === "failed" ? row.app.errorInk : editor.activeFocus || editor.hovered ? Commons.Color.accent : row.app.line, Style.normalBorderWidth)
                        }
                        function takeFocus() {
                            if (!wanted) return;
                            forceActiveFocus(); cursorPosition = length;
                            row.app.editorWanted = false;
                        }
                        onWantedChanged: if (wanted) Qt.callLater(takeFocus)
                        onTextChanged: if (activeFocus && note.ready && text !== row.app.noteText(row.rowId)) row.app.editNote(row.rowId, text)
                        onActiveFocusChanged: if (!activeFocus) row.app.flush()
                        Keys.onTabPressed: openPage.forceActiveFocus()
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    Layout.minimumHeight: Style.space(23)
                    spacing: Style.space(6)
                    Rectangle {
                        visible: row.noteState !== "failed"
                        implicitWidth: 7; implicitHeight: 7; radius: 3.5
                        color: row.noteState === "saved" ? Commons.Color.accent : row.noteState === "saving" ? row.app.selectedLine : Commons.Color.muted
                    }
                    Glyph {
                        visible: row.noteState === "failed"
                        text: Icons.alert
                        color: row.app.errorInk
                        font.pixelSize: Style.space(14)
                    }
                    Label {
                        objectName: "saveStatus"
                        Layout.fillWidth: true
                        text: row.noteState === "failed" ? "Not saved. Your text is kept here." : row.noteState === "saving" ? "Saving…" : row.noteState === "saved" ? "Saved" : "Saves as you type"
                        color: row.noteState === "failed" ? row.app.errorInk : row.app.dim
                        size: row.noteState === "failed" ? "bodySmall" : "caption"
                    }
                    KeepButton {
                        objectName: "noteRetry"
                        visible: row.noteState === "failed"
                        small: true; bordered: true; danger: true
                        icon: Icons.retry; label: "Retry"
                        onClicked: row.app.retry()
                    }
                }
                Flow {
                    id: bar
                    Layout.fillWidth: true
                    spacing: Style.space(4)
                    KeepButton {
                        id: openPage
                        objectName: "cardOpen"
                        tight: true
                        accented: true
                        icon: Icons.open; label: "Open page"
                        onClicked: row.app.openLink(row.url)
                    }
                    KeepButton {
                        id: cardMove
                        objectName: "cardMove"
                        tight: true
                        bordered: true
                        icon: Icons.move
                        label: row.app.folderName(row.folderId)
                        labelLimit: Style.space(100)
                        trailing: Icons.down
                        tooltipText: "Move to a folder"
                        onClicked: row.app.pickFolderFor(row.snapshot(), { anchor: cardMove })
                    }
                    KeepButton {
                        id: cardCopy
                        objectName: "cardCopy"
                        tight: true
                        bordered: true
                        icon: Icons.copy; label: "Copy link"
                        onClicked: row.app.copyLink(row.url)
                    }
                    KeepButton {
                        id: cardRename
                        objectName: "cardRename"
                        tight: true
                        bordered: true
                        icon: Icons.edit; label: "Rename"
                        onClicked: row.app.startRename(row.snapshot())
                    }
                    // Delete keeps to the far end of whichever line it lands on.
                    Item {
                        width: {
                            var left = bar.width;
                            [openPage, cardMove, cardCopy, cardRename].forEach(function(button) {
                                if (button.width > left) left = bar.width;
                                left -= button.width + bar.spacing;
                            });
                            return Math.max(0, left - cardDelete.width - bar.spacing);
                        }
                        height: 1
                    }
                    KeepButton {
                        id: cardDelete
                        objectName: "cardDelete"
                        tight: true
                        danger: true
                        icon: Icons.trash; label: "Delete"
                        onClicked: row.app.askDelete(row.snapshot())
                    }
                }
            }
        }
    }
    DragHandler {
        target: null
        enabled: !row.app.narrow && !row.expanded && !row.renaming
        acceptedButtons: Qt.LeftButton
        dragThreshold: Style.space(5)
        cursorShape: Qt.ClosedHandCursor
        onActiveChanged: {
            if (active) row.app.beginDrag(row.snapshot());
            else row.app.endDrag();
        }
        onCentroidChanged: if (active) row.app.moveDrag(row.mapToItem(row.app.overlay, centroid.position.x, centroid.position.y))
    }
    Loader {
        id: live
        anchors.fill: parent
        active: row.hot || row.selected || row.expanded || row.renaming || row.lifted
        sourceComponent: Item {
            Rectangle { visible: row.expanded; width: 2; height: parent.height - 1; color: Commons.Color.accent }
            Rectangle {
                anchors.fill: parent
                visible: row.selected && row.app.keyboard && !row.app.folderZone
                color: "transparent"
                border.color: Commons.Color.accent
                border.width: 1
            }
            Glyph {
                x: Math.round((Style.space(11) - width) / 2)
                y: Math.round((parent.height - height) / 2)
                visible: row.hot && !row.app.narrow && !row.expanded
                text: Icons.grip
                color: row.app.dim
                font.pixelSize: Style.space(13)
            }
            Item {
                x: column.x
                y: column.y
                width: oneLine.width
                height: oneLine.height
                visible: oneLine.visible
                HoverHandler { id: titleHover }
                Loader {
                    active: oneLine.truncated && titleHover.hovered && !area.pressed
                    sourceComponent: Ui.PanelToolTip {
                        visible: true
                        delay: 800
                        text: oneLine.source
                        x: 0
                        y: -height - 4
                        width: Math.min(implicitWidth, Style.space(367))
                        // The kit's tooltip stays on one line, which would run past the window.
                        Component.onCompleted: { (contentItem as Text).wrapMode = Text.Wrap; (contentItem as Text).maximumLineCount = 12; (contentItem as Text).elide = Text.ElideRight; }
                    }
                }
            }
        }
    }
}
