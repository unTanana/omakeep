pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import qs.Commons as Commons

// Wrapped plain text with the search match marked. The match is a selection,
// the one mark that follows the text across lines. It never takes mouse or focus.
TextEdit {
    id: root
    property string query: ""
    property string size: "body"
    readonly property var fonts: Style.font
    enabled: false
    readOnly: true
    persistentSelection: true
    textFormat: TextEdit.PlainText
    wrapMode: TextEdit.WrapAtWordBoundaryOrAnywhere
    color: Commons.Color.foreground
    selectionColor: Style.selectionFill
    selectedTextColor: color
    font.family: fonts.family
    font.pixelSize: fonts[size]
    function mark() {
        var at = query ? text.toLowerCase().indexOf(query.toLowerCase()) : -1;
        if (at >= 0) select(at, at + query.length); else deselect();
    }
    onTextChanged: mark()
    onQueryChanged: mark()
    Component.onCompleted: mark()
}
