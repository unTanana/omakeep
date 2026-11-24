.pragma library

// The numbers and arithmetic behind TouchpadScroll.qml. Ported from Flea (github.com/thisisgm/flea,
// ui/js/Scroll.js), vertical axis only, speeds changed at the user's request (2026-11-24). Flea's license:
//
// MIT License
//
// Copyright (c) 2026 GM
//
// Permission is hereby granted, free of charge, to any person obtaining a copy of this software and
// associated documentation files (the "Software"), to deal in the Software without restriction, including
// without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the
// following conditions:
//
// The above copyright notice and this permission notice shall be included in all copies or substantial
// portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT
// LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO
// EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
// IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE
// USE OR OTHER DEALINGS IN THE SOFTWARE.

// A wheel click is 120 units of angleDelta, Qt's own convention.
var NOTCH_UNITS = 120
// Wheel step: half of Flea's 96 px a line, which the user asked for on the PC's mouse (2026-11-24),
// so three lines make 144 px a click (Qt's own is about 70).
var NOTCH_PX_PER_LINE = 48
// A click never moves more than this share of the view, so a short list keeps rows in sight.
var NOTCH_MAX_VIEW = 0.375
// Touchpad pixels move 5x: twice Flea's 2.5 (GTK4's factor), which the user asked for on the MacBook (2026-11-24).
var TOUCH_GAIN = 5
// Apple's glide: velocity decays by 0.998 per millisecond, about half a second of lift speed.
var MOMENTUM_DECAY = 0.998
// Lift speed is measured over the stroke's last 100 ms by arrival time (QML has no event timestamp).
var VELOCITY_WINDOW_MS = 100
// Two events in one millisecond take this floor, so they cannot fling.
var MIN_SPAN_MS = 16
// Samples kept past the window, so the span starts at the event before the first one inside it.
var SPAN_ANCHOR_MS = 50
// The fastest lift speed, twice Flea's 6 px/ms like the gain, so a fast fling also glides twice as far (about 6000 px).
var MAX_V_PX_PER_MS = 12
// Below half a pixel per 60 Hz frame the crawl is no longer visible.
var STOP_V_PX_PER_MS = 0.03
// Apple's rubber band: shown overscroll stays under the viewport length.
var RESIST_K = 0.55
// Past an end a glide brakes hard, so the overshoot peaks within a few frames.
var OVER_DECAY = 0.98
// The way back from an overscroll, Omarchy's short animation time.
var RETURN_MS = 180

// Tests set this to drive time by hand; -1 reads the wall clock.
var testNowMs = -1
function now() {
    return testNowMs >= 0 ? testNowMs : Date.now()
}

// Keeps samples {t, y} (y in gained pixels) to the velocity window plus its anchor.
function pushSample(samples, t, dy) {
    samples.push({ t: t, y: dy })
    while (samples[0].t <= t - VELOCITY_WINDOW_MS - SPAN_ANCHOR_MS)
        samples.shift()
}

// Velocity in px/ms over the last 100 ms before endTime; 0 when the fingers had stopped.
function liftVelocity(samples, endTime) {
    var ys = 0, anchor = -1, first = -1, last = -1
    for (var i = 0; i < samples.length; i++) {
        var s = samples[i]
        if (s.t <= endTime - VELOCITY_WINDOW_MS)
            anchor = s.t
        else if (s.t <= endTime) {
            ys += s.y
            if (first < 0)
                first = s.t
            last = s.t
        }
    }
    if (first < 0)
        return 0
    var v = ys / Math.max(MIN_SPAN_MS, last - (anchor < 0 ? first : anchor))
    v = Math.max(-MAX_V_PX_PER_MS, Math.min(MAX_V_PX_PER_MS, v))
    return Math.abs(v) <= STOP_V_PX_PER_MS ? 0 : v
}

// One frame of the glide, the exact integral, so summed frames equal the closed form.
function tailStep(v, dtMs) {
    if (v === 0 || dtMs <= 0)
        return { dx: 0, v: v }
    var grown = Math.pow(MOMENTUM_DECAY, dtMs)
    return { dx: v * (grown - 1) / Math.log(MOMENTUM_DECAY), v: v * grown }
}

// Shown overscroll for raw travel x >= 0 past an end over viewport length d > 0: 0 at 0, rising, under d.
function overResist(x, d) {
    return (1 - 1 / (x * RESIST_K / d + 1)) * d
}

// The contentY range of a Flickable, margins included; short content pins to the top.
// contentHeight is -1 on a Flickable that never set it.
function limitsY(f) {
    var min = f.originY - f.topMargin
    return { min: min, max: Math.max(min, f.originY + Math.max(0, f.contentHeight) - f.height + f.bottomMargin) }
}

function scrollsY(f) {
    var l = limitsY(f)
    return l.max - l.min > 0.5
}

// Ease-out cubic from `from` to `to`; at or past dur it lands on `to`.
function returnAt(from, to, elapsed, dur) {
    var t = Math.min(1, elapsed / dur)
    return from + (to - from) * (1 - Math.pow(1 - t, 3))
}
