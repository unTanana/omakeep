pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import Quickshell
import qs.Commons
import qs.Ui as Ui
import "State.js" as State

Item {
    id: root
    property var shell: null
    property var manifest: null
    property bool opened: false
    readonly property string pluginDir: manifest && manifest.__sourceDir ? manifest.__sourceDir : Qt.resolvedUrl(".").toString().replace(/^file:\/\//, "").replace(/\/$/, "")
    property var store: State.create()
    property int revision: 0
    property var folders: []
    property int folderId: 0
    property int expandedId: 0
    property int loadedNoteId: 0
    property string loadedNote: ""
    property var nextPage: null
    property int generation: 0
    property int loadedGeneration: -1
    property int pendingFocusIndex: -1
    property bool folderNavigation: false
    property bool formReturnsToFolders: false
    property var pendingRead: null
    property string notice: ""
    property bool readFailed: false
    property string formKind: ""
    property int targetId: 0
    property string formError: ""
    readonly property string viewName: folderId === 0 ? "All" : (folders.find(function(f) { return f.id === root.folderId; }) || {}).name || "All"
    readonly property var viewFolders: [{ id: 0, name: "All" }].concat(folders)
    readonly property var moveFolders: [{ id: 0, name: "No folder" }].concat(folders)
    readonly property string saveStatus: {
        var ignored = revision;
        return store.failed ? "Changes could not be saved. Your edits are kept here."
            : Object.keys(store.drafts).length || store.active || store.queue.length ? "Saving…" : "";
    }

    ListModel { id: bookmarks; dynamicRoles: true }
    function open() {
        opened = true;
        reload();
        Qt.callLater(function() { search.forceActiveFocus(); });
    }
    function focusSearch() { search.forceActiveFocus(); search.selectAll(); }
    function close() { flush(); opened = false; }
    function dismiss() { close(); if (shell) shell.hide("omakeep"); }
    function focusRow(index) {
        folderNavigation = false;
        if (loadedGeneration !== generation) { pendingFocusIndex = Math.max(0, index); return; }
        pendingFocusIndex = -1;
        if (!bookmarks.count) { list.forceActiveFocus(); return; }
        list.currentIndex = Math.max(0, Math.min(bookmarks.count - 1, index));
        list.positionViewAtIndex(list.currentIndex, ListView.Contain);
        Qt.callLater(function() { var row = list.currentItem as BookmarkRow; if (row && !root.folderNavigation && !form.visible) row.focusTitle(); });
    }
    function focusFolders() {
        folderNavigation = true; pendingFocusIndex = -1;
        if (viewPicker.visible) { viewPicker.forceActiveFocus(); return; }
        var index = viewFolders.findIndex(function(f) { return f.id === root.folderId; });
        var button = folderButtons.itemAt(Math.max(0, index));
        if (button) {
            button.forceActiveFocus();
            var flick = sidebarScroll.contentItem as Flickable;
            if (flick) flick.contentY = Math.max(0, Math.min(button.y, flick.contentHeight - flick.height));
        }
    }
    function navigateFolder(delta) {
        var index = viewFolders.findIndex(function(f) { return f.id === root.folderId; });
        chooseFolder(viewFolders[Math.max(0, Math.min(viewFolders.length - 1, index + delta))].id);
        focusFolders();
    }
    function folderKey(event) {
        if (folderId && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) {
            if (event.key === Qt.Key_R) { beginForm("rename", folderId, viewName); event.accepted = true; }
            else if (event.key === Qt.Key_D) { beginForm("deleteFolder", folderId); event.accepted = true; }
        }
    }
    function chooseFolder(value) {
        if (folderId === value) return;
        pendingFocusIndex = -1;
        flush(); folderId = value; expandedId = 0; reload();
    }
    function reload() {
        generation++;
        pendingRead = { op: "list", query: search.text, folderId: folderId || null, generation: generation };
        pumpRead();
    }
    function pumpRead() {
        if (reader.busy) return;
        if (pendingRead) {
            var job = pendingRead; pendingRead = null;
            reader.start(job);
        } else if (expandedId && loadedNoteId !== expandedId) {
            reader.start({ op: "note", id: expandedId });
        }
    }
    function expand(id) {
        if (expandedId !== id && !store.drafts[id] && Object.keys(store.drafts).length >= 100) {
            notice = "Save or retry the pending notes before editing another bookmark."; return;
        }
        flush();
        if (expandedId === id) { expandedId = 0; return; }
        expandedId = id; loadedNoteId = 0; loadedNote = "";
        pumpRead();
    }
    function noteText(id) {
        var ignored = revision;
        return store.drafts[id] ? store.drafts[id].notes : loadedNoteId === id ? loadedNote : "";
    }
    function editNote(id, value) {
        if (!State.edit(store, id, value)) {
            notice = "Note limit reached. Copy your text before leaving this editor.";
            return;
        }
        revision++; saveTimer.restart();
    }
    function flush() { saveTimer.stop(); State.flush(store); revision++; pumpWrite(); }
    function mutate(job) {
        if (store.queue.length >= 200) { notice = "Too many pending changes. Retry the current save first."; return; }
        State.enqueue(store, job); revision++; pumpWrite();
    }
    function pumpWrite() {
        if (writer.busy) return;
        var job = State.next(store); revision++;
        if (job) writer.start(job);
    }
    function retry() {
        notice = ""; State.retry(store); revision++; pumpWrite();
        if (readFailed) { readFailed = false; reload(); }
    }
    function beginForm(kind, id, initial) {
        if (form.visible || (store.active && store.active.form)) return;
        formReturnsToFolders = folderNavigation || kind === "rename" || kind === "deleteFolder";
        flush(); formKind = kind; targetId = id || 0;
        formError = ""; field.text = initial || ""; titleField.text = "";
        form.open();
        Qt.callLater(function() { if (field.visible) { field.forceActiveFocus(); field.selectAll(); } else confirm.forceActiveFocus(); });
    }
    function submit() {
        State.cancelFailedForm(store); revision++;
        var job;
        if (formKind === "add") job = { op: "capture", url: field.text, title: titleField.text };
        else if (formKind === "folder") job = { op: "createFolder", name: field.text };
        else if (formKind === "rename") job = { op: "renameFolder", id: targetId, name: field.text };
        else if (formKind === "renameBookmark") job = { op: "renameBookmark", id: targetId, title: field.text };
        else if (formKind === "deleteFolder") job = { op: "deleteFolder", id: targetId };
        else if (formKind === "deleteBookmark") job = { op: "deleteBookmark", id: targetId };
        if (job) { job.form = true; mutate(job); }
    }
    function openLink(url) {
        if (State.safeUrl(url)) Qt.openUrlExternally(url);
        else notice = "This bookmark has an invalid URL.";
    }
    function copyLink(url) {
        if (!State.safeUrl(url)) { notice = "This bookmark has an invalid URL."; return; }
        Quickshell.clipboardText = url;
        notice = "Link copied";
    }
    function escapePressed() {
        if (expandedId) { flush(); expandedId = 0; focusRow(list.currentIndex); }
        else dismiss();
    }

    Timer { id: saveTimer; interval: 350; onTriggered: root.flush() }
    Timer { id: searchTimer; interval: 180; onTriggered: root.reload() }
    Helper {
        id: reader
        pluginDir: root.pluginDir
        onCompleted: function(job, reply) {
            if (job.op === "list" && job.generation !== root.generation) {
                Qt.callLater(root.pumpRead); return;
            }
            if (!reply.ok) { root.notice = reply.error; root.readFailed = true; }
            else if (job.op === "list") {
                if (!State.validList(reply.result)) { root.notice = "Invalid library response."; root.readFailed = true; }
                else {
                    if (JSON.stringify(root.folders) !== JSON.stringify(reply.result.folders)) {
                        root.folders = reply.result.folders;
                        Qt.callLater(function() { if (root.folderNavigation && !form.visible) root.focusFolders(); });
                    }
                    if (!job.before) bookmarks.clear();
                    reply.result.items.forEach(function(item) { bookmarks.append(item); });
                    root.nextPage = reply.result.next;
                    if (list.currentIndex < 0 && bookmarks.count) list.currentIndex = 0;
                    root.readFailed = false;
                    root.loadedGeneration = job.generation;
                    if (root.pendingFocusIndex >= 0) root.focusRow(root.pendingFocusIndex);
                }
            } else if (job.op === "note" && job.id === root.expandedId) {
                if (reply.result && typeof reply.result.notes === "string" && reply.result.notes.length <= 65536) {
                    root.loadedNoteId = job.id; root.loadedNote = reply.result.notes;
                } else { root.notice = "Invalid note response."; root.readFailed = true; }
            }
            // A failed note read waits for Retry, rather than automatically looping.
            if (!root.readFailed) Qt.callLater(root.pumpRead);
        }
    }
    Helper {
        id: writer
        pluginDir: root.pluginDir
        onCompleted: function(job, reply) {
            State.finish(root.store, reply.ok); root.revision++;
            if (!reply.ok) {
                root.notice = reply.error;
                if (job.form) root.formError = reply.error;
                if (!root.store.failed) Qt.callLater(root.pumpWrite);
            } else {
                root.notice = "";
                if (job.op === "saveNote") {
                    if (root.loadedNoteId === job.id) root.loadedNote = job.notes;
                    for (var i = 0; i < bookmarks.count; i++) if (bookmarks.get(i).id === job.id) bookmarks.setProperty(i, "hasNote", job.notes.length > 0);
                } else if (job.op === "renameBookmark") {
                    for (var k = 0; k < bookmarks.count; k++) if (bookmarks.get(k).id === job.id) bookmarks.setProperty(k, "title", job.title.trim());
                    if (job.form) form.close();
                    if (search.text) root.reload();
                } else if (job.op === "move") {
                    for (var j = 0; j < bookmarks.count; j++) if (bookmarks.get(j).id === job.id) {
                        if (root.folderId && root.folderId !== job.folderId) {
                            root.expandedId = 0; bookmarks.remove(j); root.focusRow(j);
                        } else bookmarks.setProperty(j, "folderId", job.folderId);
                        break;
                    }
                } else {
                    if (job.form) form.close();
                    if (job.op === "deleteFolder" && root.folderId === job.id) root.folderId = 0;
                    if (job.op === "deleteBookmark" && root.expandedId === job.id) root.expandedId = 0;
                    root.reload();
                }
                Qt.callLater(root.pumpWrite);
            }
        }
    }

    FloatingWindow {
        id: window
        objectName: "omakeepWindow"
        visible: root.opened
        title: "Omakeep"
        color: Color.background
        implicitWidth: Style.space(900)
        implicitHeight: Style.space(650)
        minimumSize: Qt.size(Style.space(440), Style.space(400))
        onVisibleChanged: if (!visible && root.opened) root.dismiss()

        FocusScope {
            anchors.fill: parent
            focus: true
            Keys.onEscapePressed: root.escapePressed()
            Keys.onPressed: function(event) {
                // Unmodified typing stays inside the field/editor that owns focus.
                if (event.key === Qt.Key_F && event.modifiers & Qt.ControlModifier) { search.forceActiveFocus(); search.selectAll(); event.accepted = true; }
                else if (event.key === Qt.Key_N && event.modifiers & Qt.ControlModifier) { root.beginForm(event.modifiers & Qt.ShiftModifier ? "folder" : "add"); event.accepted = true; }
            }
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Style.space(18)
                spacing: Style.space(12)
                RowLayout {
                    Layout.fillWidth: true
                    Ui.TextField {
                        id: search
                        objectName: "bookmarkSearch"
                        Layout.fillWidth: true
                        placeholderText: "Search " + root.viewName.toLowerCase()
                        maximumLength: 4096
                        Accessible.name: "Search bookmarks"
                        onTextEdited: { root.generation++; searchTimer.restart(); }
                        onActiveFocusChanged: if (activeFocus) { root.folderNavigation = false; root.pendingFocusIndex = -1; }
                        Keys.onDownPressed: root.focusRow(0)
                    }
                    Ui.Button { text: "Add bookmark"; focusable: true; Accessible.name: text; onClicked: root.beginForm("add") }
                }
                RowLayout {
                    visible: window.width < Style.space(680)
                    Layout.fillWidth: true
                    FolderPicker {
                        id: viewPicker
                        objectName: "folderViewPicker"
                        Layout.fillWidth: true
                        entries: root.viewFolders
                        selectedId: root.folderId
                        Accessible.name: "Bookmark view"
                        onChosen: function(id) { root.chooseFolder(id); }
                        onActiveFocusChanged: if (activeFocus) { root.folderNavigation = true; root.pendingFocusIndex = -1; }
                        Keys.onRightPressed: { popup.close(); root.focusRow(0); }
                        Keys.onPressed: function(event) { if (!popup.visible) root.folderKey(event); }
                    }
                    Ui.Button { text: "New folder"; focusable: true; onClicked: root.beginForm("folder") }
                }
                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: Style.space(18)
                    ColumnLayout {
                        visible: window.width >= Style.space(680)
                        Layout.preferredWidth: Style.space(170)
                        Layout.minimumWidth: Style.space(170)
                        Layout.maximumWidth: Style.space(170)
                        Layout.fillHeight: true
                        Controls.ScrollView {
                            id: sidebarScroll
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            contentWidth: availableWidth
                            Column {
                                width: sidebarScroll.availableWidth
                                Repeater {
                                    id: folderButtons
                                    objectName: "folderButtons"
                                    model: root.viewFolders
                                    Ui.Button {
                                        id: folderButton
                                        required property var modelData
                                        objectName: "folder-" + modelData.id
                                        width: parent.width
                                        implicitHeight: Style.space(34)
                                        Accessible.name: modelData.name
                                        selected: root.folderId === modelData.id
                                        focusable: true; leftAlign: true
                                        onClicked: root.chooseFolder(modelData.id)
                                        onActiveFocusChanged: if (activeFocus) { root.folderNavigation = true; root.pendingFocusIndex = -1; root.chooseFolder(modelData.id); }
                                        Keys.onDownPressed: root.navigateFolder(1)
                                        Keys.onUpPressed: root.navigateFolder(-1)
                                        Keys.onRightPressed: root.focusRow(0)
                                        Keys.onPressed: function(event) { root.folderKey(event); }
                                        Text {
                                            anchors.fill: parent; anchors.margins: Style.space(10)
                                            text: folderButton.modelData.name; textFormat: Text.PlainText
                                            elide: Text.ElideRight; verticalAlignment: Text.AlignVCenter
                                            color: Color.foreground; font.family: Style.fontFamily
                                            font.pixelSize: Style.fontToken("body", Style.fontPx(1))
                                        }
                                    }
                                }
                            }
                        }
                        Ui.Button { text: "+ New folder"; focusable: true; onClicked: root.beginForm("folder") }
                    }
                    Rectangle { visible: window.width >= Style.space(680); Layout.fillHeight: true; implicitWidth: 1; color: Style.normalBorderColor }
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        Layout.fillHeight: true
                        RowLayout {
                            Layout.fillWidth: true
                            Text { text: root.viewName; textFormat: Text.PlainText; color: Color.foreground; font.family: Style.fontFamily; font.pixelSize: Style.fontToken("body", Style.fontPx(1)); Layout.fillWidth: true; elide: Text.ElideRight }
                            Ui.Button {
                                visible: root.folderId !== 0
                                text: "Folder options"; focusable: true
                                onClicked: folderMenu.open()
                                Controls.Menu {
                                    id: folderMenu
                                    Controls.MenuItem { text: "Rename folder"; onTriggered: root.beginForm("rename", root.folderId, root.viewName) }
                                    Controls.MenuItem { text: "Delete folder…"; onTriggered: root.beginForm("deleteFolder", root.folderId) }
                                }
                            }
                        }
                        ListView {
                            id: list
                            objectName: "bookmarkList"
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            model: bookmarks
                            spacing: Style.space(4)
                            boundsBehavior: Flickable.StopAtBounds
                            Keys.onLeftPressed: root.focusFolders()
                            Controls.ScrollBar.vertical: Controls.ScrollBar {}
                            delegate: BookmarkRow {
                                required property int index
                                required property var model
                                width: list.width
                                app: root
                                bookmark: model
                                selected: list.currentIndex === index
                                onSelect: { list.currentIndex = index; root.folderNavigation = false; }
                                onNavigate: function(delta) { root.focusRow(index + delta); }
                            }
                            footer: Ui.Button {
                                visible: root.nextPage !== null
                                text: "Load more"; focusable: true
                                enabled: !reader.busy && !root.pendingRead
                                onClicked: {
                                    root.pendingRead = { op: "list", query: search.text, folderId: root.folderId || null, before: root.nextPage, generation: root.generation };
                                    root.pumpRead();
                                }
                            }
                            Text {
                                anchors.centerIn: parent
                                width: parent.width - Style.space(30)
                                visible: bookmarks.count === 0
                                text: reader.busy ? "Loading…" : root.readFailed ? "Library unavailable. Retry below." : search.text ? "No bookmarks match this search." : "No bookmarks yet.\nSave a page from Chrome or add a bookmark."
                                textFormat: Text.PlainText
                                color: Color.foreground; opacity: 0.7
                                font.family: Style.fontFamily; font.pixelSize: Style.fontToken("body", Style.fontPx(1))
                                horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
                            }
                        }
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    visible: root.notice !== "" || root.saveStatus !== ""
                    Text {
                        Layout.fillWidth: true
                        text: root.notice || root.saveStatus
                        textFormat: Text.PlainText
                        color: root.store.failed || root.readFailed ? Color.urgent : Color.foreground
                        font.family: Style.fontFamily; font.pixelSize: Style.fontToken("body-small", Style.fontPx(0.917))
                        wrapMode: Text.Wrap
                    }
                    Ui.Button { text: "Retry"; focusable: true; visible: root.store.failed !== null || root.readFailed; onClicked: root.retry() }
                }
                RowLayout {
                    Layout.fillWidth: true
                    Text { text: "← Folders · → Contents / note · E Edit note · F Folder · R Rename · D Delete"; wrapMode: Text.Wrap; textFormat: Text.PlainText; color: Color.foreground; opacity: 0.6; font.family: Style.fontFamily; font.pixelSize: Style.fontToken("body-small", Style.fontPx(0.917)); Layout.fillWidth: true }
                    Ui.Button { text: "Shortcuts"; focusable: true; onClicked: root.beginForm("help") }
                }
            }

            Controls.Popup {
                id: form
                objectName: "bookmarkForm"
                anchors.centerIn: parent
                width: Math.min(parent.width - 32, Style.space(480))
                padding: Style.space(22)
                modal: true; focus: true
                closePolicy: Controls.Popup.CloseOnEscape
                background: Rectangle { color: Color.background; border.color: Color.accent; border.width: 1 }
                onClosed: {
                    State.cancelFailedForm(root.store); root.revision++; root.pumpWrite();
                    Qt.callLater(function() { if (root.formReturnsToFolders) root.focusFolders(); else root.focusRow(list.currentIndex); });
                }
                ColumnLayout {
                    width: parent.width
                    spacing: Style.space(14)
                    Text {
                        text: ({ add: "Add bookmark", folder: "New folder", rename: "Rename folder", renameBookmark: "Rename bookmark", deleteFolder: "Delete folder?", deleteBookmark: "Delete bookmark?", help: "Keyboard shortcuts" })[root.formKind] || "Omakeep"
                        textFormat: Text.PlainText; color: Color.foreground; font.family: Style.fontFamily; font.pixelSize: Style.fontToken("body", Style.fontPx(1)); font.bold: true
                    }
                    Text {
                        visible: ["help", "deleteFolder", "deleteBookmark"].includes(root.formKind)
                        Layout.fillWidth: true
                        text: root.formKind === "help" ? "Ctrl+F or / — Search\nDown — Enter the list\n↑ / ↓ — Move between bookmarks or folders\nEnter — Open page\n← — Collapse note, then go to folders\n→ — Enter folder contents or expand note\nF — Choose folder (↑ / ↓, Enter; Escape cancels)\nE — Expand the note and edit\nR — Rename bookmark or folder\nD — Delete bookmark and note, or folder (asks first)\nTab — Reach the note editor and controls\nEscape — Return to item, then close\nCtrl+N — Add bookmark\nCtrl+Shift+N — New folder\n? — Shortcuts\n\nChrome: Alt+Shift+K saves the current page."
                            : root.formKind === "deleteFolder" ? "Bookmarks and notes will stay in All." : "This removes the bookmark and its note."
                        textFormat: Text.PlainText; color: Color.foreground; font.family: Style.fontFamily; font.pixelSize: Style.fontToken("body", Style.fontPx(1)); wrapMode: Text.Wrap
                    }
                    Ui.TextField {
                        id: field
                        objectName: "formField"
                        visible: ["add", "folder", "rename", "renameBookmark"].includes(root.formKind)
                        Layout.fillWidth: true
                        placeholderText: root.formKind === "add" ? "https://…" : root.formKind === "renameBookmark" ? "Bookmark title" : "Folder name"
                        Accessible.name: placeholderText
                        maximumLength: root.formKind === "add" ? 16384 : root.formKind === "renameBookmark" ? 4096 : 256
                        onAccepted: root.submit()
                    }
                    Ui.TextField {
                        id: titleField
                        visible: root.formKind === "add"
                        Layout.fillWidth: true
                        placeholderText: "Title (optional)"
                        Accessible.name: "Bookmark title, optional"
                        maximumLength: 4096
                        onAccepted: root.submit()
                    }
                    Text { visible: root.formError !== ""; text: root.formError; Layout.fillWidth: true; textFormat: Text.PlainText; color: Color.urgent; font.family: Style.fontFamily; font.pixelSize: Style.fontToken("body-small", Style.fontPx(0.917)); wrapMode: Text.Wrap }
                    RowLayout {
                        Layout.alignment: Qt.AlignRight
                        Ui.Button { text: root.formKind === "help" ? "Close" : "Cancel"; focusable: true; onClicked: form.close() }
                        Ui.Button {
                            id: confirm
                            visible: root.formKind !== "help"
                            text: root.formKind.startsWith("delete") ? "Delete" : root.formKind.startsWith("rename") ? "Rename" : "Add"
                            focusable: true; bordered: true
                            enabled: !writer.busy && (root.store.failed === null || root.store.failed.form === true)
                            onClicked: root.submit()
                        }
                    }
                }
            }
        }
    }
}
