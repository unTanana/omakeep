pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import qs.Commons as Commons

// Every word in the panel is plain text, so a title can never turn into markup.
Text {
    // One of the shell's font sizes: caption, bodySmall, body, subtitle, title or heading.
    property string size: "body"
    textFormat: Text.PlainText
    color: Commons.Color.foreground
    font.family: Style.font.family // qmllint disable missing-property
    font.pixelSize: Style.font[size]
    elide: Text.ElideRight
    verticalAlignment: Text.AlignVCenter
}
