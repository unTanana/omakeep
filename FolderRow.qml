pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui as Ui
import "Icons.js" as Icons
import "State.js" as State

// One folder in the sidebar. It is also a drop target while a bookmark is dragged.
Ui.Button {
    id: row
    required property var app
    required property var folder
    property bool over: false
    readonly property bool all: folder.id === 0
    readonly property bool dragging: app.dragBookmark !== null
    readonly property bool same: dragging && (app.dragBookmark.folderId || 0) === folder.id
    readonly property bool target: app.dropId === folder.id
    readonly property bool outlined: app.keyboard && app.folderZone && selected
    objectName: "folder-" + folder.id
    selected: app.folderId === folder.id
    hasCursor: target || outlined
    leftAlign: true
    implicitHeight: Style.space(32)
    opacity: same ? 0.45 : 1
    borderSpec: dragging && !target ? Border.flat(app.line, 1) : outlined ? Border.flat(Commons.Color.accent, 1) : _borderSpec
    Accessible.name: folder.name
    onHovered: function(isHovered) { row.over = isHovered; }
    onClicked: { row.app.focusFolders(); row.app.chooseFolder(row.folder.id); }
    onRightClicked: if (!row.all) row.app.folderMenu(snapshot(), { x: row.mapToItem(row.app.overlay, row.pressX, 0).x, y: row.mapToItem(row.app.overlay, 0, row.pressY).y })
    // A menu outlives this row's model entry, so it gets a copy.
    function snapshot() { return { id: folder.id, name: folder.name, count: folder.count }; }
    property real pressX: 0
    property real pressY: 0
    readonly property color tone: target || selected ? Commons.Color.accent : over ? app.hotInk : Commons.Color.foreground
    HoverHandler { id: pointer; onPointChanged: { row.pressX = point.position.x; row.pressY = point.position.y; } }
    Glyph {
        id: glyph
        x: Style.space(6)
        anchors.verticalCenter: parent.verticalCenter
        text: row.all ? Icons.all : row.selected ? Icons.folderOpen : Icons.folder
        color: row.target || row.selected ? Commons.Color.accent : row.app.dim
    }
    Label {
        x: glyph.x + glyph.width + Style.space(6)
        anchors.verticalCenter: parent.verticalCenter
        width: row.width - x - Math.max(count.implicitWidth, Style.space(15)) - Style.space(11)
        text: row.folder.name
        color: row.tone
        size: "body"
        font.bold: row.selected
    }
    Label {
        id: count
        visible: !more.active
        anchors.right: parent.right
        anchors.rightMargin: Style.space(6)
        anchors.verticalCenter: parent.verticalCenter
        text: State.comma(row.folder.count)
        color: row.app.dim
        size: "caption"
    }
    // Only the row under the pointer needs a real button.
    Loader {
        id: more
        active: row.over && !row.all && !row.dragging
        anchors.right: parent.right
        anchors.rightMargin: Style.space(3)
        anchors.verticalCenter: parent.verticalCenter
        sourceComponent: KeepButton {
            id: moreButton
            objectName: "folderMore-" + row.folder.id
            small: true
            focusable: false
            icon: Icons.more
            tooltipText: "Rename or delete"
            onClicked: row.app.folderMenu(row.snapshot(), { anchor: moreButton })
        }
    }
    DropArea {
        anchors.fill: parent
        enabled: !row.same
        onEntered: row.app.dropId = row.folder.id
        onExited: if (row.app.dropId === row.folder.id) row.app.dropId = -1
    }
}
