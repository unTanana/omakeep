import QtQuick
import "ScrollPhysics.js" as Scroll

// Touchpad and wheel scrolling for one Flickable, done the way Flea does it (ui/FastScrollHandler.qml,
// MIT, ported and trimmed to one axis; the numbers and Flea's license live in ScrollPhysics.js).
// Qt Quick on Linux moves a list one pixel per touchpad pixel and never glides, and Omarchy scales
// touchpads to 0.4, so Qt lists barely moved on a MacBook. Here:
//   - a touchpad stroke moves 5x the finger travel (twice GTK4's factor, the user's choice);
//   - fingers that lift while moving glide on, on Apple's decay curve, frame by frame;
//   - past either end the view stretches and springs back;
//   - a new stroke, a wheel click, a press or any other move of the view stops a glide;
//   - a wheel click moves `notchPx`: half Flea's step (wheel lines x 48 px, 144 by default), at
//     most three eighths of the view so a short list never jumps past what was on screen; 0 leaves
//     wheel clicks to the Flickable, whose own step is about 70 px.
// It is a MouseArea laid over the Flickable, not a WheelHandler: WheelHandler drops touchpad events
// by default, and every event without movement, and Qt on Wayland starts and ends each stroke with
// one, so the Flickable got a start without its end and stayed "moving". Presses only stop a glide
// and go on to the items below; it takes no hover, so clicks, drags and tooltips work as before.
// A scroll area inside the Flickable (a note editor in a list row) keeps the strokes that start over it.
MouseArea {
    id: root

    required property var flickable
    // Mouse wheel distance per click (120 angle units); 0 leaves clicks to the Flickable itself.
    property real notchPx: Math.min(Application.styleHints.wheelScrollLines * Scroll.NOTCH_PX_PER_LINE,
                                    Math.max(1, (flickable ? flickable.height : 0) * Scroll.NOTCH_MAX_VIEW))
    // True while a stroke, glide or spring-back runs, and briefly after a wheel click.
    readonly property bool active: settle.running || tailRunning || returnRunning

    property bool tailRunning: false
    property bool returnRunning: false
    property var samples: []
    property real velocity: 0 // px/ms of contentY travel, gained
    property real over: 0 // raw travel banked past an end: below the top < 0 < past the bottom
    property real returnFrom: 0
    property real returnTo: 0
    property real returnElapsed: 0
    property bool framing: false // the glide or the spring-back is writing contentY
    property bool yielding: false
    property bool stroking: false // between a stroke's ScrollBegin and its ScrollEnd

    parent: flickable
    anchors.fill: parent
    z: 1000
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
    onPressed: mouse => { root.stopTail(); mouse.accepted = false }

    Timer { id: settle; interval: 400 }

    function limits() { return Scroll.limitsY(root.flickable) }

    function stopTail() {
        root.tailRunning = false
        root.velocity = 0
        root.samples = []
    }

    // Ends a spring-back or a held stretch with the view at its nearest end.
    function stopReturn() {
        if (!root.returnRunning && root.over === 0)
            return
        root.returnRunning = false
        root.over = 0
        const l = root.limits()
        root.flickable.contentY = Math.max(l.min, Math.min(l.max, root.flickable.contentY))
    }

    function overscrolled() {
        const l = root.limits()
        const y = root.flickable.contentY
        return root.over !== 0 || y < l.min - 0.01 || y > l.max + 0.01
    }

    // Banks travel past an end and returns where the stretched view shows.
    function bank(l, want) {
        const d = Math.max(1, root.flickable.height)
        const below = want < l.min
        const beyond = below ? l.min - want : want - l.max
        const prev = Math.abs(root.over)
        const total = prev === 0 ? beyond : prev + Math.max(0, beyond - Scroll.overResist(prev, d))
        root.over = below ? -total : total
        const shown = Scroll.overResist(total, d)
        return below ? l.min - shown : l.max + shown
    }

    // One stroke event's travel; past an end it resists, and travel back un-banks first.
    function touch(delta) {
        const f = root.flickable
        const l = root.limits()
        if (root.over !== 0 && f.contentY >= l.min - 0.01 && f.contentY <= l.max + 0.01)
            root.over = 0
        if (root.over === 0) {
            const want = f.contentY - delta
            f.contentY = want >= l.min && want <= l.max ? want : root.bank(l, want)
            return
        }
        const below = root.over < 0
        const left = Math.abs(root.over) + (below ? delta : -delta)
        if (left <= 0) {
            root.over = 0
            f.contentY = below ? l.min - left : l.max + left
            return
        }
        root.over = below ? -left : left
        const shown = Scroll.overResist(left, Math.max(1, f.height))
        f.contentY = below ? l.min - shown : l.max + shown
    }

    function startTail() {
        if (root.over !== 0)
            return
        const v = Scroll.liftVelocity(root.samples, Scroll.now())
        root.samples = []
        root.velocity = v
        root.tailRunning = v !== 0
    }

    function advanceTail(dt) {
        const f = root.flickable
        const step = Scroll.tailStep(root.velocity, dt)
        root.velocity = step.v
        if (step.dx !== 0) {
            const l = root.limits()
            const before = f.contentY
            const want = before - step.dx
            if (root.over === 0 && want >= l.min && want <= l.max) {
                f.contentY = want
                if (f.contentY === before)
                    root.velocity = 0
            } else {
                f.contentY = root.bank(l, want)
                root.velocity *= Math.pow(Scroll.OVER_DECAY, dt)
            }
        }
        if (Math.abs(root.velocity) <= Scroll.STOP_V_PX_PER_MS) {
            root.tailRunning = false
            root.velocity = 0
            if (root.overscrolled())
                root.startReturn()
        }
    }

    function startReturn() {
        const l = root.limits()
        const y = root.flickable.contentY
        root.over = 0
        root.returnFrom = y
        root.returnTo = Math.max(l.min, Math.min(l.max, y))
        root.returnElapsed = 0
        root.returnRunning = Math.abs(root.returnTo - y) > 0.01
    }

    function advanceReturn(dt) {
        root.returnElapsed += dt
        root.flickable.contentY = Scroll.returnAt(root.returnFrom, root.returnTo, root.returnElapsed, Scroll.RETURN_MS)
        if (root.returnElapsed >= Scroll.RETURN_MS)
            root.returnRunning = false
    }

    // The innermost other scroll area under the point that has something to scroll, if any.
    // childAt() skips hidden items.
    function innerScroller(x, y) {
        let item = root.flickable.contentItem
        let p = root.mapToItem(item, x, y)
        while (item) {
            const child = item.childAt(p.x, p.y)
            if (!child)
                return null
            if (child instanceof Flickable && Scroll.scrollsY(child))
                return child
            p = item.mapToItem(child, p.x, p.y)
            item = child
        }
        return null
    }

    function touchpad(wheel) {
        const f = root.flickable
        const phase = wheel.phase
        const t = Scroll.now()
        // Qt on Wayland delivers each stroke's ScrollEnd twice (seen with real strokes through
        // libinput and Hyprland). The repeat must not end the glide the first one started.
        if (phase === Qt.ScrollEnd && !root.stroking) {
            wheel.accepted = true
            return
        }
        settle.restart()
        if (phase === Qt.ScrollBegin) {
            root.stroking = true
            root.stopTail()
            root.stopReturn()
            root.samples = [{ t: t, y: 0 }] // anchors the lift's time span
        } else if (phase !== Qt.ScrollEnd && root.tailRunning) {
            root.stopTail()
        } else if (root.returnRunning) {
            root.stopReturn()
        }
        const down = Scroll.scrollsY(f) || root.over !== 0 ? wheel.pixelDelta.y * Scroll.TOUCH_GAIN : 0
        if (down !== 0) {
            Scroll.pushSample(root.samples, t, down)
            f.cancelFlick()
            root.touch(down)
        }
        if (phase === Qt.ScrollEnd) {
            root.stroking = false
            if (root.overscrolled())
                root.startReturn()
            else
                root.startTail()
        }
        wheel.accepted = true
    }

    function mouseWheel(wheel) {
        const f = root.flickable
        // Qt 6.12 fills pixelDelta beside angleDelta on a wheel click, so a click moves by its angle;
        // pixels count only on an event without one.
        const travel = wheel.angleDelta.y !== 0 ? wheel.angleDelta.y / Scroll.NOTCH_UNITS * root.notchPx
                                                : wheel.pixelDelta.y
        root.stopTail()
        root.stopReturn()
        if (travel === 0 || !Scroll.scrollsY(f)) {
            wheel.accepted = false // the Flickable's own wheel scrolling, or whatever holds it
            return
        }
        settle.restart()
        f.cancelFlick()
        const l = root.limits()
        const want = f.contentY - travel
        // A ListView only estimates its length past the loaded rows; it finds its real end itself.
        if (want >= l.max && f.positionViewAtEnd)
            f.positionViewAtEnd()
        else
            f.contentY = Math.max(l.min, Math.min(l.max, want))
        wheel.accepted = true
    }

    onWheel: wheel => root.handle(wheel)

    // Every wheel event comes here; the tests call it with plain objects.
    function handle(wheel) {
        if (wheel.phase === Qt.ScrollMomentum) { // macOS sends its own glide
            wheel.accepted = false
            return
        }
        if (wheel.phase !== Qt.NoScrollPhase) { // a touchpad stroke; a wheel click has no phase
            // A stroke stays with whichever area it started over.
            if (wheel.phase === Qt.ScrollBegin) {
                root.yielding = root.innerScroller(wheel.x, wheel.y) !== null
                if (root.yielding) {
                    root.stopTail()
                    root.stopReturn()
                }
            }
            if (root.yielding) {
                if (wheel.phase === Qt.ScrollEnd)
                    root.yielding = false
                wheel.accepted = false
                return
            }
            root.touchpad(wheel)
            return
        }
        if (root.innerScroller(wheel.x, wheel.y) !== null) {
            wheel.accepted = false
            return
        }
        root.mouseWheel(wheel)
    }

    Connections {
        target: root.flickable
        enabled: root.active
        // Any move of the view the glide or spring-back did not make (keys, a jump to a row, a drag)
        // ends it. Writes outside a frame come after stopTail or stopReturn, so they never get here.
        function onContentYChanged() {
            if (root.framing || !(root.tailRunning || root.returnRunning))
                return
            root.stopTail()
            root.returnRunning = false
            root.over = 0
        }
        function onMovementStarted() {
            root.stopTail()
            root.stopReturn()
        }
    }

    FrameAnimation {
        running: root.tailRunning || root.returnRunning
        onTriggered: {
            root.framing = true
            if (root.tailRunning)
                root.advanceTail(frameTime * 1000)
            else
                root.advanceReturn(frameTime * 1000)
            root.framing = false
        }
    }
}
