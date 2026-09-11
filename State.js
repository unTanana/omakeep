// Plain JavaScript shared with the runnable state checks; no UI objects own drafts.
function create() { return { drafts: {}, deleting: {}, queue: [], active: null, failed: null }; }
function edit(state, id, notes) {
    if (!state.drafts[id] && Object.keys(state.drafts).length >= 100) return false;
    state.drafts[id] = { notes: notes };
    return true;
}
function enqueue(state, job) {
    if (job.op === "deleteBookmark") {
        state.deleting[job.id] = true;
        state.queue = state.queue.filter(function (old) { return old.id !== job.id || (old.op !== "saveNote" && old.op !== "move"); });
        if (state.failed && state.failed.id === job.id) state.failed = null;
    }
    if (job.op === "saveNote" || job.op === "move") {
        state.queue = state.queue.filter(function (old) { return old.op !== job.op || old.id !== job.id; });
    }
    state.queue.push(job);
}
function flush(state) {
    Object.keys(state.drafts).forEach(function (key) {
        var draft = state.drafts[key];
        if (state.deleting[key]) return;
        if (state.active && state.active.op === "saveNote" && state.active.id === Number(key) && state.active.notes === draft.notes) {
            state.queue = state.queue.filter(function(job) { return job.op !== "saveNote" || job.id !== Number(key); });
            return;
        }
        enqueue(state, { op: "saveNote", id: Number(key), notes: draft.notes });
    });
}
function next(state) {
    if (state.active || state.failed) return null;
    state.active = state.queue.shift() || null;
    return state.active;
}
function finish(state, ok) {
    var job = state.active;
    state.active = null;
    if (!ok) { if (!(job.op === "saveNote" && state.deleting[job.id])) state.failed = job; return job; }
    if (job.op === "deleteBookmark") { delete state.drafts[job.id]; delete state.deleting[job.id]; }
    if (job.op === "saveNote" && state.drafts[job.id] && state.drafts[job.id].notes === job.notes)
        delete state.drafts[job.id];
    return job;
}
function retry(state) {
    var job = state.failed;
    state.failed = null;
    if (job && job.op !== "saveNote") state.queue.unshift(job);
    flush(state);
}
function cancelFailedForm(state) {
    if (!state.failed || !state.failed.form) return;
    if (state.failed.op === "deleteBookmark") delete state.deleting[state.failed.id];
    state.failed = null;
    flush(state);
}
function safeUrl(url) {
    return typeof url === "string" && url.length <= 16384
        && /^https?:\/\/(?:\[[0-9a-f:.]+\]|[^\s\/@?#:\\]+)(?::[0-9]+)?(?:[\/?#][^\x00-\x20\x7f-\x9f]*)?$/i.test(url)
        && !/[\\\x00-\x20\x7f-\x9f]/.test(url);
}
function validList(data) {
    function id(n) { return Number.isSafeInteger(n) && n > 0; }
    return data && Array.isArray(data.items) && data.items.length <= 100
        && Array.isArray(data.folders) && data.folders.length <= 200
        && (data.next === null || id(data.next))
        && data.folders.every(function (f) { return id(f.id) && typeof f.name === "string" && f.name.length <= 256; })
        && data.items.every(function (b) {
            return id(b.id) && safeUrl(b.url) && typeof b.title === "string" && b.title.length <= 4096
                && (b.folderId === null || id(b.folderId)) && typeof b.hasNote === "boolean"
                && typeof b.favicon === "string" && b.favicon.length <= 21848 && /^[A-Za-z0-9+/=]*$/.test(b.favicon);
        });
}
