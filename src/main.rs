// The one Omakeep helper. The panel runs it with --qml for each request. Chromium runs it as a native
// messaging host and passes the extension origin as the first argument; that side may only capture.
use base64::{Engine, engine::general_purpose::STANDARD as B64};
use rusqlite::{
    Connection, MAIN_DB, OptionalExtension,
    config::DbConfig,
    hooks::{AuthAction, AuthContext, Authorization},
    limits::Limit,
    params,
    types::ValueRef,
};
use rustix::{
    event::{PollFd, PollFlags, Timespec, poll},
    fd::{AsFd, OwnedFd},
    fs::{self, AtFlags, FlockOperation, Mode, OFlags},
    io::Errno,
    process::{getuid, umask},
    rand::{GetRandomFlags, getrandom},
};
use serde::Serialize;
use serde_json::Value;
use std::{
    borrow::Cow,
    collections::HashMap,
    fs::File,
    io::{Read, Write},
    process::{Command, Stdio},
    thread::sleep,
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};
use url::Url;

const MAX_MESSAGE: usize = 256 * 1024;
const MAX_DATABASE: u64 = 64 * 1024 * 1024;
const MAX_FOLDERS: i64 = 200;
const PAGE: usize = 100;
const BLANK_MAX: usize = 512;
const MAX_TITLE: usize = 4096;
const MAX_FOLDER_NAME: usize = 256;
const SAFE_MAX: i64 = 9_007_199_254_740_991;
const PREVIEW_CHARS: usize = 200;
const PREVIEW_SCAN: usize = 4096;
// Whitespace included, this is the text every existing library already holds.
const SCHEMA: &str = "
    CREATE TABLE folders (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL UNIQUE
      CHECK(length(CAST(name AS BLOB)) BETWEEN 1 AND 256)) STRICT;
    CREATE TABLE bookmarks (
      id INTEGER PRIMARY KEY AUTOINCREMENT, url TEXT NOT NULL UNIQUE, title TEXT NOT NULL,
      notes TEXT NOT NULL DEFAULT '', folderId INTEGER REFERENCES folders(id) ON DELETE SET NULL,
      favicon BLOB, createdAt INTEGER NOT NULL, updatedAt INTEGER NOT NULL,
      CHECK(length(CAST(url AS BLOB)) <= 16384), CHECK(length(CAST(title AS BLOB)) <= 4096),
      CHECK(length(CAST(notes AS BLOB)) <= 65536), CHECK(length(favicon) <= 16384)
    ) STRICT;
    PRAGMA user_version=1;
  ";
// ponytail: literal linear search; add FTS only when the measured 10k-library target fails.
const MATCHES: &str = "(? IS NULL OR folderId=?)
    AND (?='' OR instr(lower(title),lower(?)) OR instr(lower(url),lower(?)) OR instr(lower(notes),lower(?)))";

// Three error classes, so OS and SQLite text never reaches a reply.
enum Fail {
    Say(String),
    Sql,
    Os,
}
type R<T> = Result<T, Fail>;
impl From<rusqlite::Error> for Fail {
    fn from(_: rusqlite::Error) -> Self {
        Fail::Sql
    }
}
impl From<std::io::Error> for Fail {
    fn from(_: std::io::Error) -> Self {
        Fail::Os
    }
}
impl From<Errno> for Fail {
    fn from(_: Errno) -> Self {
        Fail::Os
    }
}
fn check(ok: bool, message: &str) -> R<()> {
    if ok { Ok(()) } else { Err(Fail::Say(message.into())) }
}

// JS String.prototype.trim: differs from Rust's trim on U+0085 and U+FEFF.
fn js_space(c: char) -> bool {
    matches!(c, '\t' | '\n' | '\x0b' | '\x0c' | '\r' | ' ' | '\u{a0}' | '\u{1680}' | '\u{2000}'..='\u{200a}'
        | '\u{2028}' | '\u{2029}' | '\u{202f}' | '\u{205f}' | '\u{3000}' | '\u{feff}')
}
fn trim(s: &str) -> &str {
    s.trim_matches(js_space)
}

fn text<'a>(v: Option<&'a Value>, limit: usize, name: &str, empty: bool) -> R<&'a str> {
    let bad = format!("Invalid {name}.");
    let s = v.and_then(Value::as_str).ok_or_else(|| Fail::Say(bad.clone()))?;
    check(s.len() <= limit && !s.contains('\0') && (empty || !trim(s).is_empty()), &bad)?;
    Ok(s)
}
fn optional<'a>(req: &'a Value, key: &str) -> Option<&'a Value> {
    match req.get(key) {
        None | Some(Value::Null) => None,
        v => v,
    }
}
fn text_or_empty<'a>(req: &'a Value, key: &str, limit: usize, name: &str) -> R<&'a str> {
    match optional(req, key) {
        None => Ok(""),
        v => text(v, limit, name, true),
    }
}

fn http_prefix(v: &str) -> bool {
    let has = |p: &str| v.len() >= p.len() && v.as_bytes()[..p.len()].eq_ignore_ascii_case(p.as_bytes());
    has("http://") || has("https://")
}
fn url_chars_ok(v: &str) -> bool {
    !v.chars().any(|c| c == '\\' || c <= ' ' || ('\x7f'..='\u{9f}').contains(&c))
}
// Writes get the full WHATWG parse. The trimmed original is what gets stored, not the normalised form.
fn parse_url(value: &str) -> R<(String, String)> {
    let v = trim(value).to_string();
    check(value.len() <= 16384 && !value.contains('\0') && !v.is_empty(), "Invalid URL.")?;
    check(http_prefix(&v) && url_chars_ok(&v), "Invalid URL.")?;
    let p = Url::parse(&v).map_err(|_| Fail::Say("Invalid URL.".into()))?;
    let host = p.host_str().unwrap_or("").to_string();
    check(
        matches!(p.scheme(), "http" | "https")
            && !host.is_empty()
            && p.username().is_empty()
            && p.password().is_none_or(str::is_empty),
        "Use an HTTP or HTTPS URL without credentials.",
    )?;
    Ok((v, host))
}
// Reads check only the scheme and characters. The full parse refuses old hosts Node took, such as xn--a.
fn stored_url_ok(v: &str) -> bool {
    v.len() <= 16384 && http_prefix(v) && url_chars_ok(v)
}

fn safe_id(n: i64) -> bool {
    n > 0 && n <= SAFE_MAX
}
fn id(v: Option<&Value>) -> R<i64> {
    let f = v.and_then(Value::as_f64).unwrap_or(0.0);
    check(f.fract() == 0.0 && f > 0.0 && f <= SAFE_MAX as f64, "Invalid item ID.")?;
    Ok(f as i64)
}
fn nullable_id(v: Option<&Value>) -> R<Option<i64>> {
    match v {
        None | Some(Value::Null) => Ok(None),
        v => id(v).map(Some),
    }
}

fn be32(b: &[u8], at: usize) -> u32 {
    u32::from_be_bytes([b[at], b[at + 1], b[at + 2], b[at + 3]])
}
fn png_ok(b: &[u8]) -> bool {
    b.len() >= 45
        && b.len() <= 16384
        && b[..8] == [0x89, b'P', b'N', b'G', 0x0d, 0x0a, 0x1a, 0x0a]
        && be32(b, 8) == 13
        && &b[12..16] == b"IHDR"
        && (1..=64).contains(&be32(b, 16))
        && (1..=64).contains(&be32(b, 20))
}
// A saved icon with no visible pixel would show as a gap, so it counts as no icon. The alpha bytes of a
// PNG row filter only against other alpha bytes, so they are all zero exactly when the image is clear.
// ponytail: Chromium premultiplies, so a clear icon is all zeros and packs to almost nothing. Larger files
// skip the inflate, which was 40% of a list; a large file of colour under zero alpha would show as a gap.
fn png_blank(b: &[u8]) -> bool {
    if b.len() > BLANK_MAX {
        return false;
    }
    let (width, height) = (be32(b, 16) as usize, be32(b, 20) as usize);
    let (depth, color, interlace) = (b[24] as usize, b[25], b[28]);
    let channels = match color {
        4 => 2,
        6 => 4,
        _ => return false,
    };
    if !matches!(depth, 8 | 16) || interlace != 0 {
        return false;
    }
    let mut packed = Vec::new();
    let mut at = 33;
    while at + 12 <= b.len() {
        let size = be32(b, at) as usize;
        let Some(data) = b.get(at + 8..at + 8 + size) else { return false };
        if &b[at + 4..at + 8] == b"IDAT" {
            packed.extend_from_slice(data);
        }
        at += size + 12;
    }
    let sample = depth / 8;
    let pixel = channels * sample;
    let line = 1 + width * pixel;
    let Ok(rows) = miniz_oxide::inflate::decompress_to_vec_zlib_with_limit(&packed, line * height) else {
        return false;
    };
    rows.len() == line * height
        && rows.chunks_exact(line).all(|row| row[1..].chunks_exact(pixel).all(|p| p[pixel - sample..].iter().all(|a| *a == 0)))
}
fn icon(v: Option<&Value>) -> Option<Vec<u8>> {
    let s = v?.as_str()?;
    if s.len() > 21848 {
        return None;
    }
    B64.decode(s).ok().filter(|b| png_ok(b) && !png_blank(b))
}

// Walks from / through held descriptors, so no pathname is ever reopened.
fn directory(target: &str, private_leaf: bool) -> R<OwnedFd> {
    check(target.starts_with('/') && !target.split('/').any(|p| p == ".."), "Use an absolute data directory.")?;
    let mut fd = fs::open("/", OFlags::RDONLY | OFlags::DIRECTORY | OFlags::CLOEXEC, Mode::empty())?;
    let system_uid = fs::fstat(&fd)?.st_uid;
    let me = getuid().as_raw();
    let parts: Vec<&str> = target.split('/').filter(|p| !p.is_empty()).collect();
    for (i, part) in parts.iter().enumerate() {
        match fs::mkdirat(&fd, *part, Mode::RWXU) {
            Ok(()) | Err(Errno::EXIST) => {}
            Err(e) => return Err(e.into()),
        }
        let flags = OFlags::RDONLY | OFlags::DIRECTORY | OFlags::NOFOLLOW | OFlags::NONBLOCK | OFlags::CLOEXEC;
        fd = fs::openat(&fd, *part, flags, Mode::empty())?;
        let st = fs::fstat(&fd)?;
        check(st.st_uid == system_uid || st.st_uid == me, "Unsafe directory owner.")?;
        check(
            st.st_mode & 0o022 == 0 || (st.st_uid == system_uid && st.st_mode & 0o1000 != 0),
            "Unsafe writable directory.",
        )?;
        if private_leaf && i == parts.len() - 1 {
            check(st.st_uid == me && st.st_mode & 0o077 == 0, "Omakeep data directory must be private (0700).")?;
        }
    }
    Ok(fd)
}

fn open_private(dir: &OwnedFd, name: &str) -> R<Option<(File, u64)>> {
    let flags = OFlags::RDONLY | OFlags::NOFOLLOW | OFlags::NONBLOCK | OFlags::CLOEXEC;
    let fd = match fs::openat(dir, name, flags, Mode::empty()) {
        Ok(fd) => fd,
        Err(Errno::NOENT) => return Ok(None),
        Err(e) => return Err(e.into()),
    };
    let st = fs::fstat(&fd)?;
    check(
        st.st_mode & 0o170000 == 0o100000
            && st.st_uid == getuid().as_raw()
            && st.st_nlink == 1
            && st.st_mode & 0o077 == 0
            && st.st_size as u64 <= MAX_DATABASE,
        "Unsafe or oversized private file.",
    )?;
    Ok(Some((File::from(fd), st.st_size as u64)))
}

fn write_private(dir: &OwnedFd, name: &str, bytes: &[u8]) -> R<()> {
    let mut random = [0u8; 16];
    getrandom(&mut random, GetRandomFlags::empty())?;
    let hex: String = random.iter().map(|b| format!("{b:02x}")).collect();
    let temp = format!(".omakeep-{hex}");
    let flags = OFlags::WRONLY | OFlags::CREATE | OFlags::EXCL | OFlags::NOFOLLOW | OFlags::CLOEXEC;
    let fd = fs::openat(dir, &temp, flags, Mode::RUSR | Mode::WUSR)?;
    let result: R<()> = (|| {
        fs::fchmod(&fd, Mode::RUSR | Mode::WUSR)?;
        let mut file = File::from(fd);
        file.write_all(bytes)?;
        file.sync_all()?;
        fs::renameat(dir, &temp, dir, name)?;
        fs::fsync(dir)?;
        Ok(())
    })();
    match fs::unlinkat(dir, &temp, AtFlags::empty()) {
        Ok(()) | Err(Errno::NOENT) => result,
        Err(e) => result.and(Err(e.into())),
    }
}

// SQLite never opens the path: the file is loaded into memory and written back as one snapshot, no journals.
fn database(file: Option<(File, u64)>) -> R<Connection> {
    let mut db = Connection::open_in_memory()?;
    let fresh = file.is_none();
    if let Some((mut f, len)) = file {
        check(len > 0, "Invalid library file.")?;
        db.deserialize_read_exact(MAIN_DB, &mut f, len as usize, false)
            .map_err(|_| Fail::Say("Private file changed while reading.".into()))?;
        check(f.read(&mut [0u8])? == 0, "Private file changed while reading.")?;
    }
    // node:sqlite sets these three by default, without a line in the old helper saying so.
    db.set_db_config(DbConfig::SQLITE_DBCONFIG_DEFENSIVE, true)?;
    db.set_db_config(DbConfig::SQLITE_DBCONFIG_DQS_DML, false)?;
    db.set_db_config(DbConfig::SQLITE_DBCONFIG_DQS_DDL, false)?;
    db.set_limit(Limit::SQLITE_LIMIT_LENGTH, MAX_MESSAGE as i32)?;
    db.set_limit(Limit::SQLITE_LIMIT_ATTACHED, 0)?;
    db.set_limit(Limit::SQLITE_LIMIT_TRIGGER_DEPTH, 16)?;
    db.execute_batch("PRAGMA trusted_schema=OFF; PRAGMA foreign_keys=ON; PRAGMA temp_store=MEMORY; PRAGMA page_size=4096; PRAGMA mmap_size=67108864;")?;
    db.query_row("PRAGMA max_page_count=16384", [], |_| Ok(()))?;
    if fresh {
        db.execute_batch(SCHEMA)?;
    }
    let version: i64 = db.query_row("PRAGMA user_version", [], |r| r.get(0))?;
    check(version == 1, "Unsupported library version.")?;
    let odd: i64 = db.query_row("SELECT count(*) FROM sqlite_schema WHERE type IN ('trigger', 'view')", [], |r| r.get(0))?;
    check(odd == 0, "Unexpected library schema.")?;
    db.authorizer(Some(|ctx: AuthContext<'_>| match ctx.action {
        AuthAction::Attach { .. } | AuthAction::Detach { .. } | AuthAction::CreateVtable { .. } => Authorization::Deny,
        _ => Authorization::Allow,
    }))?;
    Ok(db)
}

#[derive(Serialize)]
struct Folder {
    id: i64,
    name: String,
    count: i64,
}
#[derive(Serialize)]
#[allow(non_snake_case)]
struct Item {
    id: i64,
    url: String,
    title: String,
    folderId: Option<i64>,
    favicon: String,
    hasNote: bool,
    preview: String,
}
#[derive(Serialize)]
struct Captured {
    id: i64,
    added: bool,
}
#[derive(Serialize)]
struct Note {
    notes: String,
}
#[derive(Serialize)]
struct Created {
    id: i64,
}

fn js<T: Serialize>(v: &T) -> R<String> {
    serde_json::to_string(v).map_err(|_| Fail::Sql)
}
fn now() -> i64 {
    SystemTime::now().duration_since(UNIX_EPOCH).map_or(0, |d| d.as_millis() as i64)
}
fn lossy<'a>(r: ValueRef<'a>) -> Cow<'a, str> {
    match r {
        ValueRef::Text(b) | ValueRef::Blob(b) => String::from_utf8_lossy(b),
        _ => Cow::Borrowed(""),
    }
}
fn changed(n: usize, message: &str) -> R<String> {
    check(n == 1, message)?;
    Ok("{}".into())
}

// One old row must never fail a list, because that blanks the whole panel. Text is cut to its limit
// and cleaned for display, and the panel refuses to open a row whose URL comes back empty.
fn shown(r: ValueRef<'_>, limit: usize) -> String {
    let mut s = lossy(r).replace('\0', "");
    s.truncate(s.floor_char_boundary(limit));
    s
}

// A short one-line look at the note. With a search it starts near the match, so the hit stays in view.
fn preview(notes: &str, query: &str) -> String {
    // Without a search only the start can show, and a long note should not cost its whole length.
    let notes = if query.is_empty() { &notes[..notes.floor_char_boundary(PREVIEW_SCAN)] } else { notes };
    let flat = notes.split(|c: char| js_space(c) || c.is_control()).filter(|w| !w.is_empty()).collect::<Vec<_>>().join(" ");
    let hit = if query.is_empty() { None } else { flat.to_ascii_lowercase().find(&query.to_ascii_lowercase()) };
    let start = hit.map_or(0, |at| flat[..at].chars().count()).checked_sub(30).filter(|n| *n > 10).unwrap_or(0);
    let body = flat.chars().skip(start).take(PREVIEW_CHARS);
    if start > 0 { std::iter::once('…').chain(body).collect() } else { body.collect() }
}

fn list(db: &Connection, req: &Value) -> R<String> {
    let query = text_or_empty(req, "query", 4096, "search")?;
    let folder = nullable_id(optional(req, "folderId"))?;
    let before = match optional(req, "before") {
        None => SAFE_MAX,
        v => id(v)?,
    };
    let mut counts = HashMap::new();
    let mut all = 0;
    let mut st = db.prepare("SELECT folderId,count(*) FROM bookmarks GROUP BY folderId")?;
    let mut rows = st.query([])?;
    while let Some(row) = rows.next()? {
        let count: i64 = row.get(1)?;
        all += count;
        counts.insert(row.get_ref(0)?.as_i64().unwrap_or(0), count);
    }
    let mut folders = Vec::new();
    let mut st = db.prepare("SELECT id,name FROM folders ORDER BY name COLLATE NOCASE LIMIT ?")?;
    let mut rows = st.query([MAX_FOLDERS])?;
    while let Some(row) = rows.next()? {
        let id: i64 = row.get(0)?;
        let name = shown(row.get_ref(1)?, MAX_FOLDER_NAME);
        if safe_id(id) {
            let name = if trim(&name).is_empty() { "Unnamed folder".into() } else { name };
            folders.push(Folder { id, name, count: counts.get(&id).copied().unwrap_or(0) });
        }
    }
    // One pass finds the page and the total. Without a search the counts above already hold the total.
    let known = match folder {
        _ if !query.is_empty() => None,
        None => Some(all),
        Some(f) => Some(counts.get(&f).copied().unwrap_or(0)),
    };
    let mut total = 0;
    let mut ids = Vec::new();
    let mut st = db.prepare(&format!("SELECT id FROM bookmarks WHERE {MATCHES} ORDER BY id DESC"))?;
    let mut rows = st.query(params![folder, folder, query, query, query, query])?;
    while let Some(row) = rows.next()? {
        total += 1;
        let id: i64 = row.get(0)?;
        // An id no operation can address never lists.
        if id < before && safe_id(id) && ids.len() <= PAGE {
            ids.push(id);
        }
        if known.is_some() && ids.len() > PAGE {
            break;
        }
    }
    let total = known.unwrap_or(total);
    let folders = js(&folders)?;
    let mut items = String::new();
    let mut next = None;
    let mut last = None;
    let mut shown_rows = 0;
    let mut st = db.prepare("SELECT url,title,folderId,favicon,notes FROM bookmarks WHERE id=?")?;
    for id in ids {
        let item = st.query_row([id], |row| {
            let url = lossy(row.get_ref(0)?);
            let notes = lossy(row.get_ref(4)?);
            Ok(Item {
                id,
                url: if stored_url_ok(&url) { url.into_owned() } else { String::new() },
                title: shown(row.get_ref(1)?, MAX_TITLE),
                folderId: row.get_ref(2)?.as_i64().ok().filter(|n| safe_id(*n)),
                favicon: match row.get_ref(3)? {
                    ValueRef::Blob(b) if png_ok(b) && !png_blank(b) => B64.encode(b),
                    _ => String::new(),
                },
                hasNote: !notes.is_empty(),
                preview: preview(&notes, query),
            })
        })?;
        let row = js(&item)?;
        if shown_rows == PAGE || folders.len() + items.len() + row.len() + 192 > MAX_MESSAGE {
            next = last;
            break;
        }
        if shown_rows > 0 {
            items.push(',');
        }
        items.push_str(&row);
        last = Some(id);
        shown_rows += 1;
    }
    let next = next.map_or("null".to_string(), |n: i64| n.to_string());
    Ok(format!(r#"{{"folders":{folders},"items":[{items}],"next":{next},"total":{total},"all":{all}}}"#))
}

// Returns the result JSON and whether the snapshot must be written back.
fn operate(db: &Connection, req: &Value) -> R<(String, bool)> {
    check(req.is_object(), "Invalid request.")?;
    let op = req.get("op").and_then(Value::as_str).unwrap_or("");
    let missing = "Bookmark no longer exists.";
    Ok(match op {
        "capture" => {
            let given = req.get("url").and_then(Value::as_str).ok_or_else(|| Fail::Say("Invalid URL.".into()))?;
            let (url, host) = parse_url(given)?;
            let given = trim(text_or_empty(req, "title", MAX_TITLE, "title")?);
            let title = if given.is_empty() { host.as_str() } else { given };
            let folder = nullable_id(optional(req, "folderId"))?;
            let t = now();
            let added = db.execute(
                "INSERT INTO bookmarks(url,title,folderId,favicon,createdAt,updatedAt)
                 VALUES(?,?,?,?,?,?) ON CONFLICT(url) DO NOTHING",
                params![url, title, folder, icon(req.get("favicon")), t, t],
            )? > 0;
            let id: i64 = db.query_row("SELECT id FROM bookmarks WHERE url=?", [&url], |r| r.get(0))?;
            (js(&Captured { id, added })?, added)
        }
        "list" => (list(db, req)?, false),
        "note" => {
            let row = db
                .query_row("SELECT notes FROM bookmarks WHERE id=?", [id(req.get("id"))?], |r| Ok(lossy(r.get_ref(0)?).into_owned()))
                .optional()?;
            let notes = row.ok_or_else(|| Fail::Say(missing.into()))?;
            check(notes.len() <= 65536 && !notes.contains('\0'), "Invalid note.")?;
            (js(&Note { notes })?, false)
        }
        "saveNote" => {
            let notes = text(req.get("notes"), 65536, "note", true)?;
            let n = db.execute("UPDATE bookmarks SET notes=?,updatedAt=? WHERE id=?", params![notes, now(), id(req.get("id"))?])?;
            (changed(n, missing)?, true)
        }
        "renameBookmark" => {
            let title = trim(text(req.get("title"), MAX_TITLE, "title", false)?);
            let n = db.execute("UPDATE bookmarks SET title=?,updatedAt=? WHERE id=?", params![title, now(), id(req.get("id"))?])?;
            (changed(n, missing)?, true)
        }
        "move" => {
            // The key must be present, though it may be null.
            let folder = match req.get("folderId") {
                Some(Value::Null) => None,
                v => Some(id(v)?),
            };
            let n = db.execute("UPDATE bookmarks SET folderId=?,updatedAt=? WHERE id=?", params![folder, now(), id(req.get("id"))?])?;
            (changed(n, missing)?, true)
        }
        "deleteBookmark" => {
            db.execute("DELETE FROM bookmarks WHERE id=?", [id(req.get("id"))?])?;
            ("{}".into(), true)
        }
        "createFolder" => {
            let n: i64 = db.query_row("SELECT count(*) FROM folders", [], |r| r.get(0))?;
            check(n < MAX_FOLDERS, "Folder limit reached (200).")?;
            let name = trim(text(req.get("name"), MAX_FOLDER_NAME, "folder", false)?);
            db.execute("INSERT INTO folders(name) VALUES(?)", [name])?;
            (js(&Created { id: db.last_insert_rowid() })?, true)
        }
        "renameFolder" => {
            let name = trim(text(req.get("name"), MAX_FOLDER_NAME, "folder", false)?);
            let n = db.execute("UPDATE folders SET name=? WHERE id=?", params![name, id(req.get("id"))?])?;
            (changed(n, "Folder no longer exists.")?, true)
        }
        "deleteFolder" => {
            db.execute("DELETE FROM folders WHERE id=?", [id(req.get("id"))?])?;
            ("{}".into(), true)
        }
        _ => return Err(Fail::Say("Unknown operation.".into())),
    })
}

// The same kernel lock the Node helper took, held on the folder until the write is published.
fn lock(dir: &OwnedFd) -> R<()> {
    let deadline = Instant::now() + Duration::from_secs(3);
    loop {
        match fs::flock(dir, FlockOperation::NonBlockingLockExclusive) {
            Ok(()) => return Ok(()),
            Err(Errno::WOULDBLOCK) if Instant::now() < deadline => sleep(Duration::from_millis(2)),
            Err(Errno::WOULDBLOCK) => return Err(Fail::Say("Library is busy. Your draft is kept; retry.".into())),
            Err(e) => return Err(e.into()),
        }
    }
}

fn run(req: &Value) -> R<String> {
    let base = match std::env::var("XDG_DATA_HOME") {
        Ok(v) if !v.is_empty() => v,
        _ => format!("{}/.local/share", std::env::var("HOME").map_err(|_| Fail::Os)?),
    };
    let dir = directory(&format!("{base}/omakeep"), true)?;
    let op = req.get("op").and_then(Value::as_str).unwrap_or("");
    if !matches!(op, "list" | "note") {
        lock(&dir)?;
    }
    let mut db = database(open_private(&dir, "bookmarks.sqlite")?)?;
    let (result, write) = operate(&db, req)?;
    if write {
        // ponytail: one locked snapshot, capped at 64 MiB; use a descriptor-safe disk API if larger libraries need it.
        let pages: i64 = db.query_row("PRAGMA page_count", [], |r| r.get(0))?;
        let page: i64 = db.query_row("PRAGMA page_size", [], |r| r.get(0))?;
        check((pages * page) as u64 <= MAX_DATABASE, "Library limit reached (64 MiB).")?;
        write_private(&dir, "bookmarks.sqlite", &db.serialize(MAIN_DB)?)?;
    }
    Ok(result)
}

fn read_request(native: bool) -> R<Value> {
    let mut input = File::from(std::io::stdin().as_fd().try_clone_to_owned()?);
    let deadline = Instant::now() + Duration::from_secs(3);
    let timeout = || Fail::Say("Request timed out.".into());
    let mut read_some = |buf: &mut [u8]| -> R<usize> {
        let left = deadline.checked_duration_since(Instant::now()).ok_or_else(timeout)?;
        let ts = Timespec { tv_sec: left.as_secs() as i64, tv_nsec: left.subsec_nanos() as i64 };
        let mut fds = [PollFd::new(&input, PollFlags::IN)];
        if poll(&mut fds, Some(&ts))? == 0 {
            return Err(timeout());
        }
        Ok(input.read(buf)?)
    };
    let mut bytes = vec![0u8; MAX_MESSAGE + 1];
    let mut size = 0;
    let expected = if native {
        let mut head = [0u8; 4];
        let mut got = 0;
        while got < 4 {
            let n = read_some(&mut head[got..])?;
            check(n > 0, "Truncated message.")?;
            got += n;
        }
        let n = u32::from_le_bytes(head) as usize;
        check(n > 0 && n <= MAX_MESSAGE, "Invalid message length.")?;
        n
    } else {
        MAX_MESSAGE + 1
    };
    while size < expected {
        let n = read_some(&mut bytes[size..expected])?;
        if n == 0 {
            break;
        }
        size += n;
    }
    check(size <= MAX_MESSAGE, "Message too large.")?;
    check(!native || size == expected, "Truncated message.")?;
    serde_json::from_slice(&bytes[..size]).map_err(|_| Fail::Say("Invalid request.".into()))
}

fn reply(mut payload: String, native: bool) {
    if payload.len() > MAX_MESSAGE {
        payload = r#"{"ok":false,"error":"Response too large."}"#.into();
    }
    let mut out = std::io::stdout().lock();
    if native {
        let _ = out.write_all(&(payload.len() as u32).to_le_bytes());
    }
    let _ = out.write_all(payload.as_bytes());
    let _ = out.flush();
}

// Runs after the reply, so a failed notification can never change the answer.
fn notify(message: &str) {
    let mut cmd = Command::new("/usr/bin/notify-send");
    cmd.args(["--app-name=Omakeep", "--expire-time=1800", message])
        .env_clear()
        .env("PATH", "/usr/bin:/bin")
        .env("LANG", "C.UTF-8")
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null());
    for key in ["HOME", "XDG_DATA_HOME", "XDG_RUNTIME_DIR", "WAYLAND_DISPLAY", "DBUS_SESSION_BUS_ADDRESS"] {
        if let Ok(v) = std::env::var(key) {
            cmd.env(key, v);
        }
    }
    let Ok(mut child) = cmd.spawn() else { return };
    let deadline = Instant::now() + Duration::from_secs(1);
    while Instant::now() < deadline {
        if !matches!(child.try_wait(), Ok(None)) {
            return;
        }
        sleep(Duration::from_millis(5));
    }
    let _ = child.kill();
    let _ = child.wait();
}

fn main() {
    umask(Mode::from_raw_mode(0o077));
    std::thread::spawn(|| {
        sleep(Duration::from_secs(8));
        std::process::exit(124);
    });
    let mode = std::env::args_os().nth(1).map(|a| a.to_string_lossy().into_owned()).unwrap_or_default();
    if mode == "--version" {
        println!("{}", env!("CARGO_PKG_VERSION"));
        return;
    }
    // Chromium's first argument is always the calling origin, so that path can never pick another mode.
    let native = mode == "--native" || mode.starts_with("chrome-extension://");
    let outcome = (|| -> R<(String, bool)> {
        check(native || mode == "--qml", "Use --qml or --native.")?;
        let mut request = read_request(native)?;
        if native {
            check(request.get("op").and_then(Value::as_str) == Some("capture"), "Browser may only capture bookmarks.")?;
            // Filing a bookmark is a panel action.
            request.as_object_mut().map(|o| o.remove("folderId"));
        }
        let result = run(&request)?;
        let added = result.contains("\"added\":true");
        Ok((result, added))
    })();
    match outcome {
        Ok((result, added)) => {
            reply(format!("{{\"ok\":true,\"result\":{result}}}"), native);
            if native {
                notify(if added { "Saved to Omakeep" } else { "Already saved in Omakeep" });
            }
        }
        Err(fail) => {
            let message = match fail {
                Fail::Say(m) => m,
                Fail::Sql => "Library operation failed. Check for a duplicate folder name or retry.".into(),
                Fail::Os => "Cannot access the library safely. Check its location and permissions.".into(),
            };
            reply(format!("{{\"ok\":false,\"error\":{}}}", Value::String(message)), native);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // Node's validUrl and hostname on a generated sample, frozen before Node went away.
    #[test]
    fn urls_match_the_frozen_node_answers() {
        let (mut same, mut xn_only) = (0, 0);
        for line in include_str!("../tests/fixtures/node-urls.jsonl").lines() {
            // A lone surrogate cannot reach this code: the JSON parser refuses it first, as Node refused the URL.
            let Ok(case) = serde_json::from_str::<Vec<String>>(line) else {
                assert!(line.contains("\\ud"), "{line}");
                continue;
            };
            let got = parse_url(&case[0]).ok();
            match (case.len() > 1, got) {
                (true, Some((v, host))) => {
                    assert_eq!(v, case[1], "stored text for {:?}", case[0]);
                    assert_eq!(host, case[2], "host for {:?}", case[0]);
                    same += 1;
                }
                (false, None) => same += 1,
                // The one known gap: the port refuses malformed xn-- hosts on write. Never the reverse.
                (true, None) if case[0].contains("xn--") => xn_only += 1,
                (node, port) => panic!("{:?}: node accepts {node}, port gives {port:?}", case[0]),
            }
        }
        assert!(same >= 2400 && xn_only < 60, "same {same}, xn-- only {xn_only}");
    }

    #[test]
    fn stored_urls_are_never_judged_by_the_write_parser() {
        assert!(parse_url("http://xn--a/x").is_err());
        assert!(stored_url_ok("http://xn--a/x"));
        assert!(stored_url_ok("http://例え/x"), "a multi-byte host must not trip the prefix check");
        assert!(stored_url_ok("https://example.com:/x"));
        assert!(!stored_url_ok("javascript:alert(1)"));
        assert!(!stored_url_ok("https://a.test/\u{85}"));
    }

    #[test]
    fn trim_follows_js_not_rust() {
        assert_eq!(trim("\u{feff} a \u{a0}"), "a");
        assert_eq!(trim("\u{85}a\u{85}"), "\u{85}a\u{85}");
    }

    #[test]
    fn ids_follow_js_numbers() {
        for good in ["3", "3.0", "3e0", "9007199254740991"] {
            assert!(id(Some(&serde_json::from_str(good).unwrap())).is_ok(), "{good}");
        }
        for bad in ["0", "-1", "1.5", "9007199254740993", "1e308", "\"3\"", "null", "true"] {
            assert!(id(Some(&serde_json::from_str(bad).unwrap())).is_err(), "{bad}");
        }
    }

    #[test]
    fn previews_are_flat_short_and_keep_the_match_in_view() {
        assert_eq!(preview("one\n\n  two\tthree\u{1}four", ""), "one two three four");
        assert_eq!(preview("", "x"), "");
        assert_eq!(preview("short note", "note"), "short note");
        let long = format!("{}Needle tail", "é".repeat(100));
        let found = preview(&long, "NEEDLE");
        assert!(found.starts_with('…') && found.contains("Needle"), "{found}");
        assert_eq!(preview(&"x".repeat(5000), "").chars().count(), PREVIEW_CHARS);
        // Near the start the note stays whole, as in the mockup.
        assert_eq!(preview(&format!("{}Needle", "a".repeat(35)), "needle"), format!("{}Needle", "a".repeat(35)));
    }

    #[test]
    fn shown_text_cuts_on_a_character_boundary() {
        let long = "é".repeat(3000);
        let text = shown(ValueRef::Text(long.as_bytes()), MAX_TITLE);
        assert_eq!(text.len(), MAX_TITLE);
        assert_eq!(shown(ValueRef::Text(b"a\0b"), MAX_TITLE), "ab");
        assert_eq!(shown(ValueRef::Text(&[0xc3, 0x28]), MAX_TITLE), "\u{fffd}(");
    }
}
