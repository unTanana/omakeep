pragma ComponentBehavior: Bound
import QtQuick
import qs.Ui as Ui

Ui.BarWidget {
    id: root
    readonly property var barContext: bar
    moduleName: "omakeep"
    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight
    Ui.BarIconButton {
        id: button
        anchors.fill: parent
        bar: root.bar
        text: "󰃀"
        tooltipText: "Omakeep — bookmarks and notes"
        onPressed: if (root.barContext && root.barContext.shell) root.barContext.shell.toggle("omakeep", "{}")
    }
}
