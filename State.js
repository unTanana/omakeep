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
function cancelFailedForm(state, ops) {
    if (!state.failed || !state.failed.form || (ops && ops.indexOf(state.failed.op) < 0)) return;
    if (state.failed.op === "deleteBookmark") delete state.deleting[state.failed.id];
    state.failed = null;
    flush(state);
}
function safeUrl(url) {
    return typeof url === "string" && url.length <= 16384
        && /^https?:\/\/(?:\[[0-9a-f:.]+\]|[^\s\/@?#:\\]+)(?::[0-9]+)?(?:[\/?#][^\x00-\x20\x7f-\x9f]*)?$/i.test(url)
        && !/[\\\x00-\x20\x7f-\x9f]/.test(url);
}
function positiveId(n) { return Number.isSafeInteger(n) && n > 0; }
function validFolder(f) {
    return !!f && positiveId(f.id) && typeof f.name === "string" && f.name.length <= 256 && Number.isSafeInteger(f.count) && f.count >= 0;
}
// A stored link can be unusable and the row must still show, so url is only a string here; openLink and copyLink refuse unsafe ones.
function validRow(b) {
    return !!b && positiveId(b.id) && typeof b.url === "string" && b.url.length <= 16384 && typeof b.title === "string" && b.title.length <= 4096
        && (b.folderId === null || positiveId(b.folderId)) && typeof b.hasNote === "boolean"
        && typeof b.preview === "string" && b.preview.length <= 1024
        && typeof b.favicon === "string" && b.favicon.length <= 21848 && /^[A-Za-z0-9+/=]*$/.test(b.favicon);
}
function validList(data) {
    return !!data && Array.isArray(data.items) && data.items.length <= 100
        && Array.isArray(data.folders) && data.folders.length <= 200
        && (data.next === null || positiveId(data.next))
        && Number.isSafeInteger(data.total) && Number.isSafeInteger(data.all);
}
// One odd row or folder drops alone. It must never blank the whole list.
function goodRows(data) { return data.items.filter(validRow); }
function goodFolders(data) { return data.folders.filter(validFolder); }
function hostOf(url) {
    return String(url).replace(/^https?:\/\//i, "").replace(/[\/?#].*$/, "").replace(/:[0-9]*$/, "").replace(/^www\./i, "");
}
function comma(n) { return String(n).replace(/\B(?=(\d{3})+(?!\d))/g, ","); }
function plural(n, word) { return comma(n) + " " + word + (n === 1 ? "" : "s"); }
// Same cut as the helper's list reply, for a note edited since that reply.
function preview(text, query) {
    var flat = String(text).split(/[\s\x00-\x1f\x7f-\x9f]+/).filter(function (word) { return word.length > 0; }).join(" ");
    var at = query ? flat.toLowerCase().indexOf(query.toLowerCase()) : -1;
    var start = at - 30 > 10 ? at - 30 : 0;
    return (start ? "…" : "") + flat.substr(start, 200);
}
function byteLength(text) {
    var bytes = 0;
    for (var i = 0; i < text.length; i++) {
        var c = text.charCodeAt(i);
        if (c >= 0xd800 && c < 0xdc00 && i + 1 < text.length) { bytes += 4; i++; }
        else bytes += c < 0x80 ? 1 : c < 0x800 ? 2 : 3;
    }
    return bytes;
}
function folderProblem(name, folders, id) {
    var wanted = name.trim();
    if (!wanted) return "Enter a folder name.";
    if (folders.some(function (f) { return f.id !== id && f.name.toLowerCase() === wanted.toLowerCase(); })) return "That name is already used.";
    return byteLength(wanted) > 256 ? "That name is too long." : "";
}
function noteState(state, id, savedId) {
    if (state.drafts[id]) return state.failed ? "failed" : "saving";
    return savedId === id ? "saved" : "idle";
}
function failureText(state, openId) {
    if (!state.failed) return "";
    var waiting = Object.keys(state.drafts).filter(function (key) { return Number(key) !== openId; }).length;
    if (waiting) return plural(waiting, "note") + " not saved. Your text is kept in this window.";
    var labels = { capture: "Adding the bookmark", move: "Moving the bookmark", renameBookmark: "Renaming the bookmark",
        deleteBookmark: "Deleting the bookmark", createFolder: "Creating the folder", renameFolder: "Renaming the folder", deleteFolder: "Deleting the folder" };
    return labels[state.failed.op] ? labels[state.failed.op] + " didn't save." : "";
}
