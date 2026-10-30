pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root
    property string pluginDir: ""
    property string mode: "--qml"
    property string path: "/usr/bin:/bin"
    // Not process.running, which stays false until the run has really started. A second start in that gap makes the Process run twice.
    property bool busy: false
    property var request: null
    property var parts: []
    property int size: 0
    property int errorLength: 0
    property bool overflow: false
    readonly property var processEnvironment: ({ HOME: Quickshell.env("HOME"), XDG_DATA_HOME: Quickshell.env("XDG_DATA_HOME"),
        XDG_RUNTIME_DIR: Quickshell.env("XDG_RUNTIME_DIR"), WAYLAND_DISPLAY: Quickshell.env("WAYLAND_DISPLAY"),
        DBUS_SESSION_BUS_ADDRESS: Quickshell.env("DBUS_SESSION_BUS_ADDRESS"), PATH: root.path, LANG: "C.UTF-8" })
    signal completed()

    function start(value) {
        if (busy) return false;
        request = value;
        parts = []; size = 0; errorLength = 0; overflow = false;
        busy = true;
        process.running = true;
        return true;
    }
    function cancel() { if (busy) { overflow = true; process.signal(15); kill.start(); } }
    function finish(ok) {
        kill.stop();
        if (!ok) parts = [];
        process.stdinEnabled = true;
        busy = false;
        completed();
    }
    // Call this from the completed handler. An older search never gets here, which is the point. As a signal
    // argument the reply would pass through QVariant, after which Array.isArray() is false on its lists.
    function parsed() {
        var reply = { ok: false, error: "Could not reach the library. Check setup and retry." }, value;
        try {
            value = JSON.parse(parts.join(""));
            if (value && typeof value.ok === "boolean" && (value.ok
                ? value.result && typeof value.result === "object" && !Array.isArray(value.result)
                : typeof value.error === "string" && value.error.length <= 256)) reply = value;
        } catch (_) {}
        return reply;
    }
    Process {
        id: process
        // One static binary from this folder, with its own time limit.
        command: [root.pluginDir + "/bin/omakeep-helper", root.mode]
        clearEnvironment: true
        environment: root.processEnvironment
        stdinEnabled: true
        onStarted: { write(JSON.stringify(root.request)); stdinEnabled = false; }
        stdout: SplitParser {
            splitMarker: ""
            onRead: function(chunk) {
                root.size += chunk.length;
                if (root.size > 262144) root.cancel();
                else root.parts.push(chunk);
            }
        }
        stderr: SplitParser {
            splitMarker: ""
            onRead: function(chunk) { root.errorLength += chunk.length; if (root.errorLength > 4096) root.cancel(); }
        }
        // Quickshell's installed qmltypes omit QProcess::ExitStatus; exercised by the real runtime check.
        // qmllint disable signal-handler-parameters
        onExited: function(code) { root.finish(code === 0 && !root.overflow); }
        // qmllint enable signal-handler-parameters
        // A helper that can't start never exits.
        onRunningChanged: if (!running && root.busy) root.finish(false)
    }
    Timer { id: kill; interval: 1100; onTriggered: if (process.running) process.signal(9) }
    Component.onDestruction: if (process.running) process.signal(15)
}
