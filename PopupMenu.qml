pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls as Controls
import qs.Commons
import qs.Commons as Commons
import qs.Ui as Ui

// One surface for right-click menus and folder pickers, drawn inside the window.
// Entries are { icon, label, key, danger, on, none, run } or "-" for a line.
Item {
    id: root
    property var items: []
    property int current: -1
    property bool filtering: false
    property var build: null
    property var held: null
    readonly property var menuColors: Commons.Color.menu
    readonly property var alert: Commons.Color.polkit
    readonly property var fonts: Style.font
    readonly property color line: Border.color(Border.controlSpec("normal", Commons.Color.foreground, Commons.Color.accent))
    readonly property color selectedLine: Border.color(Border.controlSpec("selected", Commons.Color.foreground, Commons.Color.accent))
    readonly property int rowHeight: Style.space(28)
    readonly property int lineHeight: Style.space(7)
    readonly property int margin: Style.space(3)
    readonly property int edge: Style.space(5)
    signal closed()
    anchors.fill: parent
    visible: false

    function listHeight(entries) {
        return entries.reduce(function(sum, entry) { return sum + (entry === "-" ? root.lineHeight : root.rowHeight); }, 0);
    }
    function listWidth(entries) {
        var widest = 0;
        entries.forEach(function(entry) {
            if (entry === "-") return;
            metrics.text = entry.label;
            widest = Math.max(widest, metrics.advanceWidth + (entry.key ? Style.space(14) + entry.key.length * root.fonts.caption * 0.62 : 0));
        });
        return Math.round(widest + Style.space(44));
    }
    function place(at) {
        var w = Math.max(Style.space(183), Math.min(Style.space(283), listWidth(items)));
        var top = filtering ? filter.implicitHeight + Style.space(7) : 0;
        var h = Math.min(Style.space(350), Math.min(height - Style.space(13), listHeight(items) + top + margin * 2 + edge * 2));
        var x = at.x, y = at.y;
        if (at.anchor) {
            let box = at.anchor.mapToItem(root, 0, 0);
            x = at.alignLeft ? box.x : box.x + at.anchor.width - w;
            y = box.y + at.anchor.height + 3;
            if (y + h > height - 6) y = box.y - h - 3;
        } else if (y + h > height - 6) y -= h;
        surface.width = w; surface.height = h;
        surface.x = Math.max(6, Math.min(x, width - w - 8));
        surface.y = Math.max(6, Math.min(y, height - h - 8));
    }
    function show(entries, at) {
        close(true);
        items = entries; current = -1; filtering = false; build = null;
        open(at);
    }
    // A picker rebuilds its entries as the filter changes.
    function showPicker(rebuild, withFilter, at) {
        close(true);
        filter.text = "";
        build = rebuild; items = rebuild(""); current = -1; filtering = withFilter;
        open(at);
    }
    function open(at) {
        place(at);
        if (at.anchor && at.anchor.hasCursor !== undefined) { held = at.anchor; held.hasCursor = true; }
        visible = true;
        if (filtering) filter.forceActiveFocus(); else keys.forceActiveFocus();
    }
    function close(quiet) {
        if (held) { held.hasCursor = false; held = null; }
        if (!visible) return;
        visible = false;
        if (!quiet) closed();
    }
    function step(delta) {
        // Nothing marked yet: start from the ticked entry, so Down means the next one.
        var count = items.length, index = current >= 0 ? current : items.findIndex(function(entry) { return entry.on; });
        for (let tries = 0; tries < count; tries++) {
            index = (index + delta + count) % count;
            if (items[index] !== "-" && !items[index].none) { current = index; view.positionViewAtIndex(index, ListView.Contain); return; }
        }
    }
    function run(index) {
        var entry = items[index];
        if (!entry || entry === "-" || entry.none) return;
        close(false);
        if (entry.run) entry.run();
    }
    function press(event) {
        if (event.key === Qt.Key_Escape) { close(false); event.accepted = true; }
        else if (event.key === Qt.Key_Down || event.key === Qt.Key_Up) { step(event.key === Qt.Key_Down ? 1 : -1); event.accepted = true; }
        else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && current >= 0) { run(current); event.accepted = true; }
        else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) { close(false); event.accepted = true; }
    }

    TextMetrics { id: metrics; font.family: root.fonts.family; font.pixelSize: root.fonts.bodySmall }
    // A left click outside only closes. A right click falls through so the next menu opens where it landed.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onPressed: function(mouse) {
            mouse.accepted = mouse.button === Qt.LeftButton;
            root.close(false);
        }
    }
    Ui.BorderSurface {
        id: surface
        objectName: "popupSurface"
        color: root.menuColors.background
        borderSpec: Border.flat(Commons.Color.accent, 2)
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; hoverEnabled: true }
        FocusScope {
            id: keys
            anchors.fill: parent
            anchors.margins: root.edge
            Keys.onPressed: function(event) { root.press(event); }
            Field {
                id: filter
                objectName: "popupFilter"
                visible: root.filtering
                width: parent.width
                height: visible ? implicitHeight : 0
                font.pixelSize: root.fonts.bodySmall
                placeholderText: "Find a folder…"
                Accessible.name: "Find a folder"
                onTextEdited: { root.items = root.build(text); root.current = -1; }
                Keys.onPressed: function(event) { root.press(event); }
            }
            ListView {
                id: view
                objectName: "popupList"
                y: root.filtering ? filter.height + Style.space(5) : 0
                width: parent.width
                height: parent.height - y
                clip: true
                model: root.items
                boundsBehavior: Flickable.StopAtBounds
                Controls.ScrollBar.vertical: Controls.ScrollBar { policy: view.contentHeight > view.height ? Controls.ScrollBar.AlwaysOn : Controls.ScrollBar.AlwaysOff }
                delegate: Item {
                    id: entry
                    required property var modelData
                    required property int index
                    readonly property bool line: modelData === "-"
                    readonly property bool lit: root.current === index && !line && !modelData.none
                    readonly property color tone: line ? "transparent" : modelData.danger ? root.alert.textError : lit || modelData.on ? Commons.Color.accent : Commons.Color.foreground
                    width: view.width
                    height: line ? root.lineHeight : root.rowHeight
                    objectName: line ? "" : "menu-" + modelData.label
                    Rectangle {
                        visible: entry.line
                        anchors.verticalCenter: parent.verticalCenter
                        x: 2; width: parent.width - 4; height: 1
                        color: root.line
                    }
                    Rectangle {
                        visible: !entry.line
                        anchors.fill: parent
                        color: !entry.lit ? "transparent" : entry.modelData.danger ? Util.alpha(Commons.Color.urgent, 0.16) : root.menuColors.selectedBackground
                        Rectangle {
                            width: 2; height: parent.height
                            color: !entry.lit ? "transparent" : entry.modelData.danger ? root.alert.textError : root.selectedLine
                        }
                        Glyph {
                            x: Style.space(8)
                            anchors.verticalCenter: parent.verticalCenter
                            text: entry.modelData.icon || ""
                            font.pixelSize: Style.space(14)
                            color: entry.modelData.danger || entry.lit || entry.modelData.on ? entry.tone : Util.alpha(Commons.Color.foreground, 0.72)
                        }
                        Label {
                            x: Style.space(29)
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - x - (shortcut.visible ? shortcut.width + Style.space(13) : Style.space(5))
                            text: entry.modelData.label || ""
                            color: entry.modelData.none ? Util.alpha(Commons.Color.foreground, 0.72) : entry.tone
                            size: "bodySmall"
                            font.bold: !!entry.modelData.on
                        }
                        Rectangle {
                            id: shortcut
                            visible: !!entry.modelData.key
                            anchors.right: parent.right
                            anchors.rightMargin: Style.space(6)
                            anchors.verticalCenter: parent.verticalCenter
                            width: key.implicitWidth + Style.space(6)
                            height: key.implicitHeight + 2
                            color: "transparent"
                            border.color: root.line
                            border.width: 1
                            Label {
                                id: key
                                anchors.centerIn: parent
                                text: entry.modelData.key || ""
                                size: "caption"
                                color: Util.alpha(Commons.Color.foreground, 0.72)
                            }
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        enabled: !entry.line && !entry.modelData.none
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: root.current = entry.index
                        onExited: if (root.current === entry.index) root.current = -1
                        onClicked: root.run(entry.index)
                    }
                }
            }
        }
    }
}
