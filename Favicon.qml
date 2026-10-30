pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons

// A saved icon, or the site's first letter when there is none to show.
Rectangle {
    id: root
    property string icon: ""
    property string letter: ""
    property color line: "transparent"
    readonly property bool shown: picture.status === Image.Ready
    implicitWidth: Style.space(18)
    implicitHeight: Style.space(18)
    color: shown ? "transparent" : Style.hoverFill
    border.color: shown ? "transparent" : line
    border.width: 1
    Label {
        anchors.centerIn: parent
        visible: !root.shown
        text: root.letter
        size: "caption"; font.bold: true
    }
    Image {
        id: picture
        anchors.fill: parent
        source: root.icon ? "data:image/png;base64," + root.icon : ""
        sourceSize: Qt.size(44, 44)
        fillMode: Image.PreserveAspectFit
        asynchronous: true
    }
}
