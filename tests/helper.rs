// Runs the real binary the way the panel and Chromium do, always on a throwaway data folder.
use base64::{Engine, engine::general_purpose::STANDARD as B64};
use rusqlite::{Connection, params};
use rustix::fs::{FlockOperation, flock};
use serde_json::{Value, json};
use std::{
    fs,
    io::Write,
    os::unix::fs::{PermissionsExt, symlink},
    path::PathBuf,
    process::{Command, Output, Stdio},
    time::{Duration, Instant},
};

const HELPER: &str = env!("CARGO_BIN_EXE_omakeep-helper");
const ORIGIN: &str = "chrome-extension://lefgnegnkcnkapehnnkfnkmdfiaahnmf/";
const MAX_MESSAGE: usize = 256 * 1024;

struct Lib(PathBuf);

impl Lib {
    fn new(name: &str) -> Lib {
        let dir = PathBuf::from(env!("CARGO_TARGET_TMPDIR")).join(name);
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        Lib(dir)
    }
    fn folder(&self) -> PathBuf {
        self.0.join("omakeep")
    }
    fn file(&self) -> PathBuf {
        self.folder().join("bookmarks.sqlite")
    }
    fn command(&self, arg: &str) -> Command {
        let mut c = Command::new(HELPER);
        // No session bus here, so native captures raise no desktop notification.
        c.arg(arg).env_clear().env("HOME", &self.0).env("XDG_DATA_HOME", &self.0).env("PATH", "/bad-path");
        c.stdin(Stdio::piped()).stdout(Stdio::piped()).stderr(Stdio::piped());
        c
    }
    fn run(&self, arg: &str, input: &[u8]) -> Output {
        let mut child = self.command(arg).spawn().unwrap();
        // The helper stops reading at its limit, so a broken pipe here is expected.
        let _ = child.stdin.take().unwrap().write_all(input);
        child.wait_with_output().unwrap()
    }
    fn raw(&self, input: &[u8]) -> Value {
        let out = self.run("--qml", input);
        assert_eq!(out.status.code(), Some(0), "stderr: {}", String::from_utf8_lossy(&out.stderr));
        assert!(out.stdout.len() <= MAX_MESSAGE);
        serde_json::from_slice(&out.stdout).unwrap()
    }
    fn call(&self, request: Value) -> Value {
        self.raw(request.to_string().as_bytes())
    }
    fn ok(&self, request: Value) -> Value {
        let reply = self.call(request.clone());
        assert_eq!(reply["ok"], true, "{request}: {reply}");
        reply["result"].clone()
    }
    fn refused(&self, request: Value) -> String {
        let reply = self.call(request.clone());
        assert_eq!(reply["ok"], false, "{request}: {reply}");
        reply["error"].as_str().unwrap().to_string()
    }
    fn native(&self, arg: &str, request: &[u8]) -> Value {
        let mut framed = (request.len() as u32).to_le_bytes().to_vec();
        framed.extend_from_slice(request);
        self.native_bytes(arg, &framed)
    }
    fn native_bytes(&self, arg: &str, framed: &[u8]) -> Value {
        let out = self.run(arg, framed);
        assert_eq!(out.status.code(), Some(0));
        let size = u32::from_le_bytes(out.stdout[..4].try_into().unwrap()) as usize;
        assert_eq!(out.stdout.len(), size + 4, "frame length");
        serde_json::from_slice(&out.stdout[4..]).unwrap()
    }
    fn db(&self) -> Connection {
        Connection::open(self.file()).unwrap()
    }
}

fn chunk(kind: &[u8], data: &[u8]) -> Vec<u8> {
    let mut out = (data.len() as u32).to_be_bytes().to_vec();
    out.extend_from_slice(kind);
    out.extend_from_slice(data);
    out.extend_from_slice(&[0; 4]); // The helper does not read CRCs; Qt's decoder does, on the real path.
    out
}
fn png(width: u32, color: u8, pixel: &[u8]) -> Vec<u8> {
    let mut rows = Vec::new();
    for _ in 0..width {
        rows.push(0);
        for _ in 0..width {
            rows.extend_from_slice(pixel);
        }
    }
    let mut head = width.to_be_bytes().to_vec();
    head.extend_from_slice(&width.to_be_bytes());
    head.extend_from_slice(&[8, color, 0, 0, 0]);
    let mut out = vec![0x89, b'P', b'N', b'G', 0x0d, 0x0a, 0x1a, 0x0a];
    out.extend(chunk(b"IHDR", &head));
    out.extend(chunk(b"IDAT", &miniz_oxide::deflate::compress_to_vec_zlib(&rows, 6)));
    out.extend(chunk(b"IEND", &[]));
    out
}

// Fields the new panel needs. Node never sent them, so they are lifted out before comparing.
fn without_additions(mut reply: Value) -> Value {
    if let Some(result) = reply.get_mut("result").and_then(Value::as_object_mut) {
        if result.contains_key("folders") {
            assert!(result.remove("total").is_some() && result.remove("all").is_some());
            for folder in result["folders"].as_array_mut().unwrap() {
                assert!(folder.as_object_mut().unwrap().remove("count").is_some());
            }
            for item in result["items"].as_array_mut().unwrap() {
                assert!(item.as_object_mut().unwrap().remove("preview").is_some());
            }
        }
    }
    reply
}

fn frozen() -> Vec<Value> {
    include_str!("fixtures/node-replies.json").lines().map(|l| serde_json::from_str(l).unwrap()).collect()
}
fn request_bytes(case: &Value) -> Vec<u8> {
    match case["request"].as_str() {
        Some(text) => text.as_bytes().to_vec(),
        None => case["bytes"].as_array().unwrap().iter().map(|b| b.as_u64().unwrap() as u8).collect(),
    }
}
fn replay(lib: &Lib, case: &Value) -> Value {
    let request = request_bytes(case);
    if case["native"] == true { lib.native("--native", &request) } else { lib.raw(&request) }
}

#[test]
fn node_answers_replay_exactly() {
    let lib = Lib::new("replay");
    let cases = frozen();
    assert!(cases.len() >= 120);
    let mut refused_only = 0;
    for case in &cases {
        let got = replay(&lib, case);
        let want: Value = serde_json::from_str(case["reply"].as_str().unwrap()).unwrap();
        if case["malformed"] == true {
            assert_eq!(got["ok"], false, "still refused: {case}");
            refused_only += 1;
        } else {
            assert_eq!(without_additions(got), want, "request {}", case["request"]);
        }
    }
    assert_eq!(refused_only, 5);
    let library = lib.db();
    assert_eq!(library.query_row("PRAGMA integrity_check", [], |r| r.get::<_, String>(0)).unwrap(), "ok");
}

#[test]
fn replies_keep_node_key_order_with_additions_after() {
    let lib = Lib::new("order");
    assert!(String::from_utf8(lib.run("--qml", br#"{"op":"list"}"#).stdout).unwrap().starts_with(r#"{"ok":true,"result":{"folders":[],"items":[],"next":null,"total":0,"all":0}"#));
    lib.ok(json!({"op": "createFolder", "name": "A"}));
    lib.ok(json!({"op": "capture", "url": "https://a.test/", "title": "A"}));
    let raw = String::from_utf8(lib.run("--qml", br#"{"op":"list"}"#).stdout).unwrap();
    assert!(raw.contains(r#"{"id":1,"name":"A","count":0}"#), "{raw}");
    assert!(raw.contains(r#"{"id":1,"url":"https://a.test/","title":"A","folderId":null,"favicon":"","hasNote":false,"preview":""}"#), "{raw}");
    assert_eq!(String::from_utf8(lib.run("--qml", br#"{"op":"nope"}"#).stdout).unwrap(), r#"{"ok":false,"error":"Unknown operation."}"#);
}

#[test]
fn a_library_node_wrote_opens_and_stays_the_same_format() {
    let lib = Lib::new("node-file");
    fs::create_dir_all(lib.folder()).unwrap();
    fs::set_permissions(lib.folder(), fs::Permissions::from_mode(0o700)).unwrap();
    fs::write(lib.file(), include_bytes!("fixtures/node-library.db")).unwrap();
    fs::set_permissions(lib.file(), fs::Permissions::from_mode(0o600)).unwrap();
    let before = lib.ok(json!({"op": "list"}));
    assert!(before["items"].as_array().unwrap().len() > 10);
    lib.ok(json!({"op": "saveNote", "id": 5, "notes": "written by the port"}));

    let fresh = Lib::new("fresh-file");
    fresh.ok(json!({"op": "capture", "url": "https://a.test/"}));
    let schema = |db: &Connection| -> Vec<String> {
        let mut st = db.prepare("SELECT sql FROM sqlite_schema WHERE sql IS NOT NULL ORDER BY name").unwrap();
        st.query_map([], |r| r.get(0)).unwrap().map(Result::unwrap).collect()
    };
    let (a, b) = (lib.db(), fresh.db());
    assert_eq!(schema(&a), schema(&b), "same schema text from both writers");
    for db in [&a, &b] {
        assert_eq!(db.query_row("PRAGMA user_version", [], |r| r.get::<_, i64>(0)).unwrap(), 1);
        assert_eq!(db.query_row("PRAGMA journal_mode", [], |r| r.get::<_, String>(0)).unwrap(), "delete");
        assert_eq!(db.query_row("PRAGMA page_size", [], |r| r.get::<_, i64>(0)).unwrap(), 4096);
    }
    assert_eq!(fs::metadata(lib.file()).unwrap().permissions().mode() & 0o777, 0o600);
    assert_eq!(fs::read_dir(lib.folder()).unwrap().count(), 1, "no temp files or journals left");
}

// A read stricter than Node would blank the panel, so every bad row here must leave the rest standing.
#[test]
fn one_bad_row_never_blanks_the_list() {
    let lib = Lib::new("bad-rows");
    lib.ok(json!({"op": "createFolder", "name": "Kept"}));
    lib.ok(json!({"op": "createFolder", "name": "Odd"}));
    for n in 1..=10 {
        lib.ok(json!({"op": "capture", "url": format!("https://good.test/{n}"), "title": format!("Good {n}")}));
    }
    let db = lib.db();
    // Hand edits and old writers can leave what the schema's checks would stop today.
    db.execute_batch("PRAGMA ignore_check_constraints=ON; PRAGMA foreign_keys=OFF").unwrap();
    for (row, sql) in [
        ("url", "UPDATE bookmarks SET url='notaurl' WHERE id=1"),
        ("url script", "UPDATE bookmarks SET url='javascript:alert(1)' WHERE id=2"),
        ("url control", "UPDATE bookmarks SET url=CAST(x'68747470733a2f2f612e746573742f0a62' AS TEXT) WHERE id=3"),
        ("title utf-8", "UPDATE bookmarks SET title=CAST(x'c328' AS TEXT) WHERE id=4"),
        ("title nul", "UPDATE bookmarks SET title=CAST(x'610062' AS TEXT) WHERE id=5"),
        ("title long", "UPDATE bookmarks SET title=hex(zeroblob(4000)) WHERE id=6"),
        ("folder missing", "UPDATE bookmarks SET folderId=999 WHERE id=7"),
        ("favicon junk", "UPDATE bookmarks SET favicon=x'00112233' WHERE id=8"),
        ("note nul", "UPDATE bookmarks SET notes=CAST(x'610062' AS TEXT) WHERE id=9"),
        ("note long", "UPDATE bookmarks SET notes=hex(zeroblob(40000)) WHERE id=10"),
        ("folder name", "UPDATE folders SET name=CAST(x'00' AS TEXT) WHERE id=2"),
        ("negative id", "INSERT INTO bookmarks(id,url,title,createdAt,updatedAt) VALUES(-5,'https://neg.test/','Negative',1,1)"),
    ] {
        db.execute_batch(sql).unwrap_or_else(|e| panic!("{row}: {e}"));
    }
    drop(db);
    let list = lib.ok(json!({"op": "list"}));
    let items = list["items"].as_array().unwrap();
    assert_eq!(items.len(), 10, "every addressable row is listed: {list}");
    assert_eq!(list["next"], Value::Null);
    let by_id = |id: i64| items.iter().find(|i| i["id"] == id).unwrap().clone();
    for bad in [1, 2, 3] {
        assert_eq!(by_id(bad)["url"], "", "a URL that fails stays out of the panel");
    }
    assert_eq!(by_id(4)["title"], "\u{fffd}(");
    assert_eq!(by_id(5)["title"], "ab");
    assert_eq!(by_id(6)["title"].as_str().unwrap().len(), 4096);
    assert_eq!(by_id(8)["favicon"], "");
    assert_eq!(by_id(10)["hasNote"], true);
    assert!(list["folders"].as_array().unwrap().iter().any(|f| f["name"] == "Unnamed folder"));

    // Those rows can still be fixed from the panel.
    lib.ok(json!({"op": "renameBookmark", "id": 1, "title": "Fixed title"}));
    lib.ok(json!({"op": "move", "id": 3, "folderId": 1}));
    lib.ok(json!({"op": "deleteBookmark", "id": 2}));
    assert_eq!(lib.ok(json!({"op": "list"}))["items"].as_array().unwrap().len(), 9);
    assert!(lib.refused(json!({"op": "note", "id": 9})).contains("note"), "only that note is refused");

    // Old hosts the full parser would refuse still list unchanged, as they did under Node.
    let fine = lib.db();
    fine.execute("UPDATE bookmarks SET url=?", ["http://xn--a/x"]).unwrap_or(0);
    fine.execute("UPDATE bookmarks SET url='http://例え/x' WHERE id=4", []).unwrap();
    fine.execute("UPDATE bookmarks SET url='http://xn--a/x' WHERE id=5", []).unwrap();
    drop(fine);
    let list = lib.ok(json!({"op": "list"}));
    let url = |id: i64| list["items"].as_array().unwrap().iter().find(|i| i["id"] == id).unwrap()["url"].clone();
    assert_eq!(url(4), "http://例え/x");
    assert_eq!(url(5), "http://xn--a/x");
}

#[test]
fn too_many_folders_never_blanks_the_list() {
    let lib = Lib::new("many-folders");
    lib.ok(json!({"op": "capture", "url": "https://a.test/"}));
    let db = lib.db();
    for n in 0..205 {
        db.execute("INSERT INTO folders(name) VALUES(?)", [format!("f{n}")]).unwrap();
    }
    drop(db);
    let list = lib.ok(json!({"op": "list"}));
    assert_eq!(list["folders"].as_array().unwrap().len(), 200);
    assert_eq!(list["items"].as_array().unwrap().len(), 1);
    assert_eq!(lib.refused(json!({"op": "createFolder", "name": "one more"})), "Folder limit reached (200).");
}

#[test]
fn lists_carry_counts_and_previews() {
    let lib = Lib::new("additions");
    let reading = lib.ok(json!({"op": "createFolder", "name": "Reading"}))["id"].clone();
    let empty = lib.ok(json!({"op": "createFolder", "name": "Empty"}))["id"].clone();
    for n in 1..=5 {
        lib.ok(json!({"op": "capture", "url": format!("https://a.test/{n}"), "title": format!("Page {n}")}));
    }
    lib.ok(json!({"op": "move", "id": 1, "folderId": reading}));
    lib.ok(json!({"op": "move", "id": 2, "folderId": reading}));
    lib.ok(json!({"op": "saveNote", "id": 1, "notes": "First line\n\n  second\tline"}));
    lib.ok(json!({"op": "saveNote", "id": 2, "notes": format!("{}Needle here", "padding ".repeat(20))}));

    let list = lib.ok(json!({"op": "list"}));
    assert_eq!((list["total"].as_i64(), list["all"].as_i64()), (Some(5), Some(5)));
    let count = |id: &Value| list["folders"].as_array().unwrap().iter().find(|f| f["id"] == *id).unwrap()["count"].clone();
    assert_eq!(count(&reading), 2);
    assert_eq!(count(&empty), 0);
    let item = |list: &Value, id: i64| list["items"].as_array().unwrap().iter().find(|i| i["id"] == id).unwrap().clone();
    assert_eq!(item(&list, 1)["preview"], "First line second line");

    let found = lib.ok(json!({"op": "list", "query": "needle"}));
    assert_eq!((found["total"].as_i64(), found["all"].as_i64()), (Some(1), Some(5)));
    let preview = item(&found, 2)["preview"].as_str().unwrap().to_string();
    assert!(preview.starts_with('…') && preview.contains("Needle here"), "{preview}");

    let folder = lib.ok(json!({"op": "list", "folderId": reading, "query": "page"}));
    assert_eq!((folder["total"].as_i64(), folder["all"].as_i64()), (Some(2), Some(5)));
}

#[test]
fn pages_stay_inside_the_message_limit_and_lose_nothing() {
    let lib = Lib::new("pages");
    // Big icons and full notes, so the byte budget ends each page early.
    let mut icon = png(64, 6, &[1, 2, 3, 255]);
    icon.resize(16000, 0);
    let total = 300;
    let db = {
        lib.ok(json!({"op": "capture", "url": "https://first.test/"}));
        let db = lib.db();
        db.execute("DELETE FROM bookmarks", []).unwrap();
        for n in 0..total {
            db.execute(
                "INSERT INTO bookmarks(url,title,notes,favicon,createdAt,updatedAt) VALUES(?,?,?,?,1,1)",
                params![format!("https://a.test/{n}/{}", "u".repeat(4000)), "t".repeat(4000), "\u{1}x".repeat(9000), icon],
            )
            .unwrap();
        }
        db
    };
    drop(db);
    let (mut seen, mut pages, mut before) = (0, 0, Value::Null);
    loop {
        let page = lib.ok(json!({"op": "list", "before": before}));
        assert!(page.to_string().len() < MAX_MESSAGE);
        assert_eq!(page["total"], total);
        seen += page["items"].as_array().unwrap().len();
        pages += 1;
        before = page["next"].clone();
        if before.is_null() {
            break;
        }
    }
    assert_eq!(seen, total as usize);
    assert!(pages > 3, "the budget split this: {pages} pages");
}

#[test]
fn a_clear_favicon_counts_as_no_icon() {
    let lib = Lib::new("favicons");
    let clear = B64.encode(png(32, 6, &[0, 0, 0, 0]));
    let clear_colored = B64.encode(png(32, 6, &[200, 10, 90, 0]));
    let visible = B64.encode(png(32, 6, &[0, 0, 0, 1]));
    let gray_clear = B64.encode(png(16, 4, &[255, 0]));
    lib.ok(json!({"op": "capture", "url": "https://clear.test/", "favicon": clear}));
    lib.ok(json!({"op": "capture", "url": "https://colored.test/", "favicon": clear_colored}));
    lib.ok(json!({"op": "capture", "url": "https://gray.test/", "favicon": gray_clear}));
    lib.ok(json!({"op": "capture", "url": "https://visible.test/", "favicon": visible}));
    let stored = |url: &str| -> bool {
        lib.db().query_row("SELECT favicon IS NOT NULL FROM bookmarks WHERE url=?", [url], |r| r.get(0)).unwrap()
    };
    assert!(!stored("https://clear.test/"), "new captures do not keep it");
    assert!(stored("https://visible.test/"));
    // Saved before this rule: stays on disk, shows as no icon.
    lib.db().execute("UPDATE bookmarks SET favicon=? WHERE url='https://clear.test/'", [B64.decode(&clear).unwrap()]).unwrap();
    let list = lib.ok(json!({"op": "list"}));
    let icon = |url: &str| list["items"].as_array().unwrap().iter().find(|i| i["url"] == url).unwrap()["favicon"].clone();
    assert_eq!(icon("https://clear.test/"), "");
    assert_eq!(icon("https://visible.test/"), visible.as_str());
}

#[test]
fn hostile_files_are_refused() {
    let lib = Lib::new("hostile");
    lib.ok(json!({"op": "capture", "url": "https://a.test/"}));
    let (file, original) = (lib.file(), lib.0.join("original"));
    let list = json!({"op": "list"});
    let capture = json!({"op": "capture", "url": "https://hostile.test/"});

    fs::rename(&file, &original).unwrap();
    symlink(&original, &file).unwrap();
    lib.refused(capture.clone());
    lib.refused(list.clone());
    fs::remove_file(&file).unwrap();

    assert!(Command::new("/usr/bin/mkfifo").arg(&file).status().unwrap().success());
    lib.refused(list.clone());
    fs::remove_file(&file).unwrap();

    fs::hard_link(&original, &file).unwrap();
    lib.refused(list.clone());
    fs::remove_file(&file).unwrap();

    fs::rename(&original, &file).unwrap();
    fs::set_permissions(&file, fs::Permissions::from_mode(0o644)).unwrap();
    lib.refused(list.clone());
    fs::set_permissions(&file, fs::Permissions::from_mode(0o600)).unwrap();

    fs::set_permissions(lib.folder(), fs::Permissions::from_mode(0o755)).unwrap();
    assert_eq!(lib.refused(list.clone()), "Omakeep data directory must be private (0700).");
    fs::set_permissions(lib.folder(), fs::Permissions::from_mode(0o700)).unwrap();

    let moved = lib.0.join("moved");
    fs::rename(lib.folder(), &moved).unwrap();
    symlink(&moved, lib.folder()).unwrap();
    lib.refused(list.clone());
    fs::remove_file(lib.folder()).unwrap();
    fs::rename(&moved, lib.folder()).unwrap();

    let good = fs::read(&file).unwrap();
    fs::write(&file, b"").unwrap();
    assert_eq!(lib.refused(list.clone()), "Invalid library file.");
    fs::write(&file, b"not a database at all".repeat(50)).unwrap();
    lib.refused(list.clone());
    for sql in ["PRAGMA user_version=2", "CREATE VIEW v AS SELECT 1", "CREATE TRIGGER t AFTER INSERT ON folders BEGIN SELECT 1; END"] {
        fs::write(&file, &good).unwrap();
        lib.db().execute_batch(sql).unwrap();
        lib.refused(list.clone());
        lib.refused(capture.clone());
    }
    let handle = fs::OpenOptions::new().write(true).open(&file).unwrap();
    handle.set_len(64 * 1024 * 1024 + 1).unwrap();
    assert_eq!(lib.refused(list.clone()), "Unsafe or oversized private file.");
    fs::write(&file, &good).unwrap();
    assert!(lib.ok(list.clone())["items"].as_array().unwrap().len() == 1);
    assert_eq!(fs::metadata(&file).unwrap().len(), good.len() as u64, "a refused write changed nothing");
}

#[test]
fn unsafe_data_paths_are_refused() {
    let lib = Lib::new("paths");
    let run = |dir: &str| -> Value {
        let mut c = lib.command("--qml");
        c.env("XDG_DATA_HOME", dir);
        let mut child = c.spawn().unwrap();
        child.stdin.take().unwrap().write_all(br#"{"op":"list"}"#).unwrap();
        serde_json::from_slice(&child.wait_with_output().unwrap().stdout).unwrap()
    };
    assert_eq!(run("relative/path")["error"], "Use an absolute data directory.");
    assert_eq!(run(&format!("{}/../up", lib.0.display()))["error"], "Use an absolute data directory.");
    let open = lib.0.join("open");
    fs::create_dir(&open).unwrap();
    fs::set_permissions(&open, fs::Permissions::from_mode(0o777)).unwrap();
    assert_eq!(run(open.to_str().unwrap())["error"], "Unsafe writable directory.");
    let real = lib.0.join("real");
    fs::create_dir(&real).unwrap();
    symlink(&real, lib.0.join("link")).unwrap();
    assert_eq!(run(lib.0.join("link").to_str().unwrap())["ok"], false, "a symlink at any level");
    // Empty counts as unset, so the data goes under HOME.
    assert_eq!(run("")["ok"], true);
    assert!(lib.0.join(".local/share/omakeep").is_dir());
    assert!(!lib.0.join(".local/share/omakeep/bookmarks.sqlite").exists(), "reads never create the file");
}

#[test]
fn a_new_library_is_private() {
    let lib = Lib::new("private");
    assert_eq!(lib.ok(json!({"op": "list"}))["items"], json!([]));
    assert!(!lib.file().exists(), "reads never create the file");
    lib.ok(json!({"op": "capture", "url": "https://first.test/"}));
    assert_eq!(fs::metadata(lib.folder()).unwrap().permissions().mode() & 0o777, 0o700);
    assert_eq!(fs::metadata(lib.file()).unwrap().permissions().mode() & 0o777, 0o600);
}

#[test]
fn chromium_may_only_capture() {
    let lib = Lib::new("native");
    lib.ok(json!({"op": "capture", "url": "https://panel.test/", "title": "Keep"}));
    lib.ok(json!({"op": "createFolder", "name": "Mine"}));
    let keep = fs::read(lib.file()).unwrap();
    for op in [
        json!({"op": "deleteBookmark", "id": 1}),
        json!({"op": "list"}),
        json!({"op": "note", "id": 1}),
        json!({"op": "saveNote", "id": 1, "notes": "x"}),
        json!({"op": "renameBookmark", "id": 1, "title": "x"}),
        json!({"op": "move", "id": 1, "folderId": null}),
        json!({"op": "createFolder", "name": "x"}),
        json!({"op": "renameFolder", "id": 1, "name": "x"}),
        json!({"op": "deleteFolder", "id": 1}),
        json!({"op": null}),
        json!([]),
        json!(null),
    ] {
        for arg in ["--native", ORIGIN] {
            let reply = lib.native(arg, op.to_string().as_bytes());
            assert_eq!(reply, json!({"ok": false, "error": "Browser may only capture bookmarks."}), "{op}");
        }
    }
    assert_eq!(fs::read(lib.file()).unwrap(), keep, "checked before the library is touched");

    // The way Chromium really calls it: its origin as the first argument.
    let saved = lib.native(ORIGIN, br#"{"op":"capture","url":"https://chrome.test/","title":"From Chrome","folderId":1}"#);
    assert_eq!(saved["result"]["added"], true);
    let item = lib.ok(json!({"op": "list"}))["items"][0].clone();
    assert_eq!(item["url"], "https://chrome.test/");
    assert_eq!(item["folderId"], Value::Null, "only the panel files bookmarks");
    assert_eq!(lib.native(ORIGIN, br#"{"op":"capture","url":"https://chrome.test/","title":"Again"}"#)["result"]["added"], false);

    for arg in ["", "--x", "--help", "http://evil.test/"] {
        assert_eq!(lib.run(arg, b"{}").stdout, br#"{"ok":false,"error":"Use --qml or --native."}"#);
    }
    let bare = Command::new(HELPER).env_clear().env("HOME", &lib.0).stdin(Stdio::null()).output().unwrap();
    assert_eq!(bare.stdout, br#"{"ok":false,"error":"Use --qml or --native."}"#);
}

#[test]
fn the_panel_files_a_new_bookmark_in_one_step() {
    let lib = Lib::new("capture-folder");
    let folder = lib.ok(json!({"op": "createFolder", "name": "Mine"}))["id"].clone();
    lib.ok(json!({"op": "capture", "url": "https://a.test/", "folderId": folder}));
    assert_eq!(lib.ok(json!({"op": "list", "folderId": folder}))["items"][0]["url"], "https://a.test/");
    assert_eq!(lib.ok(json!({"op": "capture", "url": "https://a.test/", "folderId": null}))["added"], false);
    assert_eq!(lib.ok(json!({"op": "list", "folderId": folder}))["total"], 1, "a duplicate stays where it was");
    assert_eq!(lib.refused(json!({"op": "capture", "url": "https://b.test/", "folderId": 0})), "Invalid item ID.");
    lib.refused(json!({"op": "capture", "url": "https://b.test/", "folderId": 999}));
    assert_eq!(lib.ok(json!({"op": "list"}))["all"], 1);
}

#[test]
fn frames_are_bounded() {
    let lib = Lib::new("frames");
    let refused = |bytes: &[u8], want: &str| {
        let reply = lib.native_bytes("--native", bytes);
        assert_eq!(reply, json!({"ok": false, "error": want}));
    };
    refused(&0u32.to_le_bytes(), "Invalid message length.");
    refused(&((MAX_MESSAGE + 1) as u32).to_le_bytes(), "Invalid message length.");
    refused(&u32::MAX.to_le_bytes(), "Invalid message length.");
    refused(&[5, 0], "Truncated message.");
    let mut short = 50u32.to_le_bytes().to_vec();
    short.extend_from_slice(b"{\"op\":\"capture\"");
    refused(&short, "Truncated message.");
    assert_eq!(lib.raw(&vec![b' '; MAX_MESSAGE + 1])["error"], "Message too large.");
}

#[test]
fn limits_are_in_bytes() {
    let lib = Lib::new("limits");
    lib.ok(json!({"op": "capture", "url": "https://a.test/"}));
    lib.ok(json!({"op": "saveNote", "id": 1, "notes": "a".repeat(65536)}));
    assert_eq!(lib.ok(json!({"op": "note", "id": 1}))["notes"].as_str().unwrap().len(), 65536);
    assert_eq!(lib.refused(json!({"op": "saveNote", "id": 1, "notes": "a".repeat(65537)})), "Invalid note.");
    assert_eq!(lib.refused(json!({"op": "saveNote", "id": 1, "notes": "é".repeat(32769)})), "Invalid note.");
    assert_eq!(lib.refused(json!({"op": "saveNote", "id": 1, "notes": "\u{1}".repeat(60000)})), "Message too large.");
    assert_eq!(lib.refused(json!({"op": "renameBookmark", "id": 1, "title": "é".repeat(2049)})), "Invalid title.");
    assert_eq!(lib.refused(json!({"op": "createFolder", "name": "é".repeat(129)})), "Invalid folder.");
    lib.ok(json!({"op": "createFolder", "name": "é".repeat(128)}));
}

#[test]
fn a_stalled_sender_times_out() {
    let lib = Lib::new("stall");
    let mut child = lib.command("--qml").spawn().unwrap();
    let start = Instant::now();
    let stdin = child.stdin.take().unwrap(); // Held open, sending nothing.
    let out = child.wait_with_output().unwrap();
    drop(stdin);
    assert_eq!(out.stdout, br#"{"ok":false,"error":"Request timed out."}"#);
    assert!((Duration::from_millis(2900)..Duration::from_secs(5)).contains(&start.elapsed()));
}

#[test]
fn writers_wait_on_the_same_lock_node_used() {
    let lib = Lib::new("lock");
    lib.ok(json!({"op": "capture", "url": "https://a.test/"}));
    let held = fs::File::open(lib.folder()).unwrap();
    flock(&held, FlockOperation::LockExclusive).unwrap();
    assert_eq!(lib.ok(json!({"op": "list"}))["all"], 1, "reads take no lock");
    let start = Instant::now();
    assert_eq!(lib.refused(json!({"op": "capture", "url": "https://b.test/"})), "Library is busy. Your draft is kept; retry.");
    assert!(start.elapsed() >= Duration::from_millis(2900));
    drop(held);
    assert_eq!(lib.ok(json!({"op": "capture", "url": "https://b.test/"}))["added"], true);
}

#[test]
fn parallel_captures_all_land() {
    let lib = Lib::new("parallel");
    lib.ok(json!({"op": "capture", "url": "https://first.test/"}));
    lib.ok(json!({"op": "saveNote", "id": 1, "notes": "kept"}));
    let mut children = Vec::new();
    for n in 0..16 {
        let mut child = lib.command("--qml").spawn().unwrap();
        let request = json!({"op": "capture", "url": format!("https://concurrent.test/{}", n % 8)});
        child.stdin.take().unwrap().write_all(request.to_string().as_bytes()).unwrap();
        children.push(child);
    }
    for child in children {
        let out = child.wait_with_output().unwrap();
        assert_eq!(serde_json::from_slice::<Value>(&out.stdout).unwrap()["ok"], true);
    }
    assert_eq!(lib.ok(json!({"op": "list"}))["all"], 9);
    assert_eq!(lib.ok(json!({"op": "note", "id": 1}))["notes"], "kept");
    assert_eq!(lib.db().query_row("PRAGMA integrity_check", [], |r| r.get::<_, String>(0)).unwrap(), "ok");
}

#[test]
fn the_binary_stands_alone() {
    let out = Command::new("/usr/bin/ldd").arg(HELPER).output().unwrap();
    assert!(String::from_utf8_lossy(&out.stdout).contains("statically linked"), "{out:?}");
}

// cargo test --release -- --ignored --nocapture
#[test]
#[ignore]
fn benchmark_ten_thousand_bookmarks() {
    let lib = Lib::new("bench");
    lib.ok(json!({"op": "capture", "url": "https://first.test/"}));
    let icon = png(32, 6, &[9, 8, 7, 255]);
    let mut noisy = icon.clone();
    noisy.resize(4196, 7);
    let mut db = lib.db();
    let tx = db.transaction().unwrap();
    for n in 0..10_000 {
        tx.execute(
            "INSERT INTO bookmarks(url,title,notes,favicon,createdAt,updatedAt) VALUES(?,?,?,?,1,1)",
            params![format!("https://example.com/{n}"), format!("Bookmark {n}"), format!("Note for bookmark {n}"), noisy],
        )
        .unwrap();
    }
    tx.commit().unwrap();
    drop(db);
    let time = |make: &dyn Fn(usize) -> Value| {
        let mut runs: Vec<Duration> = (0..15)
            .map(|n| {
                let request = make(n);
                let start = Instant::now();
                let reply = lib.call(request);
                let took = start.elapsed();
                assert_eq!(reply["ok"], true);
                took
            })
            .collect();
        runs.sort();
        runs[7]
    };
    println!("library {:.1} MiB", fs::metadata(lib.file()).unwrap().len() as f64 / 1048576.0);
    println!("list   {:?}", time(&|_| json!({"op": "list"})));
    println!("search {:?}", time(&|_| json!({"op": "list", "query": "bookmark 99"})));
    println!("save   {:?}", time(&|n| json!({"op": "capture", "url": format!("https://bench.test/{n}"), "title": "Bench"})));
}
