pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import qs.Commons as Commons

Text {
    textFormat: Text.PlainText
    color: Commons.Color.foreground
    font.family: Style.fontFamily
    font.pixelSize: Style.space(15)
    width: Math.round(font.pixelSize * 1.25)
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
}
