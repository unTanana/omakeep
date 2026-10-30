pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui as Ui

// Ui.TextField on the panel background, with a red border when its value is wrong.
Ui.TextField {
    id: root
    property bool bad: false
    readonly property var alert: Commons.Color.polkit
    readonly property color line: Border.color(Border.controlSpec("normal", Commons.Color.foreground, Commons.Color.accent))
    implicitHeight: Style.space(30)
    verticalPadding: 0
    background: Ui.BorderSurface {
        color: Commons.Color.background
        radius: Style.cornerRadius
        borderSpec: Border.flat(root.bad ? root.alert.textError : root.activeFocus || root.hovered ? Commons.Color.accent : root.line, Style.normalBorderWidth)
    }
}
