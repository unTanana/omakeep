pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root
    property string pluginDir: ""
    property bool busy: process.running
    property var request: null
    property string output: ""
    property int errorLength: 0
    property bool overflow: false
    readonly property var processEnvironment: ({ HOME: Quickshell.env("HOME"), XDG_DATA_HOME: Quickshell.env("XDG_DATA_HOME"),
        XDG_RUNTIME_DIR: Quickshell.env("XDG_RUNTIME_DIR"), WAYLAND_DISPLAY: Quickshell.env("WAYLAND_DISPLAY"),
        DBUS_SESSION_BUS_ADDRESS: Quickshell.env("DBUS_SESSION_BUS_ADDRESS"), PATH: "/usr/bin:/bin", LANG: "C.UTF-8" })
    signal completed(var request, var reply)

    function start(value) {
        if (busy) return false;
        request = value;
        output = ""; errorLength = 0; overflow = false;
        process.running = true;
        return true;
    }
    function cancel() { if (busy) { overflow = true; process.signal(15); kill.start(); } }
    Process {
        id: process
        // setup creates this fixed launcher with the supported Node path and an eight-second timeout.
        command: [root.pluginDir + "/run-helper", "--qml"]
        clearEnvironment: true
        environment: root.processEnvironment
        stdinEnabled: true
        onStarted: { write(JSON.stringify(root.request)); stdinEnabled = false; }
        stdout: SplitParser {
            splitMarker: ""
            onRead: function(chunk) {
                if (root.output.length + chunk.length > 262144) root.cancel();
                else if (!root.overflow) root.output += chunk;
            }
        }
        stderr: SplitParser {
            splitMarker: ""
            onRead: function(chunk) { root.errorLength += chunk.length; if (root.errorLength > 4096) root.cancel(); }
        }
        // Quickshell's installed qmltypes omit QProcess::ExitStatus; exercised by the real runtime check.
        // qmllint disable signal-handler-parameters
        onExited: function(code) {
            kill.stop();
            var reply = { ok: false, error: "Could not reach the library. Check setup and retry." };
            if (code === 0 && !root.overflow) {
                try {
                    var parsed = JSON.parse(root.output);
                    if (parsed && typeof parsed.ok === "boolean" && (parsed.ok
                        ? parsed.result && typeof parsed.result === "object" && !Array.isArray(parsed.result)
                        : typeof parsed.error === "string" && parsed.error.length <= 256)) reply = parsed;
                } catch (_) {}
            }
            root.output = "";
            stdinEnabled = true;
            root.completed(root.request, reply);
        }
        // qmllint enable signal-handler-parameters
    }
    Timer { id: kill; interval: 1100; onTriggered: if (process.running) process.signal(9) }
    Component.onDestruction: if (process.running) process.signal(15)
}
