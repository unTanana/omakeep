pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls as Controls
import qs.Commons

Controls.ComboBox {
    id: root
    property var entries: []
    property int selectedId: 0
    signal chosen(int id)
    model: entries
    textRole: "name"
    valueRole: "id"
    currentIndex: Math.max(0, entries.findIndex(function(f) { return f.id === root.selectedId; }))
    onActivated: root.chosen(entries[currentIndex].id)
    font.family: Style.fontFamily
    font.pixelSize: Style.fontToken("body", Style.fontPx(1))
    palette.window: Color.background
    palette.base: Color.background
    palette.text: Color.foreground
    palette.button: Color.background
    palette.buttonText: Color.foreground
    palette.highlight: Color.accent
    contentItem: Text {
        text: root.displayText; textFormat: Text.PlainText
        color: Color.foreground; font: root.font
        verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight
        leftPadding: 10; rightPadding: 26
    }
    background: Rectangle { color: Color.background; border.color: root.activeFocus ? Color.accent : Style.normalBorderColor; border.width: 1 }
    delegate: Controls.ItemDelegate {
        id: option
        required property var modelData
        width: root.width
        contentItem: Text { text: option.modelData.name; textFormat: Text.PlainText; color: Color.foreground; font: root.font; elide: Text.ElideRight }
        background: Rectangle { color: option.highlighted ? Style.selectedAccentFill : Color.background }
        highlighted: root.highlightedIndex === option.index
        required property int index
    }
}
