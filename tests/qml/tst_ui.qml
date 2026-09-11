import QtQuick
import QtQuick.Window
import Quickshell
import QtTest
import qs.Commons
import "../.." as Omakeep

TestCase {
    id: test
    name: "Omakeep"
    when: windowShown
    width: 920; height: 700
    Omakeep.App { id: app }
    function folderButton(id) {
        var buttons = findChild(app, "folderButtons");
        for (var i = 0; i < buttons.count; i++) if (buttons.itemAt(i).modelData.id === id) return buttons.itemAt(i);
        return null;
    }
    function test_capture_edit_keyboard_and_reopen() {
        try { exerciseLibrary(); }
        catch (error) { console.log(error.stack); throw error; }
    }
    function exerciseLibrary() {
        console.log("UI check: opening");
        app.open();
        var search = findChild(app, "bookmarkSearch");
        var list = findChild(app, "bookmarkList");
        var form = findChild(app, "bookmarkForm");
        var field = findChild(app, "formField");
        if (Quickshell.env("OMAKEEP_TEST_REOPEN") === "1") {
            tryCompare(list, "count", 1, 5000);
            app.expand(1);
            tryCompare(app, "loadedNoteId", 1, 5000);
            compare(app.loadedNote, "Saved on collapse");
            compare(list.model.get(0).title, "Renamed page");
            console.log("OMAKEEP_RESTART_OK");
            app.close();
            return;
        }
        tryVerify(function() { return search.activeFocus; });
        console.log("UI check: capture");
        app.mutate({ op: "capture", url: "https://example.com", title: "Example page" });
        tryCompare(list, "count", 1, 5000);
        console.log("UI check: keyboard");
        app.focusRow(0);
        var title = findChild(list.currentItem, "bookmarkTitle");
        tryVerify(function() { return title.activeFocus; });
        keyClick(Qt.Key_Right);
        compare(app.expandedId, 1);
        tryCompare(app, "loadedNoteId", 1, 5000);
        console.log("UI check: note loaded");
        verify(title.activeFocus);
        var editor = findChild(list.currentItem, "noteEditor");
        keyClick(Qt.Key_E);
        tryVerify(function() { return editor.activeFocus; });
        keyClick(Qt.Key_Escape);
        keyClick(Qt.Key_E); // A collapsed note loads before its editor takes focus.
        keyClick(Qt.Key_F, Qt.ControlModifier); // Leaving must cancel that pending focus.
        tryCompare(app, "loadedNoteId", 1, 5000);
        verify(search.activeFocus);
        keyClick(Qt.Key_Down);
        tryVerify(function() { return title.activeFocus; });
        keyClick(Qt.Key_E);
        tryVerify(function() { return editor.activeFocus; });
        keyClick("/"); keyClick("?"); keyClick("r"); keyClick("d"); keyClick("e"); keyClick("f");
        compare(app.expandedId, 1);
        compare(editor.text, "/?rdef");
        verify(!form.visible);
        keyClick(Qt.Key_A, Qt.ControlModifier); keyClick(Qt.Key_Backspace);
        "A note worth keeping".split("").forEach(function(character) { keyClick(character); });
        tryVerify(function() { return Object.keys(app.store.drafts).length === 0 && app.store.active === null; }, 5000);
        compare(app.loadedNote, "A note worth keeping");
        keyClick(Qt.Key_F, Qt.ControlModifier);
        verify(search.activeFocus);
        editor.forceActiveFocus();
        // A real validation failure keeps the editor's draft; Retry saves the latest correction.
        editor.text = "é".repeat(40000);
        app.flush();
        tryVerify(function() { return app.store.failed !== null; }, 5000);
        compare(app.store.drafts[1].notes.length, 40000);
        findChild(list.currentItem, "copyLink").triggered();
        compare(Quickshell.clipboardText, "https://example.com", "Copy works while saving is blocked");
        compare(app.store.failed.op, "saveNote");
        app.copyLink("javascript:alert(1)");
        compare(Quickshell.clipboardText, "https://example.com", "Invalid URLs leave the clipboard intact");
        editor.text = "Recovered note";
        app.retry();
        tryVerify(function() { return app.store.active === null && !app.store.drafts[1]; }, 5000);
        compare(app.loadedNote, "Recovered note");
        editor.text = "Saved on collapse";
        keyClick(Qt.Key_Escape);
        compare(app.expandedId, 0);
        tryVerify(function() { return title.activeFocus; });
        tryVerify(function() { return !app.store.drafts[1]; }, 5000);
        keyClick(Qt.Key_E);
        tryVerify(function() { return editor.activeFocus; });
        compare(editor.text, "Saved on collapse");
        compare(editor.cursorPosition, editor.length);
        keyClick(Qt.Key_Escape);
        app.close(); app.open();
        tryVerify(function() { return search.activeFocus; });
        app.expand(1);
        tryCompare(app, "loadedNoteId", 1, 5000);
        compare(app.loadedNote, "Saved on collapse");
        keyClick(Qt.Key_N, Qt.ControlModifier);
        tryVerify(function() { return form.visible; });
        compare(app.formKind, "add");
        keyClick(Qt.Key_Escape);
        tryVerify(function() { return !form.visible; });
        keyClick(Qt.Key_N, Qt.ControlModifier | Qt.ShiftModifier);
        tryVerify(function() { return field.activeFocus; });
        compare(app.formKind, "folder");
        field.text = "Reading"; keyClick(Qt.Key_Return);
        tryCompare(app, "folders", [{ id: 1, name: "Reading" }], 5000);
        console.log("UI check: F folder assignment");
        app.focusRow(0);
        title = findChild(list.currentItem, "bookmarkTitle");
        tryVerify(function() { return title.activeFocus; });
        keyClick(Qt.Key_Left);
        compare(app.expandedId, 0);
        var assignment = findChild(list.currentItem, "bookmarkFolderPicker");
        keyClick(Qt.Key_F);
        tryVerify(function() { return assignment.popup.visible; });
        compare(app.expandedId, 1);
        keyClick(Qt.Key_Down);
        compare(list.model.get(0).folderId, null, "Browsing folders must not move the bookmark");
        keyClick(Qt.Key_Escape);
        tryVerify(function() { return !assignment.popup.visible && title.activeFocus; });
        compare(list.model.get(0).folderId, null, "Escape cancels folder assignment");
        keyClick(Qt.Key_F);
        tryVerify(function() { return assignment.popup.visible; });
        keyClick(Qt.Key_Down); keyClick(Qt.Key_Return);
        tryVerify(function() { return list.model.get(0).folderId === 1 && title.activeFocus; }, 5000);
        compare(app.noteText(1), "Saved on collapse");

        console.log("UI check: folders, rename and confirmation");
        keyClick(Qt.Key_Left); // Collapse first; a second Left reaches folders.
        compare(app.expandedId, 0);
        verify(title.activeFocus);
        keyClick(Qt.Key_Left);
        var all = folderButton(0);
        tryVerify(function() { return all.activeFocus; });
        keyClick(Qt.Key_R); keyClick(Qt.Key_D);
        verify(!form.visible, "All is not a user folder");
        keyClick(Qt.Key_Down);
        compare(app.folderId, 1);
        keyClick(Qt.Key_Right); // Enter before the async folder read completes.
        tryVerify(function() { return list.currentItem && findChild(list.currentItem, "bookmarkTitle").activeFocus; }, 5000);
        compare(list.model.get(0).folderId, 1);
        keyClick(Qt.Key_R);
        tryVerify(function() { return field.activeFocus; });
        compare(app.formKind, "renameBookmark");
        compare(field.selectedText, "Example page");
        field.text = "   "; keyClick(Qt.Key_Return);
        tryVerify(function() { return app.formError !== ""; }, 5000);
        verify(form.visible);
        field.text = "Renamed page"; keyClick(Qt.Key_Return);
        tryVerify(function() { return !form.visible; }, 5000);
        compare(list.model.get(0).title, "Renamed page");
        tryVerify(function() { return findChild(list.currentItem, "bookmarkTitle").activeFocus; });
        keyClick(Qt.Key_D);
        tryVerify(function() { return form.visible; });
        compare(app.formKind, "deleteBookmark");
        keyClick(Qt.Key_Escape);
        tryVerify(function() { return !form.visible; });
        compare(list.count, 1, "Cancel must preserve the bookmark");
        tryVerify(function() { return findChild(list.currentItem, "bookmarkTitle").activeFocus; });
        keyClick(Qt.Key_Left);
        var folder = folderButton(1);
        tryVerify(function() { return folder.activeFocus; });
        keyClick(Qt.Key_R);
        tryVerify(function() { return field.activeFocus; });
        compare(field.selectedText, "Reading");
        field.text = "Research"; keyClick(Qt.Key_Return);
        tryCompare(app, "folders", [{ id: 1, name: "Research" }], 5000);
        tryVerify(function() { return folderButton(1).activeFocus; });
        keyClick(Qt.Key_D);
        tryVerify(function() { return form.visible; });
        compare(app.formKind, "deleteFolder");
        keyClick(Qt.Key_Escape);
        tryVerify(function() { return !form.visible && folderButton(1).activeFocus; });
        compare(app.folders.length, 1);
        keyClick(Qt.Key_D);
        tryVerify(function() { return form.visible; });
        keyClick(Qt.Key_Return);
        tryCompare(app, "folderId", 0, 5000);
        tryCompare(app, "folders", [], 5000);
        tryCompare(list, "count", 1, 5000);
        tryVerify(function() { return folderButton(0).activeFocus; });
        keyClick(Qt.Key_Right);
        tryVerify(function() { return findChild(list.currentItem, "bookmarkTitle").activeFocus; });

        // Confirming D removes both the disposable bookmark and its note.
        app.mutate({ op: "capture", url: "https://delete.test", title: "Disposable" });
        tryCompare(list, "count", 2, 5000);
        app.editNote(2, "Remove this too"); app.flush();
        tryVerify(function() { return !app.store.drafts[2] && app.store.active === null; }, 5000);
        app.focusRow(0);
        tryVerify(function() { return findChild(list.currentItem, "bookmarkTitle").activeFocus; });
        compare(list.model.get(0).id, 2);
        keyClick(Qt.Key_D);
        tryVerify(function() { return form.visible; });
        keyClick(Qt.Key_Return);
        tryCompare(list, "count", 1, 5000);
        compare(list.model.get(0).id, 1);
        tryVerify(function() { return findChild(list.currentItem, "bookmarkTitle").activeFocus; });

        app.mutate({ op: "createFolder", name: "Empty" });
        tryCompare(app, "folders", [{ id: 2, name: "Empty" }], 5000);
        keyClick(Qt.Key_Left); keyClick(Qt.Key_Down); keyClick(Qt.Key_Right);
        tryCompare(list, "count", 0, 5000);
        tryVerify(function() { return list.activeFocus; });
        keyClick(Qt.Key_Left);
        tryVerify(function() { return folderButton(2).activeFocus; });
        keyClick(Qt.Key_Up); keyClick(Qt.Key_Right);
        tryCompare(list, "count", 1, 5000);
        app.expand(1);
        tryCompare(app, "loadedNoteId", 1, 5000);
        compare(app.loadedNote, "Saved on collapse");
        var nativeWindow = findChild(app, "omakeepWindow");
        wait(100);
        grabImage(nativeWindow.contentItem).save("/tmp/omakeep-ui-wide.png");
        nativeWindow.contentItem.Window.window.width = 620;
        wait(100);
        verify(nativeWindow.width <= 650, "Narrow window must actually resize");
        app.focusRow(0);
        tryVerify(function() { return findChild(list.currentItem, "bookmarkTitle").activeFocus; });
        keyClick(Qt.Key_Left); keyClick(Qt.Key_Left);
        var picker = findChild(app, "folderViewPicker");
        tryVerify(function() { return picker.activeFocus; });
        keyClick(Qt.Key_Down); keyClick(Qt.Key_Right);
        tryCompare(list, "count", 0, 5000);
        tryVerify(function() { return list.activeFocus; });
        keyClick(Qt.Key_Left);
        tryVerify(function() { return picker.activeFocus; });
        keyClick(Qt.Key_D);
        tryVerify(function() { return form.visible; });
        keyClick(Qt.Key_Return);
        tryCompare(app, "folders", [], 5000);
        tryVerify(function() { return picker.activeFocus; });
        keyClick(Qt.Key_Right);
        tryCompare(list, "count", 1, 5000);
        app.expand(1);
        tryCompare(app, "loadedNoteId", 1, 5000);
        grabImage(nativeWindow.contentItem).save("/tmp/omakeep-ui-narrow.png");
        Color.background = "#f3efe3"; Color.foreground = "#314e52"; Color.accent = "#3f8f8a";
        Color.shellValues = ({}); Style.styleOverrides = ({});
        wait(100);
        grabImage(nativeWindow.contentItem).save("/tmp/omakeep-ui-light.png");
        app.close();
        console.log("OMAKEEP_UI_OK");
    }
    function cleanupTestCase() { console.log("UI failures: " + qtest_results.failCount + "; notice: " + app.notice); }
}
