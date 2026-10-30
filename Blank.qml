pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.Commons
import "Icons.js" as Icons

// What the list shows instead of rows.
Item {
    id: root
    required property var app
    readonly property string query: app.appliedQuery
    readonly property string kind: app.libraryError ? "library" : query ? "search" : app.folderId ? "folder" : "first"
    readonly property string headline: kind === "library" ? "Can't open your library" : kind === "search" ? "Nothing matches “" + query + "”"
        : kind === "folder" ? app.viewName + " is empty" : "No bookmarks yet"
    readonly property string body: kind === "library" ? "Your bookmarks are safe on disk. Omakeep just couldn't read them this time."
        : kind === "search" ? "Searched titles, links and notes in " + app.viewName + "."
        : kind !== "folder" ? "In Chrome, click the Omakeep button or press Alt+Shift+K to save the page you're on."
        : app.narrow ? "Use Move on any bookmark to put it here, or add a new one." : "Drag a bookmark onto this folder, or add a new one here."
    ColumnLayout {
        anchors.centerIn: parent
        width: Math.min(parent.width - Style.space(40), Style.space(350))
        spacing: Style.space(7)
        Glyph {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredHeight: font.pixelSize
            Layout.bottomMargin: Style.space(3)
            text: root.kind === "library" ? Icons.alert : root.kind === "search" ? Icons.noResult : root.kind === "folder" ? Icons.folderOpen : Icons.bookmark
            color: root.kind === "library" ? root.app.errorInk : root.app.dim
            font.pixelSize: Style.space(32)
        }
        Label {
            Layout.fillWidth: true
            text: root.headline
            color: root.app.hotInk
            size: "subtitle"; font.bold: true
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap; elide: Text.ElideNone
        }
        Label {
            Layout.fillWidth: true
            text: root.body
            color: root.app.dim
            size: "bodySmall"
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap; elide: Text.ElideNone
        }
        Row {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: Style.space(7)
            spacing: Style.space(7)
            KeepButton {
                solid: true
                objectName: "blankRetry"
                visible: root.kind === "library"
                icon: Icons.retry; label: "Retry"
                onClicked: root.app.retryLibrary()
            }
            KeepButton {
                objectName: "blankSearchAll"
                visible: root.kind === "search" && root.app.folderId !== 0
                accented: true
                label: "Search all bookmarks"
                onClicked: root.app.chooseFolder(0)
            }
            KeepButton {
                objectName: "blankClear"
                visible: root.kind === "search"
                bordered: true
                label: "Clear search"
                onClicked: root.app.clearSearch()
            }
            KeepButton {
                objectName: "blankAdd"
                visible: root.kind === "folder" || root.kind === "first"
                accented: true
                icon: Icons.plus; label: "Add bookmark"
                onClicked: root.app.openAdd()
            }
            KeepButton {
                objectName: "blankAll"
                visible: root.kind === "folder"
                bordered: true
                label: "Show all bookmarks"
                onClicked: root.app.chooseFolder(0)
            }
        }
    }
}
