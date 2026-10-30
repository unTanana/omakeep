pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons

// One line of plain text with the search match marked behind it. A match past
// the cut-off moves the text along, so the match stays in view.
Label {
    id: root
    property string source: ""
    property string query: ""
    readonly property int match: query ? source.toLowerCase().indexOf(query.toLowerCase()) : -1
    property int from: 0
    property real matchedWidth: 0
    // The width of all the text, for a layout that sizes this to fit. With a match the shown text can be cut, so it is measured.
    readonly property real sourceWidth: match >= 0 ? matchedWidth : implicitWidth
    text: from > 0 ? "…" + source.slice(from) : source
    // Measuring text is the slow part, so only a line that holds a match pays for it.
    Loader {
        active: root.match >= 0
        onActiveChanged: if (!active) root.from = 0
        sourceComponent: Rectangle {
            id: mark
            readonly property int shownAt: root.from > 0 ? root.match - root.from + 1 : root.match
            TextMetrics { id: all; font: root.font; text: root.source }
            Binding { target: root; property: "matchedWidth"; value: Math.ceil(all.advanceWidth) }
            TextMetrics { id: whole; font: root.font; text: root.source.slice(0, root.match + root.query.length) }
            TextMetrics { id: before; font: root.font; text: root.text.slice(0, mark.shownAt) }
            TextMetrics { id: marked; font: root.font; text: root.text.substr(mark.shownAt, root.query.length) }
            Binding { target: root; property: "from"; value: whole.advanceWidth > root.width ? Math.max(0, root.match - 14) : 0 }
            x: before.advanceWidth
            y: 0
            z: -1
            width: Math.min(marked.advanceWidth, root.width - x)
            height: root.height
            color: Style.selectionFill
        }
    }
}
