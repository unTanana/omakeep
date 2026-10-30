pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import QtQuick.Window
import Quickshell
import qs.Commons
import qs.Commons as Commons
import qs.Ui as Ui
import "Icons.js" as Icons
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
    property int total: 0
    property int libraryCount: 0
    property int expandedId: 0
    property int loadedNoteId: 0
    property string loadedNote: ""
    property int savedNoteId: 0
    property bool editorWanted: false
    property var nextPage: null
    property int generation: 0
    property int loadedGeneration: -1
    property int pendingFocusIndex: -1
    property var pendingRead: null
    property bool countsPending: false
    property string clipboardPending: ""
    property string appliedQuery: ""
    property bool loaded: false
    property bool libraryError: false
    property bool noteFailed: false
    property bool pageFailed: false
    property int revealId: 0
    property bool folderZone: false
    property bool keyboard: false
    property int flashId: 0
    property real flashLevel: 0
    property int renamingId: 0
    property string renameText: ""
    property string renameError: ""
    property var folderEdit: null
    property string folderText: ""
    property string folderError: ""
    property bool addOpen: false
    property string addUrl: ""
    property string addTitle: ""
    property int addFolderId: 0
    property string addError: ""
    property int addDuplicateId: 0
    property var dragBookmark: null
    property int dropId: -1
    property var restoreRow: null
    property Item focusBefore: null
    readonly property int unfiled: Math.max(0, folders.reduce(function(left, f) { return left - f.count; }, libraryCount))
    readonly property string sortLabel: sorter.busy ? "Sorting…" : "Sort " + unfiled + " with AI"
    readonly property var alert: Commons.Color.polkit
    readonly property var barColors: Commons.Color.bar
    readonly property var menuColors: Commons.Color.menu
    readonly property color errorInk: alert.textError
    readonly property color line: Border.color(Border.controlSpec("normal", Commons.Color.foreground, Commons.Color.accent))
    readonly property color selectedLine: Border.color(Border.controlSpec("selected", Commons.Color.foreground, Commons.Color.accent))
    readonly property color softLine: Util.alpha(Commons.Color.muted, 0.45)
    readonly property color dim: Util.alpha(Commons.Color.foreground, 0.72)
    readonly property color hotInk: Style.hoverStateColor(Commons.Color.foreground, Commons.Color.accent, Commons.Color.urgent)
    readonly property int sideWidth: Style.space(178)
    readonly property bool narrow: window.width < Style.space(633)
    readonly property bool compact: (narrow ? window.width : window.width - sideWidth) < Style.space(467)
    readonly property bool modal: (dialogHost.item as DialogLayer)?.visible ?? false
    readonly property Item overlay: content
    readonly property string viewName: folderId ? folderName(folderId) : "All bookmarks"
    readonly property string failure: { var ignored = revision; return State.failureText(store, expandedId) || (noteFailed ? "Couldn't load this note." : ""); }

    ListModel { id: bookmarks }
    ListModel { id: folderRows }
    function open() {
        reload();
        opened = true;
        Qt.callLater(function() { search.forceActiveFocus(); });
    }
    // Built on first use, so a panel that only sits in the shell never pays for them.
    function popup() { popupHost.active = true; return popupHost.item as PopupMenu; }
    function dialog() { dialogHost.active = true; return dialogHost.item as DialogLayer; }
    function focusSearch() { editorWanted = false; search.forceActiveFocus(); search.selectAll(); }
    function close() {
        flush();
        if (popupHost.item) popup().close(true);
        if (dialogHost.item) dialog().close();
        opened = false;
    }
    function dismiss() { close(); if (shell) shell.hide("omakeep"); }
    function folderName(id) {
        var found = folders.find(function(f) { return f.id === id; });
        return found ? found.name : "No folder";
    }
    function rowTitle(row) { return row.title || row.url || "Untitled"; }
    function rowHost(row) { return State.hostOf(row.url) || "No usable link"; }
    function initial(row) { return (State.hostOf(row.url) || row.title || "?").charAt(0).toUpperCase(); }
    function rowNote(row) { return store.drafts[row.id] ? State.preview(store.drafts[row.id].notes, appliedQuery) : row.preview || ""; }
    // The list is always newest id first.
    function rowIndex(id) {
        var low = 0, high = bookmarks.count - 1;
        while (low <= high) {
            const middle = (low + high) >> 1, found = bookmarks.get(middle).id;
            if (found === id) return middle;
            if (found > id) low = middle + 1; else high = middle - 1;
        }
        return -1;
    }
    function rowSnapshot(index) {
        var b = bookmarks.get(index);
        return { id: b.id, url: b.url, title: b.title, folderId: b.folderId, favicon: b.favicon, hasNote: b.hasNote, preview: b.preview, note: rowNote(b) };
    }

    function focusRow(index) {
        folderZone = false;
        if (loadedGeneration !== generation) { pendingFocusIndex = Math.max(0, index); return; }
        pendingFocusIndex = -1;
        list.forceActiveFocus();
        if (!bookmarks.count) return;
        list.currentIndex = Math.max(0, Math.min(bookmarks.count - 1, index));
        list.positionViewAtIndex(list.currentIndex, ListView.Contain);
    }
    function focusFolders() {
        folderZone = true; pendingFocusIndex = -1;
        if (narrow) viewButton.forceActiveFocus(); else sideKeys.forceActiveFocus();
    }
    function returnFocus() {
        var item = focusBefore;
        focusBefore = null;
        if (item && item.visible && item.enabled) item.forceActiveFocus();
        else if (folderZone) focusFolders();
        else list.forceActiveFocus();
    }
    function navigateFolder(delta) {
        var ids = [0].concat(folders.map(function(f) { return f.id; }));
        var index = Math.max(0, Math.min(ids.length - 1, ids.indexOf(folderId) + delta));
        chooseFolder(ids[index]);
        if (index) sideScroll.positionViewAtIndex(index - 1, ListView.Contain); else sideScroll.positionViewAtBeginning();
    }
    function chooseFolder(value) {
        if (folderId === value) return;
        pendingFocusIndex = -1;
        flush(); stopRename();
        folderId = value; expandedId = 0;
        if (addOpen) addFolderId = value;
        reload();
    }
    function clearSearch() {
        search.text = "";
        reload();
    }

    function reload() {
        generation++;
        pageFailed = false;
        pendingRead = { op: "list", query: search.text.trim(), folderId: folderId || null, generation: generation };
        pumpRead();
    }
    function pumpRead() {
        if (reader.busy) return;
        if (pendingRead) {
            reader.start(pendingRead);
            pendingRead = null;
        } else if (countsPending) {
            countsPending = false;
            reader.start({ op: "list", query: appliedQuery, folderId: folderId || null, counts: true });
        } else if (clipboardPending) {
            reader.start({ op: "list", query: clipboardPending, folderId: null, clipboard: true });
            clipboardPending = "";
        } else if (expandedId && loadedNoteId !== expandedId && !noteFailed) {
            reader.start({ op: "note", id: expandedId });
        }
    }
    // Folder counts and the header total, without touching the rows on screen.
    function refreshCounts() { countsPending = true; pumpRead(); }
    function loadMore() {
        if (nextPage === null || pendingRead || libraryError || pageFailed || loadedGeneration !== generation) return;
        if (reader.busy && reader.request.before) return;
        pendingRead = { op: "list", query: appliedQuery, folderId: folderId || null, before: nextPage, generation: generation };
        pumpRead();
    }
    function loadMoreNearEnd() {
        if (list.contentHeight - (list.contentY - list.originY) - list.height < Style.space(420)) loadMore();
    }
    // Updates in place: set() only wakes what really changed, so reopening an unchanged list costs nothing on screen.
    function fill(model, rows) {
        var shared = Math.min(model.count, rows.length);
        for (let i = 0; i < shared; i++) model.set(i, rows[i]);
        if (model.count > shared) model.remove(shared, model.count - shared);
        else if (rows.length > shared) model.append(rows.slice(shared));
    }
    function adoptFolders(found) {
        if (JSON.stringify(folders) === JSON.stringify(found)) return;
        folders = found;
        fill(folderRows, found);
    }
    function listRead(job, data) {
        if (!State.validList(data)) { readFailed(job); return; }
        adoptFolders(State.goodFolders(data));
        libraryCount = data.all;
        if (job.counts) { total = data.total; return; }
        var rows = State.goodRows(data).map(function(b) {
            return { id: b.id, url: b.url, title: b.title, folderId: b.folderId || 0, favicon: b.favicon, hasNote: b.hasNote, preview: b.preview };
        });
        if (job.before) bookmarks.append(rows);
        else {
            fill(bookmarks, rows);
            list.currentIndex = rows.length ? 0 : -1;
            list.positionViewAtBeginning();
        }
        total = data.total;
        nextPage = data.next;
        appliedQuery = job.query;
        loaded = true;
        libraryError = false;
        loadedGeneration = job.generation;
        if (pendingFocusIndex >= 0) focusRow(pendingFocusIndex);
        if (revealId) reveal();
        else Qt.callLater(loadMoreNearEnd);
    }
    function readDone(job, reply) {
        if (job.clipboard) clipboardRead(job, reply);
        else if (!reply.ok) readFailed(job);
        else if (job.op === "list") listRead(job, reply.result);
        else if (job.id === expandedId) {
            if (reply.result && typeof reply.result.notes === "string" && reply.result.notes.length <= 65536) {
                loadedNoteId = job.id; loadedNote = reply.result.notes;
                Qt.callLater(keepOpenRowInView);
            } else noteFailed = true;
        }
    }
    function readFailed(job) {
        if (job.op === "note") noteFailed = job.id === expandedId;
        else if (job.before) pageFailed = true;
        else if (!job.counts && !job.clipboard) {
            libraryError = true;
            nextPage = null;
            bookmarks.clear();
            loadedGeneration = job.generation;
        }
    }
    function clipboardRead(job, reply) {
        var saved = reply.ok && Array.isArray(reply.result.items) && reply.result.items.some(function(b) { return b.url === job.query || b.url === job.query + "/"; });
        if (saved && addUrl === job.query) addUrl = "";
    }
    // Show it can point at a row further down than the pages loaded so far.
    function reveal() {
        var index = rowIndex(revealId), id = revealId;
        if (index >= 0) {
            revealId = 0;
            list.currentIndex = index;
            expand(id, false);
        } else if (nextPage !== null) loadMore();
        else revealId = 0;
    }

    function expand(id, withEditor) {
        if (expandedId !== id && !store.drafts[id] && Object.keys(store.drafts).length >= 100) {
            toast.show("Save or retry the pending notes before editing another bookmark.", true); return;
        }
        flush();
        if (expandedId === id) { expandedId = 0; return; }
        expandedId = id; loadedNoteId = 0; loadedNote = ""; savedNoteId = 0; noteFailed = false;
        editorWanted = !!withEditor;
        pumpRead();
        Qt.callLater(keepOpenRowInView);
    }
    function keepOpenRowInView() {
        var index = rowIndex(expandedId);
        if (index < 0) return;
        var item = list.itemAtIndex(index);
        list.positionViewAtIndex(index, item && item.height > list.height ? ListView.Beginning : ListView.Contain);
    }
    function noteText(id) {
        var ignored = revision;
        return store.drafts[id] ? store.drafts[id].notes : loadedNoteId === id ? loadedNote : "";
    }
    function editNote(id, value) {
        if (value.length > 21845 && State.byteLength(value) > 65536) {
            toast.show("Note limit reached. Copy your text before leaving this editor.", true);
            return;
        }
        if (!State.edit(store, id, value)) {
            toast.show("Note limit reached. Copy your text before leaving this editor.", true);
            return;
        }
        savedNoteId = 0;
        revision++; saveTimer.restart();
    }
    function flush() { saveTimer.stop(); State.flush(store); pumpWrite(); }
    function mutate(job) {
        if (store.queue.length >= 200) { toast.show("Too many pending changes. Retry the current save first.", true); return; }
        State.enqueue(store, job); revision++; pumpWrite();
    }
    function pumpWrite() {
        if (writer.busy) return;
        var job = State.next(store);
        if (job) { revision++; writer.start(job); }
    }
    function retry() {
        noteFailed = false;
        State.retry(store); revision++;
        pumpWrite(); pumpRead();
    }
    function retryLibrary() { libraryError = false; loaded = false; reload(); }
    function retryPage() { pageFailed = false; loadMore(); }
    function formBusy() { return store.active !== null && store.active.form === true; }
    function dropFailedForm(ops) { State.cancelFailedForm(store, ops); revision++; pumpWrite(); }

    function written(job, result) {
        var index = rowIndex(job.id), name = folderName(job.id), after = folderEdit ? folderEdit.after : null;
        if (job.op === "saveNote") {
            if (loadedNoteId === job.id) loadedNote = job.notes;
            if (job.id === expandedId) savedNoteId = job.id;
            if (index >= 0) {
                bookmarks.setProperty(index, "hasNote", job.notes.length > 0);
                bookmarks.setProperty(index, "preview", State.preview(job.notes, appliedQuery));
            }
        } else if (job.op === "renameBookmark") {
            if (index >= 0) bookmarks.setProperty(index, "title", job.title);
            if (renamingId === job.id) { stopRename(); returnFocus(); }
            if (appliedQuery) reload();
        } else if (job.op === "move") {
            moved(job);
        } else if (job.op === "capture") {
            if (!result.added) { addDuplicateId = result.id; return; }
            closeAdd();
            flashId = result.id;
            flash.restart();
            toast.show("Bookmark added");
            search.text = "";
            reload();
        } else if (job.op === "createFolder") {
            adoptFolders(folders.concat([{ id: result.id, name: job.name, count: 0 }]));
            stopFolderEdit();
            if (after) after(result.id, job.name);
            refreshCounts();
        } else if (job.op === "renameFolder") {
            adoptFolders(folders.map(function(f) { return f.id === job.id ? { id: f.id, name: job.name, count: f.count } : f; }));
            stopFolderEdit();
            refreshCounts();
        } else if (job.op === "deleteBookmark") {
            if (expandedId === job.id) expandedId = 0;
            if (renamingId === job.id) stopRename();
            if (index >= 0) bookmarks.remove(index);
            toast.show("Bookmark deleted");
            refreshCounts();
        } else if (job.op === "undoSort") {
            if (job.created.indexOf(folderId) >= 0) { folderId = 0; expandedId = 0; }
            toast.show("Sort undone");
            reload();
        } else if (job.op === "deleteFolder") {
            toast.show("Folder “" + name + "” deleted. Its bookmarks are in All.");
            if (folderId === job.id) { folderId = 0; expandedId = 0; reload(); }
            else {
                clearFolderTags(job.id);
                refreshCounts();
            }
        }
    }
    function clearFolderTags(id) {
        for (let i = 0; i < bookmarks.count; i++) if (bookmarks.get(i).folderId === id) bookmarks.setProperty(i, "folderId", 0);
    }
    function writeFailed(job, error) {
        var refused = /limit/.test(error) ? "Folder limit reached (200)." : /duplicate/.test(error) ? "That name is already used." : "";
        if (job.op === "capture" && /Invalid URL|HTTP or HTTPS/.test(error)) {
            addError = "Enter a full link, starting with http:// or https://";
            dropFailedForm(["capture"]);
            if (addOpen) (addSheet.item as AddSheet).focusLink();
        } else if (job.op === "capture") {
            addError = "Couldn't save. Your link is still here. Use Retry above.";
        } else if (job.op === "createFolder" || job.op === "renameFolder") {
            folderError = refused || "Couldn't save. Use Retry above.";
            if (refused) dropFailedForm(["createFolder", "renameFolder"]);
        } else if (job.op === "deleteBookmark" || job.op === "deleteFolder") {
            toast.show("Couldn't delete it. Use Retry above.", true);
        }
    }

    function startSort() {
        flush();
        sorter.start({ op: "sort" });
    }
    function sorted(reply) {
        if (!reply.ok) { toast.show(reply.error, true); return; }
        var moved = reply.result.moved, created = reply.result.created;
        reload();
        if (!moved.length) { toast.show("No bookmark fit a folder."); return; }
        var places = new Set(moved.map(function(m) { return m.folderId; })).size;
        toast.show("Sorted " + State.plural(moved.length, "bookmark") + " into " + State.plural(places, "folder"), false, function() {
            root.mutate({ op: "undoSort", moves: moved, created: created });
        });
    }
    function openLink(url) {
        if (State.safeUrl(url)) { Qt.openUrlExternally(url); dismiss(); }
        else toast.show("This bookmark has an invalid URL.", true);
    }
    function copyLink(url) {
        if (!State.safeUrl(url)) { toast.show("This bookmark has an invalid URL.", true); return; }
        Quickshell.clipboardText = url;
        toast.show("Link copied");
    }
    function moveTo(row, target, name) {
        if ((row.folderId || 0) === target) return;
        mutate({ op: "move", id: row.id, folderId: target || null, from: row.folderId || 0, name: name || "", undoable: true });
    }
    function moved(job) {
        var target = job.folderId || 0, index = rowIndex(job.id), row = null, back = restoreRow ? restoreRow.row : null;
        if (index >= 0 && folderId && folderId !== target) {
            row = { index: index, id: job.id, row: rowSnapshot(index) };
            if (expandedId === job.id) expandedId = 0;
            bookmarks.remove(index);
            if (list.activeFocus) focusRow(index);
        } else if (index >= 0) bookmarks.setProperty(index, "folderId", target);
        else if (restoreRow && restoreRow.id === job.id && folderId === target) {
            bookmarks.insert(Math.min(restoreRow.index, bookmarks.count), { id: back.id, url: back.url, title: back.title, folderId: target, favicon: back.favicon, hasNote: back.hasNote, preview: back.preview });
        }
        restoreRow = null;
        refreshCounts();
        if (!job.undoable) return;
        toast.show(target ? "Moved to " + (job.name || folderName(target)) : "Removed from folder", false, function() {
            root.restoreRow = row;
            root.mutate({ op: "move", id: job.id, folderId: job.from || null, from: target, name: "", undoable: false });
            root.returnFocus(); // Undo goes away with its toast and must not take the keyboard with it.
        });
    }

    function startRename(row) { stopRename(); renameText = row.title; renamingId = row.id; }
    function saveRename() {
        var title = renameText.trim();
        renameError = title ? "" : "Enter a title.";
        if (!title || formBusy()) return;
        dropFailedForm(["renameBookmark"]);
        mutate({ op: "renameBookmark", id: renamingId, title: title, form: true });
    }
    function stopRename() { renamingId = 0; renameError = ""; renameText = ""; }
    function cancelRename() { stopRename(); dropFailedForm(["renameBookmark"]); returnFocus(); }

    function startNewFolder(after) {
        if (folders.length >= 200) { toast.show("Folder limit reached (200).", true); return; }
        folderText = ""; folderError = "";
        folderEdit = { mode: "new", id: 0, after: after || null };
    }
    function startRenameFolder(folder) {
        folderText = folder.name; folderError = "";
        folderEdit = { mode: "rename", id: folder.id, after: null };
    }
    function saveFolderName() {
        var edit = folderEdit, name = folderText.trim();
        if (!edit) return;
        folderError = State.folderProblem(name, folders, edit.id);
        if (folderError || formBusy()) return;
        dropFailedForm(["createFolder", "renameFolder"]);
        mutate(edit.mode === "new" ? { op: "createFolder", name: name, form: true } : { op: "renameFolder", id: edit.id, name: name, form: true });
    }
    function stopFolderEdit() { folderEdit = null; folderError = ""; returnFocus(); }
    function cancelFolderName() { dropFailedForm(["createFolder", "renameFolder"]); stopFolderEdit(); }

    function openAdd() {
        if (addOpen) { (addSheet.item as AddSheet).focusLink(); return; }
        var clip = String(Quickshell.clipboardText || "").trim();
        var usable = State.safeUrl(clip) && clip.length <= 4096;
        addUrl = usable ? clip : ""; addTitle = "";
        addError = ""; addDuplicateId = 0;
        addFolderId = folderId;
        addOpen = true;
        if (usable) { clipboardPending = clip; pumpRead(); }
    }
    function submitAdd() {
        var url = addUrl.trim();
        addDuplicateId = 0;
        addError = url ? "" : "Enter a full link, starting with http:// or https://";
        if (!url) (addSheet.item as AddSheet).focusLink();
        if (!url || formBusy()) return;
        dropFailedForm(["capture"]);
        mutate({ op: "capture", url: url, title: addTitle.trim(), folderId: addFolderId || null, form: true });
    }
    function closeAdd() {
        addOpen = false;
        addError = ""; addDuplicateId = 0; addUrl = ""; addTitle = "";
        dropFailedForm(["capture"]);
        returnFocus();
    }
    function showDuplicate() {
        var id = addDuplicateId;
        closeAdd();
        flush(); stopRename();
        search.text = ""; folderId = 0; expandedId = 0; revealId = id;
        reload();
    }

    function folderEntries(current, filter, pick) {
        var wanted = filter.toLowerCase();
        var rows = [{ id: 0, name: "No folder" }].concat(folders).filter(function(f) { return !wanted || f.name.toLowerCase().indexOf(wanted) >= 0; });
        var entries = rows.map(function(f) {
            return { icon: f.id === current ? Icons.check : Icons.folder, label: f.name, on: f.id === current, run: function() { pick(f.id, f.name); } };
        });
        if (!rows.length) entries.push({ icon: Icons.noResult, label: "No matching folder", none: true });
        if (!wanted) entries.push("-", { icon: Icons.folderPlus, label: "New folder…", run: function() { root.startNewFolder(pick); } });
        return entries;
    }
    function holdFocus() { focusBefore = content.Window.activeFocusItem; }
    function pickFolderFor(row, at) {
        holdFocus();
        popup().showPicker(function(filter) {
            return root.folderEntries(row.folderId || 0, filter, function(id, name) { root.moveTo(row, id, name); });
        }, folders.length > 8, at);
    }
    function pickAddFolder(button) {
        holdFocus();
        popup().showPicker(function(filter) {
            return root.folderEntries(root.addFolderId, filter, function(id) { root.addFolderId = id; });
        }, folders.length > 8, { anchor: button, alignLeft: true });
    }
    function rowMenu(row, at) {
        holdFocus();
        popup().show([
            { icon: Icons.open, label: "Open page", key: "Enter", run: function() { root.openLink(row.url); } },
            { icon: row.hasNote ? Icons.note : Icons.plus, label: row.hasNote ? "Edit note" : "Add note", key: "E", run: function() { if (root.expandedId !== row.id) root.expand(row.id, true); else root.editorWanted = true; } },
            { icon: Icons.move, label: "Move to folder…", key: "F", run: function() { root.pickFolderFor(row, at); } },
            { icon: Icons.copy, label: "Copy link", run: function() { root.copyLink(row.url); } },
            { icon: Icons.edit, label: "Rename", key: "R", run: function() { root.startRename(row); } },
            "-",
            { icon: Icons.trash, label: "Delete…", key: "D", danger: true, run: function() { root.askDelete(row); } }
        ], at);
    }
    function folderMenu(folder, at) {
        holdFocus();
        popup().show([
            { icon: Icons.edit, label: "Rename folder", key: "R", run: function() { root.startRenameFolder(folder); } },
            "-",
            { icon: Icons.trash, label: "Delete folder…", key: "D", danger: true, run: function() { root.askDeleteFolder(folder); } }
        ], at);
    }
    function viewsMenu(at) {
        var entries = [{ icon: Icons.all, label: "All bookmarks", on: !folderId, run: function() { root.chooseFolder(0); } }, "-"];
        folders.forEach(function(f) {
            entries.push({ icon: f.id === root.folderId ? Icons.folderOpen : Icons.folder, label: f.name + "  (" + State.comma(f.count) + ")", on: f.id === root.folderId, run: function() { root.chooseFolder(f.id); } });
        });
        if (folders.length) entries.push("-");
        entries.push({ icon: Icons.folderPlus, label: "New folder…", run: function() { root.startNewFolder(null); } });
        if (unfiled > 0 && !sorter.busy) entries.push({ icon: Icons.sort, label: sortLabel, run: function() { root.startSort(); } });
        holdFocus();
        popup().show(entries, at);
    }
    function listMenu(x, y) {
        holdFocus();
        popup().show([
            { icon: Icons.plus, label: "Add bookmark", key: "Ctrl N", run: function() { root.openAdd(); } },
            { icon: Icons.folderPlus, label: "New folder", key: "Ctrl Shift N", run: function() { root.startNewFolder(null); } }
        ], { x: x, y: y });
    }
    function askDelete(row) { holdFocus(); dialog().show("bookmark", row); }
    function askDeleteFolder(folder) { holdFocus(); dialog().show("folder", folder); }
    function showKeys() { holdFocus(); dialog().show("keys"); }

    function beginDrag(row) {
        ghostHost.active = true;
        dragBookmark = row;
        if (popupHost.item) popup().close(true);
    }
    function moveDrag(point) {
        (ghostHost.item as Item).x = point.x + Style.space(12);
        (ghostHost.item as Item).y = point.y + Style.space(10);
    }
    function endDrag() {
        if (!dragBookmark) return;
        var row = dragBookmark, target = dropId;
        dragBookmark = null; dropId = -1;
        if (target >= 0) moveTo(row, target);
    }

    function escapePressed() {
        var index = rowIndex(expandedId);
        if (renamingId) cancelRename();
        else if (folderEdit) cancelFolderName();
        else if (addOpen) closeAdd();
        else if (expandedId) {
            expand(expandedId, false);
            keyboard = true;
            focusRow(index);
        } else if (search.activeFocus) list.forceActiveFocus();
        else dismiss();
    }
    function appKey(event) {
        if (modal || popupHost.item && popup().visible) return;
        if (event.key === Qt.Key_F && event.modifiers & Qt.ControlModifier) { focusSearch(); event.accepted = true; }
        else if (event.key === Qt.Key_N && event.modifiers & Qt.ControlModifier) {
            if (event.modifiers & Qt.ShiftModifier) startNewFolder(null); else openAdd();
            event.accepted = true;
        }
    }
    function listKey(event) {
        if (event.text === "/") { focusSearch(); event.accepted = true; return; }
        if (event.text === "?") { showKeys(); event.accepted = true; return; }
        if (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) return;
        var keys = [Qt.Key_Up, Qt.Key_Down, Qt.Key_Left, Qt.Key_Right, Qt.Key_Return, Qt.Key_Enter, Qt.Key_E, Qt.Key_F, Qt.Key_R, Qt.Key_D];
        if (keys.indexOf(event.key) < 0) return;
        event.accepted = true;
        keyboard = true;
        var index = Math.max(0, list.currentIndex), item = list.itemAtIndex(index), row = null, at = null;
        if (event.key === Qt.Key_Left && (!bookmarks.count || expandedId !== bookmarks.get(index).id)) { focusFolders(); return; }
        if (!bookmarks.count) return;
        row = rowSnapshot(index);
        if (event.key === Qt.Key_Up || event.key === Qt.Key_Down) focusRow(index + (event.key === Qt.Key_Down ? 1 : -1));
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) openLink(row.url);
        else if (event.key === Qt.Key_Right) { if (expandedId !== row.id) expand(row.id, false); }
        else if (event.key === Qt.Key_Left) expand(row.id, false);
        else if (event.key === Qt.Key_E) { if (expandedId !== row.id) expand(row.id, true); else editorWanted = true; }
        else if (event.key === Qt.Key_R) startRename(row);
        else if (event.key === Qt.Key_D) askDelete(row);
        else if (event.key === Qt.Key_F) {
            at = item ? item.mapToItem(content, item.width - Style.space(217), Style.space(25)) : Qt.point(Style.space(40), Style.space(100));
            pickFolderFor(row, { x: at.x, y: at.y });
        }
    }
    function folderKey(event) {
        if (event.text === "/") { focusSearch(); event.accepted = true; return; }
        if (event.text === "?") { showKeys(); event.accepted = true; return; }
        if (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) return;
        var folder = folderId ? { id: folderId, name: viewName, count: total } : null;
        if (event.key === Qt.Key_Down || event.key === Qt.Key_Up) { keyboard = true; navigateFolder(event.key === Qt.Key_Down ? 1 : -1); }
        else if (event.key === Qt.Key_Right) { keyboard = true; focusRow(0); }
        else if (event.key === Qt.Key_R && folder) startRenameFolder(folder);
        else if (event.key === Qt.Key_D && folder) askDeleteFolder(folder);
        else return;
        event.accepted = true;
    }

    Timer { id: saveTimer; interval: 350; onTriggered: root.flush() }
    NumberAnimation { id: flash; target: root; property: "flashLevel"; from: 1; to: 0; duration: 1100 }
    Helper {
        id: reader
        objectName: "reader"
        pluginDir: root.pluginDir
        onCompleted: {
            var job = reader.request;
            if (job.generation === undefined || job.generation === root.generation) root.readDone(job, reader.parsed());
            Qt.callLater(root.pumpRead);
        }
    }
    Helper {
        id: sorter
        objectName: "sorter"
        pluginDir: root.pluginDir
        mode: "--sort"
        // The agent lives outside the fixed path the other helpers use. It still gets no other variables.
        path: Quickshell.env("PATH") || "/usr/bin:/bin"
        onCompleted: root.sorted(sorter.parsed())
    }
    Helper {
        id: writer
        objectName: "writer"
        pluginDir: root.pluginDir
        onCompleted: {
            var job = writer.request, reply = writer.parsed();
            State.finish(root.store, reply.ok); root.revision++;
            if (reply.ok) root.written(job, reply.result);
            else root.writeFailed(job, reply.error);
            Qt.callLater(root.pumpWrite);
        }
    }

    FloatingWindow {
        id: window
        objectName: "omakeepWindow"
        visible: root.opened
        title: "Omakeep"
        color: Commons.Color.background
        implicitWidth: Style.space(900)
        implicitHeight: Style.space(650)
        minimumSize: Qt.size(Style.space(440), Style.space(400))
        onVisibleChanged: if (!visible && root.opened) root.dismiss()

        FocusScope {
            id: content
            objectName: "omakeepContent"
            anchors.fill: parent
            focus: true
            Keys.onEscapePressed: root.escapePressed()
            Keys.onPressed: function(event) { root.appKey(event); }
            property point lastPointer: Qt.point(-1, -1)
            HoverHandler {
                // The keyboard cursor stays until the mouse really moves, not when the list scrolls under it.
                onPointChanged: {
                    if (point.position === content.lastPointer) return;
                    content.lastPointer = point.position;
                    root.keyboard = false;
                }
            }
            ColumnLayout {
                anchors.fill: parent
                spacing: 0
                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Style.space(47)
                    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Commons.Color.muted }
                    RowLayout {
                        anchors.fill: parent
                        anchors.rightMargin: Style.space(8)
                        spacing: Style.space(7)
                        Row {
                            Layout.preferredWidth: root.narrow ? implicitWidth + Style.space(10) : root.sideWidth
                            Layout.leftMargin: 0
                            leftPadding: Style.space(10)
                            spacing: Style.space(7)
                            Glyph {
                                anchors.verticalCenter: parent.verticalCenter
                                text: Icons.bookmark
                                color: Commons.Color.accent
                                font.pixelSize: Style.space(17)
                            }
                            Label {
                                visible: !root.narrow
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Omakeep"
                                color: root.hotInk
                                size: "subtitle"; font.bold: true
                            }
                        }
                        Ui.TextField {
                            id: search
                            objectName: "bookmarkSearch"
                            Layout.fillWidth: true
                            implicitHeight: Style.space(32)
                            verticalPadding: 0
                            leftPadding: Style.space(35)
                            rightPadding: Style.space(29)
                            placeholderText: root.folderId ? "Search " + root.viewName : "Search all bookmarks"
                            maximumLength: 4096
                            Accessible.name: "Search bookmarks"
                            // One run at a time and only the newest query waits, so fast typing can't queue up work.
                            onTextEdited: root.reload()
                            onActiveFocusChanged: if (activeFocus) { root.folderZone = false; root.pendingFocusIndex = -1; }
                            Keys.onDownPressed: { root.keyboard = true; root.focusRow(0); }
                            Glyph {
                                x: Style.space(8)
                                anchors.verticalCenter: parent.verticalCenter
                                text: Icons.search
                                color: root.dim
                            }
                            KeepButton {
                                objectName: "clearSearch"
                                visible: search.text !== ""
                                anchors.right: parent.right
                                anchors.rightMargin: Style.space(3)
                                anchors.verticalCenter: parent.verticalCenter
                                small: true
                                icon: Icons.close
                                tooltipText: "Clear search"
                                Accessible.name: "Clear search"
                                onClicked: { root.clearSearch(); search.forceActiveFocus(); }
                            }
                        }
                        KeepButton {
                            objectName: "addButton"
                            accented: true
                            icon: Icons.plus
                            label: root.compact ? "" : "Add bookmark"
                            tooltipText: "Add a bookmark by link"
                            Accessible.name: "Add bookmark"
                            onClicked: root.openAdd()
                        }
                        KeepButton {
                            objectName: "keysButton"
                            icon: Icons.keys
                            tooltipText: "Keyboard shortcuts"
                            Accessible.name: "Keyboard shortcuts"
                            onClicked: root.showKeys()
                        }
                        KeepButton {
                            objectName: "closeButton"
                            icon: Icons.close
                            tooltipText: "Close Omakeep"
                            Accessible.name: "Close Omakeep"
                            onClicked: root.dismiss()
                        }
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 0
                    Rectangle {
                        visible: !root.narrow
                        Layout.preferredWidth: root.sideWidth
                        Layout.fillHeight: true
                        color: root.barColors.background
                        Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: Commons.Color.muted }
                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.RightButton
                            onClicked: function(mouse) {
                                let at = mapToItem(content, mouse.x, mouse.y);
                                root.holdFocus();
                                root.popup().show([{ icon: Icons.folderPlus, label: "New folder", key: "Ctrl Shift N", run: function() { root.startNewFolder(null); } }], { x: at.x, y: at.y });
                            }
                        }
                        Item {
                            id: sideKeys
                            objectName: "folderZone"
                            anchors.fill: parent
                            anchors.margins: Style.space(7)
                            anchors.rightMargin: Style.space(7) + 1
                            activeFocusOnTab: true
                            Accessible.name: "Folders"
                            Keys.onPressed: function(event) { root.folderKey(event); }
                            onActiveFocusChanged: if (activeFocus) { root.folderZone = true; root.pendingFocusIndex = -1; }
                            ListView {
                                id: sideScroll
                                width: parent.width
                                height: Math.min(contentHeight, parent.height - newFolder.height - Style.space(5) - (sortButton.visible ? sortButton.height + Style.space(3) : 0))
                                clip: true
                                spacing: 2
                                boundsBehavior: Flickable.StopAtBounds
                                Controls.ScrollBar.vertical: Controls.ScrollBar { policy: sideScroll.contentHeight > sideScroll.height ? Controls.ScrollBar.AsNeeded : Controls.ScrollBar.AlwaysOff }
                                model: folderRows
                                header: Column {
                                    width: sideScroll.width
                                    spacing: 2
                                    bottomPadding: sideScroll.count ? 2 : 0
                                    FolderRow {
                                        width: parent.width
                                        app: root
                                        folder: ({ id: 0, name: "All", count: root.libraryCount })
                                    }
                                    Item {
                                        width: parent.width
                                        height: Style.space(9)
                                        Rectangle { anchors.centerIn: parent; width: parent.width - 4; height: 1; color: root.line }
                                    }
                                }
                                delegate: Column {
                                    id: slot
                                    required property var model
                                    // A copy, because the model object vanishes before the row is gone.
                                    readonly property var folder: ({ id: model.id, name: model.name, count: model.count })
                                    readonly property bool editing: root.folderEdit !== null && root.folderEdit.mode === "rename" && root.folderEdit.id === folder.id
                                    width: sideScroll.width
                                    FolderRow { visible: !slot.editing; width: parent.width; app: root; folder: slot.folder }
                                    Loader {
                                        active: slot.editing && !root.narrow
                                        visible: active
                                        width: parent.width
                                        sourceComponent: FolderNameEditor { app: root }
                                    }
                                }
                                footer: Item {
                                    width: sideScroll.width
                                    height: newEditor.active ? newEditor.height + 2 : 0
                                    Loader {
                                        id: newEditor
                                        y: 2
                                        active: root.folderEdit !== null && root.folderEdit.mode === "new" && !root.narrow
                                        width: parent.width
                                        sourceComponent: FolderNameEditor { app: root }
                                        onLoaded: Qt.callLater(sideScroll.positionViewAtEnd)
                                    }
                                }
                            }
                            KeepButton {
                                id: newFolder
                                objectName: "newFolder"
                                y: sideScroll.height + Style.space(5)
                                width: parent.width
                                implicitHeight: Style.space(30)
                                leftAlign: true
                                bordered: true
                                size: "body"
                                icon: Icons.plus
                                label: "New folder"
                                onClicked: root.startNewFolder(null)
                            }
                            KeepButton {
                                id: sortButton
                                objectName: "sortButton"
                                visible: root.unfiled > 0 || sorter.busy
                                enabled: !sorter.busy
                                y: newFolder.y + newFolder.height + Style.space(3)
                                width: parent.width
                                implicitHeight: Style.space(30)
                                leftAlign: true
                                bordered: true
                                size: "body"
                                icon: Icons.sort
                                label: root.sortLabel
                                tooltipText: "Your default agent files bookmarks that have no folder. It sees their titles and links, not your notes."
                                onClicked: root.startSort()
                            }
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.minimumWidth: 0
                        spacing: 0
                        Item {
                            Layout.fillWidth: true
                            Layout.preferredHeight: Math.max(Style.space(38), root.narrow && root.folderEdit ? headEdit.height + Style.space(7) : 0)
                            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Commons.Color.muted }
                            RowLayout {
                                visible: !headEdit.active
                                anchors.fill: parent
                                anchors.leftMargin: Style.space(10)
                                anchors.rightMargin: Style.space(8)
                                anchors.bottomMargin: 1
                                spacing: Style.space(7)
                                Label {
                                    objectName: "viewName"
                                    visible: !root.narrow
                                    Layout.preferredWidth: implicitWidth
                                    Layout.minimumWidth: Style.space(40)
                                    text: root.viewName
                                    color: root.hotInk
                                    size: "title"; font.bold: true
                                }
                                KeepButton {
                                    id: viewButton
                                    objectName: "viewButton"
                                    visible: root.narrow
                                    bordered: true
                                    icon: root.folderId ? Icons.folderOpen : Icons.all
                                    label: root.viewName
                                    labelLimit: Style.space(150)
                                    trailing: Icons.down
                                    size: "body"
                                    strong: true
                                    ink: root.hotInk
                                    tooltipText: "Switch folder"
                                    Accessible.name: "Switch folder"
                                    onClicked: root.viewsMenu({ anchor: viewButton, alignLeft: true })
                                    onActiveFocusChanged: if (activeFocus) { root.folderZone = true; root.pendingFocusIndex = -1; }
                                    Keys.onPressed: function(event) { root.folderKey(event); }
                                }
                                Label {
                                    objectName: "viewCount"
                                    visible: !root.libraryError && root.loaded
                                    text: root.appliedQuery ? State.plural(root.total, "result") : State.comma(root.total)
                                    color: root.dim
                                    size: "bodySmall"
                                }
                                Item { Layout.fillWidth: true }
                                KeepButton {
                                    objectName: "headSearchAll"
                                    visible: root.appliedQuery !== "" && root.folderId !== 0 && root.total > 0
                                    bordered: true
                                    label: "Search all"
                                    onClicked: root.chooseFolder(0)
                                }
                                KeepButton {
                                    objectName: "headRename"
                                    visible: !root.appliedQuery && root.folderId !== 0
                                    bordered: true
                                    icon: Icons.edit
                                    label: root.compact ? "" : "Rename"
                                    tooltipText: root.compact ? "Rename folder" : ""
                                    Accessible.name: "Rename folder"
                                    onClicked: root.startRenameFolder({ id: root.folderId, name: root.viewName })
                                }
                                KeepButton {
                                    objectName: "headDelete"
                                    visible: !root.appliedQuery && root.folderId !== 0
                                    bordered: true
                                    danger: true
                                    icon: Icons.trash
                                    label: root.compact ? "" : "Delete"
                                    tooltipText: root.compact ? "Delete folder" : ""
                                    Accessible.name: "Delete folder"
                                    onClicked: root.askDeleteFolder({ id: root.folderId, name: root.viewName, count: root.total })
                                }
                                KeepButton {
                                    objectName: "headNewFolder"
                                    visible: root.narrow
                                    bordered: true
                                    icon: Icons.folderPlus
                                    tooltipText: "New folder"
                                    Accessible.name: "New folder"
                                    onClicked: root.startNewFolder(null)
                                }
                            }
                            Loader {
                                id: headEdit
                                active: root.narrow && root.folderEdit !== null
                                x: Style.space(10)
                                y: Style.space(3)
                                width: parent.width - Style.space(18)
                                sourceComponent: FolderNameEditor { app: root; wide: true }
                            }
                        }
                        Rectangle {
                            objectName: "banner"
                            visible: root.failure !== ""
                            Layout.fillWidth: true
                            implicitHeight: bannerRow.implicitHeight + Style.space(13)
                            color: Util.alpha(Commons.Color.urgent, 0.16)
                            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Commons.Color.urgent }
                            RowLayout {
                                id: bannerRow
                                anchors.fill: parent
                                anchors.leftMargin: Style.space(10)
                                anchors.rightMargin: Style.space(8)
                                spacing: Style.space(8)
                                Glyph { text: Icons.alert; color: root.errorInk }
                                Label {
                                    objectName: "bannerText"
                                    Layout.fillWidth: true
                                    text: root.failure
                                    color: root.hotInk
                                    size: "bodySmall"
                                    wrapMode: Text.Wrap; elide: Text.ElideNone
                                }
                                KeepButton {
                                    objectName: "bannerRetry"
                                    small: true; bordered: true; danger: true
                                    icon: Icons.retry; label: "Retry"
                                    onClicked: root.retry()
                                }
                            }
                        }
                        Loader {
                            id: addSheet
                            active: root.addOpen
                            visible: active
                            Layout.fillWidth: true
                            sourceComponent: AddSheet { app: root }
                        }
                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            MouseArea {
                                anchors.fill: parent
                                acceptedButtons: Qt.RightButton
                                onClicked: function(mouse) {
                                    let at = mapToItem(content, mouse.x, mouse.y);
                                    root.listMenu(at.x, at.y);
                                }
                            }
                            ListView {
                                id: list
                                objectName: "bookmarkList"
                                anchors.fill: parent
                                anchors.rightMargin: listBar.width
                                // Rows drag onto folders, so the list moves by wheel and scrollbar only.
                                interactive: false
                                reuseItems: true
                                cacheBuffer: Style.space(300)
                                model: bookmarks
                                currentIndex: -1
                                highlightFollowsCurrentItem: false
                                activeFocusOnTab: true
                                boundsBehavior: Flickable.StopAtBounds
                                Accessible.name: "Bookmarks"
                                Keys.onPressed: function(event) { root.listKey(event); }
                                onActiveFocusChanged: if (activeFocus) root.folderZone = false
                                onContentYChanged: root.loadMoreNearEnd()
                                onHeightChanged: root.loadMoreNearEnd()
                                Controls.ScrollBar.vertical: Controls.ScrollBar {
                                    id: listBar
                                    objectName: "listScrollBar"
                                    parent: list.parent
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.bottom: parent.bottom
                                    width: Style.space(11)
                                    padding: 0
                                    leftPadding: hovered || pressed ? 3 : 4
                                    rightPadding: hovered || pressed ? 2 : 3
                                    policy: Controls.ScrollBar.AlwaysOn
                                    background: Rectangle { color: "transparent"; Rectangle { width: 1; height: parent.height; color: root.softLine } }
                                    contentItem: Rectangle {
                                        implicitWidth: Style.space(6)
                                        implicitHeight: Style.space(30)
                                        color: listBar.hovered || listBar.pressed ? Commons.Color.foreground : Commons.Color.muted
                                        visible: listBar.size < 1
                                    }
                                }
                                WheelHandler {
                                    enabled: root.dragBookmark === null
                                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                                    orientation: Qt.Vertical
                                    onWheel: function(event) {
                                        var pixels = event.pixelDelta.y || event.angleDelta.y / 120 * Style.space(100);
                                        var top = list.originY, end = Math.max(top, top + list.contentHeight - list.height);
                                        list.contentY = Math.max(top, Math.min(end, list.contentY - pixels));
                                    }
                                }
                                delegate: BookmarkRow {
                                    id: rowItem
                                    required property int index
                                    required property var model
                                    width: list.width
                                    app: root
                                    bookmark: model
                                    selected: list.currentIndex === index
                                    onSelect: { list.currentIndex = index; root.folderZone = false; list.forceActiveFocus(); }
                                    onKeepInView: Qt.callLater(root.keepOpenRowInView)
                                    // A row waiting for reuse must not hold on to hover or a tooltip.
                                    ListView.onPooled: visible = false
                                    ListView.onReused: visible = true
                                }
                                footer: Item {
                                    width: list.width
                                    height: root.nextPage !== null ? Style.space(37) : 0
                                    visible: height > 0
                                    Row {
                                        anchors.centerIn: parent
                                        spacing: Style.space(8)
                                        Label {
                                            objectName: "listFooter"
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: root.pageFailed ? "Couldn't load more." : "Loading more…  " + State.comma(bookmarks.count) + " of " + State.comma(root.total)
                                            color: root.dim
                                            size: "bodySmall"
                                        }
                                        KeepButton {
                                            objectName: "pageRetry"
                                            visible: root.pageFailed
                                            anchors.verticalCenter: parent.verticalCenter
                                            small: true; bordered: true
                                            icon: Icons.retry; label: "Retry"
                                            onClicked: root.retryPage()
                                        }
                                    }
                                }
                            }
                            Loader {
                                anchors.fill: parent
                                active: bookmarks.count === 0 && (root.loaded || root.libraryError)
                                sourceComponent: Blank { app: root }
                            }
                            Label {
                                anchors.centerIn: parent
                                visible: bookmarks.count === 0 && !root.loaded && !root.libraryError
                                text: "Loading…"
                                color: root.dim
                                size: "bodySmall"
                            }
                        }
                    }
                }
            }
            Toast {
                id: toast
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Style.space(12)
            }
            Loader {
                id: popupHost
                anchors.fill: parent
                active: false
                sourceComponent: PopupMenu { onClosed: root.returnFocus() }
            }
            Loader {
                id: dialogHost
                anchors.fill: parent
                active: false
                sourceComponent: DialogLayer {
                    app: root
                    onClosed: Qt.callLater(root.returnFocus)
                    onConfirmed: function(kind, target) {
                        root.mutate({ op: kind === "bookmark" ? "deleteBookmark" : "deleteFolder", id: target.id });
                    }
                }
            }
            Loader {
                id: ghostHost
                active: false
                sourceComponent: Ui.BorderSurface {
                    objectName: "dragGhost"
                    visible: root.dragBookmark !== null
                    width: Math.min(ghostRow.implicitWidth + Style.space(17), Style.space(283))
                    height: ghostRow.implicitHeight + Style.space(10)
                    color: root.menuColors.background
                    borderSpec: Border.flat(Commons.Color.accent, 2)
                    Drag.active: visible
                    Drag.hotSpot.x: -Style.space(12)
                    Drag.hotSpot.y: -Style.space(10)
                    Row {
                        id: ghostRow
                        x: Style.space(8)
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Style.space(7)
                        Favicon {
                            anchors.verticalCenter: parent.verticalCenter
                            line: root.line
                            icon: root.dragBookmark ? root.dragBookmark.favicon : ""
                            letter: root.dragBookmark ? root.initial(root.dragBookmark) : ""
                        }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            Label {
                                width: Math.min(implicitWidth, Style.space(240))
                                text: root.dragBookmark ? root.rowTitle(root.dragBookmark) : ""
                                color: root.hotInk
                                size: "bodySmall"
                            }
                            Label {
                                objectName: "dragHint"
                                text: root.dropId < 0 ? "Drop on a folder" : root.dropId ? "Move to " + root.folderName(root.dropId) : "Remove from folder"
                                color: root.dropId >= 0 ? Commons.Color.accent : root.dim
                                size: "caption"
                            }
                        }
                    }
                }
            }
        }
    }
}
