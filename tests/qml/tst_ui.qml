import QtQuick
import QtQuick.Window
import Quickshell
import QtTest
import qs.Commons
import qs.Commons as Commons
import "../.." as Omakeep

// One long walk through the real panel on a throwaway library: real keys, a real
// mouse, the real helper. Fake helpers stand in only where a failure is the point.
TestCase {
    id: test
    name: "Omakeep"
    when: windowShown
    width: 920; height: 700
    Omakeep.App { id: app }
    property var win: null
    property var list: null
    property var search: null
    property var reader: null
    property var writer: null
    readonly property string fakes: Quickshell.env("OMAKEEP_TEST_FAKES")
    readonly property string shots: Quickshell.env("OMAKEEP_TEST_SHOTS")

    function by(name, scope) { return findChild(scope || win.contentItem, name) || findChild(app, name); }
    function click(name, scope, button) {
        var item = by(name, scope);
        verify(item, "missing " + name);
        tryVerify(function() { return item.visible; }, 3000, name + " is not visible");
        mouseClick(item, item.width / 2, item.height / 2, button || Qt.LeftButton);
        wait(20);
    }
    function resize(w, h) { win.contentItem.Window.window.width = w; win.contentItem.Window.window.height = h; wait(120); }
    function idle() { tryVerify(function() { return !reader.busy && !writer.busy; }, 5000); wait(30); }
    function drained() { tryVerify(function() { return app.store.active === null && Object.keys(app.store.drafts).length === 0 && !writer.busy; }, 5000); }
    function shown(name) { var item = by(name); return !!item && item.visible; }
    function folder(id) { return app.folders.find(function(f) { return f.id === id; }); }
    function typeText(text) { text.split("").forEach(function(character) { keyClick(character); }); }
    function shot(name) { if (shots) { wait(120); grabImage(win.contentItem).save(shots + "/" + name + ".png"); } }

    function test_walk() {
        try {
            app.open();
            win = findChild(app, "omakeepWindow");
            list = by("bookmarkList"); search = by("bookmarkSearch");
            reader = by("reader"); writer = by("writer");
            if (Quickshell.env("OMAKEEP_TEST_REOPEN") === "1") { reopened(); return; }
            wait(800); // The real theme loads a moment after the panel.
            resize(Style.space(780), Style.space(650));
            firstRun();
            addInPlace();
            keyboardAndNotes();
            saveFailure();
            newFolderAndPicker();
            mouseMenus();
            dragToFolder();
            confirmations();
            emptyFolder();
            rowsNeverBlank();
            scrollFailures();
            narrow();
            lightTheme();
            app.close();
            console.log("OMAKEEP_UI_OK");
        } catch (error) { console.log(error.message + "\n" + error.stack); throw error; }
    }
    function reopened() {
        tryCompare(list, "count", 1, 5000);
        app.expand(1, false);
        tryCompare(app, "loadedNoteId", 1, 5000);
        compare(app.loadedNote, "Saved on collapse");
        compare(list.model.get(0).title, "Renamed page");
        console.log("OMAKEEP_RESTART_OK");
        app.close();
    }
    function firstRun() {
        console.log("UI check: first run");
        tryVerify(function() { return search.activeFocus; });
        tryVerify(function() { return shown("blankAdd"); }, 5000);
        verify(!shown("headRename"), "All bookmarks is not a folder");
    }
    function addInPlace() {
        console.log("UI check: add in place");
        Quickshell.clipboardText = "";
        click("blankAdd");
        tryVerify(function() { return by("addLink").activeFocus; });
        click("addSubmit");
        tryVerify(function() { return shown("addError"); });
        compare(list.count, 0);
        typeText("nonsense");
        click("addSubmit");
        tryCompare(app, "addError", "Enter a full link, starting with http:// or https://", 5000);
        compare(app.store.failed, null, "A refused link is not a stuck save");
        keyClick(Qt.Key_A, Qt.ControlModifier); keyClick(Qt.Key_Backspace);
        typeText("https://example.com");
        by("addTitle").forceActiveFocus();
        typeText("Example page");
        keyClick(Qt.Key_Return);
        tryCompare(list, "count", 1, 5000);
        verify(!app.addOpen, "The sheet closes after adding");
        compare(by("toast").visible, true);

        keyClick(Qt.Key_N, Qt.ControlModifier);
        tryVerify(function() { return app.addOpen; });
        tryVerify(function() { return by("addLink").activeFocus; });
        typeText("https://example.com");
        keyClick(Qt.Key_Return);
        tryVerify(function() { return shown("addDuplicate"); }, 5000);
        compare(list.count, 1, "A duplicate adds nothing");
        click("addShowIt");
        tryVerify(function() { return !app.addOpen && app.expandedId === 1; }, 5000);
        tryCompare(app, "loadedNoteId", 1, 5000);
        keyClick(Qt.Key_Escape);
        tryCompare(app, "expandedId", 0);

        keyClick(Qt.Key_N, Qt.ControlModifier);
        tryVerify(function() { return app.addOpen; });
        keyClick(Qt.Key_Escape);
        tryVerify(function() { return !app.addOpen; });
        compare(by("addSheet"), null, "Add leaves nothing behind");
    }
    function keyboardAndNotes() {
        console.log("UI check: keyboard");
        app.focusRow(0);
        tryVerify(function() { return list.activeFocus; });
        keyClick(Qt.Key_Right);
        compare(app.expandedId, 1);
        tryCompare(app, "loadedNoteId", 1, 5000);
        verify(list.activeFocus);
        var editor = by("noteEditor", list.currentItem);
        keyClick(Qt.Key_E);
        tryVerify(function() { return editor.activeFocus; });
        keyClick(Qt.Key_Escape);
        tryCompare(app, "expandedId", 0);
        keyClick(Qt.Key_E); // A collapsed note loads before its editor takes focus.
        keyClick(Qt.Key_F, Qt.ControlModifier); // Leaving must cancel that pending focus.
        tryCompare(app, "loadedNoteId", 1, 5000);
        verify(search.activeFocus);
        keyClick(Qt.Key_Down);
        tryVerify(function() { return list.activeFocus; });
        keyClick(Qt.Key_E);
        editor = by("noteEditor", list.currentItem);
        tryVerify(function() { return editor.activeFocus; });
        keyClick("/"); keyClick("?"); keyClick("r"); keyClick("d"); keyClick("e"); keyClick("f");
        compare(app.expandedId, 1);
        compare(editor.text, "/?rdef", "Letters in a note are text, not shortcuts");
        compare(shown("dialog"), false);
        keyClick(Qt.Key_A, Qt.ControlModifier); keyClick(Qt.Key_Backspace);
        typeText("A note worth keeping");
        drained();
        compare(app.loadedNote, "A note worth keeping");
        tryVerify(function() { return by("saveStatus").text === "Saved"; }, 3000);
        keyClick(Qt.Key_F, Qt.ControlModifier);
        verify(search.activeFocus);

        console.log("UI check: search");
        typeText("worth");
        tryCompare(app, "appliedQuery", "worth", 3000);
        compare(list.count, 1);
        keyClick(Qt.Key_A, Qt.ControlModifier);
        typeText("example.com"); // A match in the link shows the whole link on the row.
        tryCompare(app, "appliedQuery", "example.com", 3000);
        compare(list.count, 1);
        keyClick(Qt.Key_A, Qt.ControlModifier);
        typeText("zzz");
        tryVerify(function() { return list.count === 0 && shown("blankClear"); }, 3000);
        click("blankClear");
        tryCompare(list, "count", 1, 3000);
        compare(search.text, "");
    }
    function saveFailure() {
        console.log("UI check: failed save and retry");
        app.expandedId = 0;
        app.expand(1, true);
        tryCompare(app, "loadedNoteId", 1, 5000);
        var editor = by("noteEditor", list.currentItem);
        tryVerify(function() { return editor.activeFocus; });
        writer.pluginDir = fakes + "/failing";
        keyClick("!");
        app.flush();
        tryVerify(function() { return app.store.failed !== null; }, 5000);
        tryVerify(function() { return shown("noteRetry"); });
        compare(shown("banner"), false, "An open note shows its own failure");
        compare(app.store.drafts[1].notes, "A note worth keeping!", "The draft stays");
        click("cardCopy", list.currentItem);
        compare(Quickshell.clipboardText, "https://example.com", "Copy works while saving is blocked");
        compare(app.store.failed.op, "saveNote");
        app.copyLink("javascript:alert(1)");
        compare(Quickshell.clipboardText, "https://example.com", "Invalid URLs leave the clipboard intact");
        app.expand(1, false);
        tryVerify(function() { return shown("notSavedChip") && shown("banner"); }, 3000);
        shot("failed-collapsed");
        app.expand(1, false);
        tryCompare(app, "loadedNoteId", 0, 100);
        wait(50);
        tryVerify(function() { return by("noteEditor", list.currentItem).text === "A note worth keeping!"; }, 3000);
        writer.pluginDir = app.pluginDir;
        by("noteEditor", list.currentItem).forceActiveFocus();
        by("noteEditor", list.currentItem).text = "Recovered note";
        click("noteRetry");
        drained();
        tryVerify(function() { return !shown("banner"); });
        tryCompare(app, "loadedNote", "Recovered note", 3000);
        by("noteEditor", list.currentItem).forceActiveFocus();
        by("noteEditor", list.currentItem).text = "Saved on collapse";
        keyClick(Qt.Key_Escape);
        compare(app.expandedId, 0);
        tryVerify(function() { return list.activeFocus; });
        drained();
        tryVerify(function() { return shown("noteLine"); }, 3000);
        compare(list.model.get(0).preview, "Saved on collapse", "The row shows the note");
        keyClick(Qt.Key_E);
        editor = by("noteEditor", list.currentItem);
        tryVerify(function() { return editor.activeFocus; });
        compare(editor.text, "Saved on collapse");
        compare(editor.cursorPosition, editor.length);
        keyClick(Qt.Key_Escape);
        tryCompare(app, "expandedId", 0);
        app.close(); app.open();
        tryVerify(function() { return search.activeFocus; });
        app.expand(1, false);
        tryCompare(app, "loadedNoteId", 1, 5000);
        compare(app.loadedNote, "Saved on collapse");
        app.expand(1, false);
    }
    function newFolderAndPicker() {
        console.log("UI check: folders");
        keyClick(Qt.Key_N, Qt.ControlModifier | Qt.ShiftModifier);
        tryVerify(function() { return by("folderField") && by("folderField").activeFocus; });
        keyClick(Qt.Key_Return);
        tryVerify(function() { return by("folderField") && app.folderError !== ""; });
        typeText("Reading");
        keyClick(Qt.Key_Return);
        tryVerify(function() { return app.folders.length === 1; }, 5000);
        tryCompare(app, "folderEdit", null, 3000);
        compare(app.folders[0].name, "Reading");
        compare(app.folders[0].count, 0);

        console.log("UI check: F folder assignment");
        app.focusRow(0);
        tryVerify(function() { return list.activeFocus; });
        keyClick(Qt.Key_F);
        tryVerify(function() { return shown("popupSurface"); });
        keyClick(Qt.Key_Down);
        compare(list.model.get(0).folderId, 0, "Browsing folders must not move the bookmark");
        keyClick(Qt.Key_Escape);
        tryVerify(function() { return !shown("popupSurface") && list.activeFocus; });
        compare(list.model.get(0).folderId, 0, "Escape cancels folder assignment");
        keyClick(Qt.Key_F);
        tryVerify(function() { return shown("popupSurface"); });
        keyClick(Qt.Key_Down); keyClick(Qt.Key_Return);
        tryVerify(function() { return list.model.get(0).folderId === 1 && list.activeFocus; }, 5000);
        tryVerify(function() { return folder(1).count === 1; }, 5000);
        tryVerify(function() { return shown("toastUndo"); });
        click("toastUndo");
        tryVerify(function() { return list.model.get(0).folderId === 0 && folder(1).count === 0; }, 5000);
        keyClick(Qt.Key_F);
        tryVerify(function() { return shown("popupSurface"); });
        keyClick(Qt.Key_Down); keyClick(Qt.Key_Return);
        tryVerify(function() { return list.model.get(0).folderId === 1; }, 5000);
        app.focusRow(0);

        console.log("UI check: folder keys");
        tryVerify(function() { return list.activeFocus; });
        keyClick(Qt.Key_Left);
        tryVerify(function() { return app.folderZone; });
        keyClick(Qt.Key_R); keyClick(Qt.Key_D);
        compare(shown("dialog"), false, "All is not a user folder");
        compare(app.folderEdit, null);
        keyClick(Qt.Key_Down);
        compare(app.folderId, 1);
        keyClick(Qt.Key_Right); // Enter before the folder read completes.
        tryVerify(function() { return list.activeFocus && list.count === 1; }, 5000);
        compare(list.model.get(0).folderId, 1);
        keyClick(Qt.Key_R);
        tryVerify(function() { return by("renameField") && by("renameField").activeFocus; });
        compare(by("renameField").selectedText, "Example page");
        keyClick(Qt.Key_A, Qt.ControlModifier); keyClick(Qt.Key_Backspace);
        keyClick(Qt.Key_Return);
        tryVerify(function() { return app.renameError !== ""; }, 3000);
        typeText("Renamed page");
        keyClick(Qt.Key_Return);
        tryCompare(app, "renamingId", 0, 5000);
        compare(list.model.get(0).title, "Renamed page");
        tryVerify(function() { return list.activeFocus; });
        keyClick(Qt.Key_Left);
        tryVerify(function() { return app.folderZone; });
        keyClick(Qt.Key_R);
        tryVerify(function() { return by("folderField") && by("folderField").activeFocus; });
        compare(by("folderField").selectedText, "Reading");
        keyClick(Qt.Key_A, Qt.ControlModifier); keyClick(Qt.Key_Backspace);
        typeText("Research");
        keyClick(Qt.Key_Return);
        tryVerify(function() { return folder(1).name === "Research"; }, 5000);
        tryCompare(app, "viewName", "Research", 3000);
        click("folder-1", null, Qt.RightButton);
        tryVerify(function() { return shown("popupSurface"); });
        keyClick(Qt.Key_Escape);
        click("folder-0");
        tryCompare(app, "folderId", 0, 3000);
        idle();
    }
    function mouseMenus() {
        console.log("UI check: mouse menus");
        var row = list.itemAtIndex(0);
        verify(by("noteButton", row).visible && by("moveButton", row).visible && by("moreButton", row).visible, "Row actions are always there");
        mouseMove(row, row.width / 2, 12);
        wait(60);
        mouseClick(row, row.width / 2, 12); // The row opens its page. run-ui.sh checks the log for it.
        idle();
        compare(app.expandedId, 0, "A row click opens the page, not the note");
        mouseClick(row, row.width / 2, 12, Qt.MiddleButton);
        click("noteButton", row);
        tryCompare(app, "loadedNoteId", 1, 5000);
        click("closeNote", row);
        tryCompare(app, "expandedId", 0);
        click("moreButton", row);
        tryVerify(function() { return shown("popupSurface"); });
        Quickshell.clipboardText = "";
        click("menu-Copy link");
        compare(Quickshell.clipboardText, "https://example.com");
        tryVerify(function() { return !shown("popupSurface"); });
        mouseClick(row, row.width / 2, 12, Qt.RightButton);
        tryVerify(function() { return shown("popupSurface"); });
        verify(by("menu-Rename") !== null);
        mouseClick(win.contentItem, 4, win.height - 4); // A click outside only closes it.
        tryVerify(function() { return !shown("popupSurface"); });
        compare(app.folderId, 0);
        click("moveButton", row);
        tryVerify(function() { return shown("popupSurface"); });
        click("menu-No folder");
        tryVerify(function() { return list.model.get(0).folderId === 0; }, 5000);
        tryVerify(function() { return folder(1).count === 0; }, 5000);
        idle();
    }
    function dragToFolder() {
        console.log("UI check: drag to a folder");
        var row = list.itemAtIndex(0), target = by("folder-1");
        var from = row.mapToItem(win.contentItem, Style.space(200), 12), to = target.mapToItem(win.contentItem, target.width / 2, 12);
        mouseMove(win.contentItem, from.x, from.y);
        mousePress(win.contentItem, from.x, from.y);
        mouseMove(win.contentItem, from.x + 2, from.y);
        compare(app.dragBookmark, null, "Small moves stay clicks");
        for (var step = 1; step <= 10; step++) { mouseMove(win.contentItem, from.x + (to.x - from.x) * step / 10, from.y + (to.y - from.y) * step / 10); wait(8); }
        tryVerify(function() { return app.dragBookmark !== null && shown("dragGhost"); }, 2000);
        tryCompare(app, "dropId", 1, 2000);
        shot("drag");
        mouseRelease(win.contentItem, to.x, to.y);
        tryVerify(function() { return list.model.get(0).folderId === 1 && folder(1).count === 1; }, 5000);
        compare(app.dragBookmark, null);
        compare(shown("dragGhost"), false);
        click("toastUndo");
        tryVerify(function() { return list.model.get(0).folderId === 0 && folder(1).count === 0; }, 5000);
        app.moveTo(app.rowSnapshot(0), 1, "Research");
        tryVerify(function() { return list.model.get(0).folderId === 1; }, 5000);
        idle();
    }
    function confirmations() {
        console.log("UI check: confirmations");
        app.focusRow(0);
        tryVerify(function() { return list.activeFocus; });
        keyClick(Qt.Key_D);
        tryVerify(function() { return shown("dialog"); });
        tryVerify(function() { return by("dialogConfirm").activeFocus; });
        keyClick(Qt.Key_Escape);
        tryVerify(function() { return !shown("dialog") && list.activeFocus; });
        compare(list.count, 1, "Cancel must keep the bookmark");
        click("folder-1", null, Qt.RightButton);
        click("menu-Delete folder…");
        tryVerify(function() { return shown("dialog"); });
        click("dialogCancel");
        tryVerify(function() { return !shown("dialog"); });
        compare(app.folders.length, 1);
        click("folder-1");
        tryCompare(app, "folderId", 1, 3000);
        idle();
        click("headDelete");
        tryVerify(function() { return shown("dialog"); });
        keyClick(Qt.Key_Return);
        tryVerify(function() { return app.folders.length === 0 && app.folderId === 0; }, 5000);
        tryCompare(list, "count", 1, 5000);
        compare(list.model.get(0).folderId, 0, "Its bookmarks stay");
        tryCompare(app, "total", 1, 3000);

        // Confirming removes both the bookmark and its note.
        app.mutate({ op: "capture", url: "https://delete.test", title: "Disposable" });
        tryCompare(list, "count", 2, 5000);
        idle();
        app.editNote(2, "Remove this too"); app.flush();
        drained();
        app.focusRow(0);
        tryVerify(function() { return list.activeFocus; });
        compare(list.model.get(0).id, 2);
        click("moreButton", list.itemAtIndex(0));
        click("menu-Delete…");
        tryVerify(function() { return shown("dialog"); });
        click("dialogConfirm");
        tryCompare(list, "count", 1, 5000);
        compare(list.model.get(0).id, 1);
        tryVerify(function() { return list.activeFocus; });

        app.showKeys();
        tryVerify(function() { return shown("dialog") && by("dialogCancel").activeFocus; });
        keyClick(Qt.Key_Escape);
        tryVerify(function() { return !shown("dialog"); });
        keyClick("?");
        tryVerify(function() { return shown("dialog"); });
        keyClick(Qt.Key_Escape);
        tryVerify(function() { return !shown("dialog"); });
    }
    function emptyFolder() {
        console.log("UI check: empty folder");
        app.mutate({ op: "createFolder", name: "Empty" });
        tryVerify(function() { return app.folders.length === 1; }, 5000);
        idle();
        var id = app.folders[0].id;
        click("folder-" + id);
        tryCompare(list, "count", 0, 5000);
        tryVerify(function() { return shown("blankAdd") && shown("blankAll"); });
        click("blankAdd");
        tryVerify(function() { return app.addOpen && app.addFolderId === id; });
        keyClick(Qt.Key_Escape);
        click("blankAll");
        tryCompare(app, "folderId", 0, 3000);
        tryCompare(list, "count", 1, 5000);
        app.expand(1, false);
        tryCompare(app, "loadedNoteId", 1, 5000);
        compare(app.loadedNote, "Saved on collapse");
        app.expand(1, false);
        idle();
    }
    function rowsNeverBlank() {
        console.log("UI check: bad rows and a broken library");
        reader.pluginDir = fakes + "/odd";
        app.reload();
        tryVerify(function() { return list.count === 2; }, 5000);
        compare(app.libraryError, false, "One bad row must not blank the list");
        compare(list.model.get(0).title, "Good row");
        compare(app.rowHost(list.model.get(1)), "No usable link");
        tryVerify(function() { return list.itemAtIndex(1) !== null; });
        var second = list.itemAtIndex(1), title = findChild(second, "bookmarkTitle");
        compare(findChild(second, "moveButton"), null, "A row at rest is plain text");
        mouseMove(second, second.width / 2, 12);
        tryVerify(function() { return findChild(second, "moveButton") !== null && title.font.underline; }, 1000);
        mouseMove(findChild(second, "moveButton"), 4, 4);
        tryVerify(function() { return !title.font.underline; }, 1000, "The title is not the target while a button is");
        mouseMove(win.contentItem, 4, 4);
        reader.pluginDir = fakes + "/failing";
        app.reload();
        tryVerify(function() { return shown("blankRetry"); }, 5000);
        reader.pluginDir = fakes + "/missing";
        click("blankRetry");
        tryVerify(function() { return !reader.busy && shown("blankRetry"); }, 5000); // No helper at all fails the same way.
        reader.pluginDir = app.pluginDir;
        verify(reader.start({ op: "note", id: 999 }));
        verify(!reader.start({ op: "note", id: 999 }), "One run at a time, from the moment it is asked for");
        idle();
        click("blankRetry");
        tryCompare(list, "count", 1, 5000);
        compare(app.libraryError, false);
    }
    function scrollFailures() {
        console.log("UI check: scrolling replaces Load more");
        reader.pluginDir = fakes + "/paging";
        app.reload();
        tryVerify(function() { return shown("pageRetry"); }, 5000);
        compare(list.count, 3, "A failed page keeps the rows already here");
        tryVerify(function() { return shown("listFooter"); });
        reader.pluginDir = fakes + "/pagingok";
        click("pageRetry");
        tryCompare(list, "count", 4, 5000);
        compare(app.nextPage, null);
        compare(shown("pageRetry"), false);
        reader.pluginDir = app.pluginDir;
        app.reload();
        tryCompare(list, "count", 1, 5000);
        idle();
    }
    function narrow() {
        console.log("UI check: narrow");
        resize(Style.space(500), Style.space(620));
        tryVerify(function() { return app.narrow && shown("viewButton"); });
        compare(shown("folder-0"), false, "The sidebar is gone");
        compare(shown("newFolder"), false);
        app.mutate({ op: "createFolder", name: "Small" });
        tryVerify(function() { return app.folders.length === 2; }, 5000);
        idle();
        click("viewButton");
        tryVerify(function() { return shown("popupSurface"); });
        keyClick(Qt.Key_Escape);
        app.focusRow(0);
        tryVerify(function() { return list.activeFocus; });
        keyClick(Qt.Key_Left);
        tryVerify(function() { return by("viewButton").activeFocus; });
        keyClick(Qt.Key_Down);
        tryVerify(function() { return app.folderId !== 0; });
        tryCompare(list, "count", 0, 5000);
        keyClick(Qt.Key_Right);
        tryVerify(function() { return list.activeFocus; });
        keyClick(Qt.Key_Left);
        tryVerify(function() { return by("viewButton").activeFocus; });
        keyClick(Qt.Key_D);
        tryVerify(function() { return shown("dialog"); });
        keyClick(Qt.Key_Return);
        tryVerify(function() { return app.folders.length === 1; }, 5000);
        app.chooseFolder(0);
        tryCompare(list, "count", 1, 5000);
        idle();
        var row = list.itemAtIndex(0), from = row.mapToItem(win.contentItem, 200, 12);
        mousePress(win.contentItem, from.x, from.y);
        mouseMove(win.contentItem, from.x + 20, from.y + 40);
        compare(app.dragBookmark, null, "No drag without a sidebar");
        mouseRelease(win.contentItem, from.x + 20, from.y + 40);
        resize(Style.space(440), Style.space(400));
        compare(by("addButton").label === "" || app.compact, true);
        app.expand(1, false);
        tryCompare(app, "loadedNoteId", 1, 5000);
        verify(by("noteEditor", list.currentItem).visible);
        shot("narrow");
        app.expand(1, false);
    }
    function lightTheme() {
        Commons.Color.background = "#f3efe3"; Commons.Color.foreground = "#314e52"; Commons.Color.accent = "#3f8f8a";
        Commons.Color.shellValues = ({}); Style.styleOverrides = ({});
        wait(100);
        shot("light");
    }
    function cleanupTestCase() { console.log("UI failures: " + qtest_results.failCount); }
}
