pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui as Ui

// Ui.Button at the panel's sizes. It draws its own label because the kit's has
// a fixed gap and cannot go bold, elide or carry a second icon. Without a label
// it is square. A solid one is the single main action on a surface.
Ui.Button {
    id: root
    property string label: ""
    property string icon: ""
    property string trailing: ""
    property string size: small ? "caption" : "bodySmall"
    property real labelLimit: 0
    property bool small: false
    property bool tight: false
    property bool danger: false
    property bool accented: false
    property bool solid: false
    property bool strong: false
    property color ink: Commons.Color.foreground
    readonly property bool square: label === ""
    readonly property var alert: Commons.Color.polkit
    readonly property color tone: solid ? (danger ? "#ffffff" : Commons.Color.background) : danger ? alert.textError : accented ? Commons.Color.accent : hot || activeFocus ? hotColor() : ink
    focusable: true
    foreground: tone
    accent: danger ? alert.textError : Commons.Color.accent
    iconSize: small || tight ? Style.space(13) : Style.space(15)
    horizontalPadding: small || tight ? Style.space(7) : Style.space(8)
    verticalPadding: 0
    implicitWidth: square ? implicitHeight : content.implicitWidth + horizontalPadding * 2 + 2
    implicitHeight: small ? Style.space(23) : Style.space(28)
    borderSpec: accented && !hot && !activeFocus ? Border.flat(Commons.Color.accent, Style.normalBorderWidth) : _borderSpec
    Accessible.name: label || tooltipText
    function hotColor() { return Style.hoverStateColor(Commons.Color.foreground, Commons.Color.accent, Commons.Color.urgent); }
    Rectangle {
        visible: root.solid
        anchors.fill: parent
        color: !root.hot ? (root.danger ? Commons.Color.urgent : Commons.Color.accent) : root.danger ? root.alert.textError : root.hotColor()
        border.color: root.activeFocus && !root.hot ? root.hotColor() : "transparent"
        border.width: 1
    }
    Row {
        id: content
        x: root.leftAlign ? root.horizontalPadding : Math.round((root.width - width) / 2)
        anchors.verticalCenter: parent.verticalCenter
        spacing: root.tight ? Style.space(3) : root.small ? Style.space(4) : Style.space(5)
        Glyph {
            visible: root.icon !== ""
            anchors.verticalCenter: parent.verticalCenter
            text: root.icon
            color: root.tone
            font.pixelSize: root.iconSize
        }
        Label {
            visible: !root.square
            anchors.verticalCenter: parent.verticalCenter
            width: root.labelLimit > 0 ? Math.min(implicitWidth, root.labelLimit) : implicitWidth
            text: root.label
            color: root.tone
            size: root.size
            font.bold: root.solid || root.strong
        }
        Glyph {
            visible: root.trailing !== ""
            anchors.verticalCenter: parent.verticalCenter
            text: root.trailing
            color: root.tone
            font.pixelSize: Style.space(13)
        }
    }
}
