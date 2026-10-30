# Omakeep

Local bookmarks, notes and folders for Omarchy. Save a page from Chromium/Chrome, keep browsing, and edit it later in a native window.

QML, plain JavaScript and SQLite, with one small Rust helper. No Node, Python, npm packages, HTTP server or persistent helper process. The helper is a single static binary kept in the repo at `bin/omakeep-helper`, so using Omakeep needs no Rust and no install step beyond setup.

## Local setup

Requires Omarchy Quattro on x86_64. Setup uses `jq`, `base64` and `sha256sum`, and browser saves use `notify-send`; Omarchy ships all of them. Nothing else is needed at run time. Setup does not install packages or download anything.

From this checkout:

```sh
./setup.sh install chromium
omarchy shell shell rescanPlugins
omarchy plugin enable omakeep --section right
./setup.sh shortcut
```

Use `google-chrome` instead of `chromium` for Google Chrome. Registration applies to that browser's normal user-data directory. Custom `--user-data-dir` installations need their own native-host registration.

In that browser, open `chrome://extensions`, enable **Developer mode**, choose **Load unpacked**, and select this checkout's `extension` directory. Pin Omakeep's toolbar button so its success/error badge is visible. Its stable extension ID is `lefgnegnkcnkapehnnkfnkmdfiaahnmf`.

**Alt+Shift+K** saves the active page. Change that shortcut at `chrome://extensions/shortcuts` if necessary. **Super+Shift+K** opens Omakeep; setup refuses to replace an existing binding. The global shortcut is optional; the bar icon also opens the library.

Keep the checkout in place: setup links the plugin to it, and the browser registration holds the absolute path of `bin/omakeep-helper`. After moving the checkout, remove the old setup and run setup again. `./setup.sh prepare` only checks that the helper runs and prints the extension ID and folder.

To change the helper, edit `src/`, then run `./build.sh`. That is the only step that needs Rust. It uses the pinned toolchain through mise when mise is there, otherwise your `cargo`, and keeps build output outside the plugin folder because the shell reloads on any change inside it.

After editing QML, check the running window: this Omarchy version can retain old components even after `rescanPlugins`. If it does, let pending edits finish, run `omarchy restart shell`, then reopen Omakeep. This restarts the shared desktop shell.

## Using it

- Capture saves the URL, page title and an available favicon under **All**, with no folder. Success appears only after durable storage. The Omakeep window stays closed and browser focus stays put.
- Capturing the same URL reports **Already saved** and preserves its title, notes and folder. Query strings and fragments are significant.
- Open Omakeep later. Click anywhere on a row to open the page, or use **Note**, **Move** and the **⋮** menu, which every row always shows. Right-click a row, a folder or the empty list for its menu. Drag a bookmark onto a folder to move it, then **Undo** in the toast if you need to. Dragging is off below 760 pixels, where the sidebar is gone.
- Notes save after a short pause and when leaving the editor. A row with a note shows its first line. The sidebar shows how many bookmarks each folder holds.
- Add, rename and new folder all happen in place, with no popup. Adding a link you already saved says so and offers **Show it**.
- Long titles stay on one line, with the full title in a tooltip and in the open row.
- Failed saves retain the draft in the running window, including across searches and window hiding. Correct the issue and use **Retry**. An unsaved draft does not survive a shell crash/restart.
- Deleting a folder keeps its bookmarks and notes in All. Bookmark and folder deletion require confirmation.
- Search matches literal text in titles, URLs and notes within the current view. Manual add accepts a URL, an optional title and a folder; without a title, the hostname is used.

| Key | Action |
| --- | --- |
| Ctrl+F; `/` from a bookmark | Search |
| Down from search | Focus the first bookmark |
| Up / Down | Previous / next bookmark or folder |
| Enter on a bookmark | Open the page |
| Left | Collapse the note, then focus folders |
| Right | Enter the selected folder’s contents, or expand a bookmark’s note |
| F on a bookmark | Open folder picker; ↑/↓ chooses, Enter moves, Escape cancels |
| E on a bookmark | Expand its note and focus the editor |
| R on a bookmark or folder | Rename (title only for bookmarks) |
| D on a bookmark or folder | Confirm deletion; bookmarks include their notes, folders preserve their contents in All |
| Tab / Shift+Tab | Move between controls |
| Escape | Back out one step: rename, folder name, add, note, search, then close |
| Ctrl+N | Add a bookmark |
| Ctrl+Shift+N | Create a folder |
| `?` from a bookmark | Show shortcuts |

## Storage and boundaries

Data lives in `$XDG_DATA_HOME/omakeep/bookmarks.sqlite`, normally `~/.local/share/omakeep/bookmarks.sqlite`, outside the plugin checkout. It contains URLs, titles, plain-text notes, folders and cached PNG favicons. There are no accounts, sync services or background page requests. Chrome's built-in favicon resource is optional; failure uses a generic icon.

The helper reads a bounded SQLite snapshot through a validated, non-symlink file descriptor, loads it into SQLite in memory, then publishes writes with a private temporary file, fsync and atomic rename. A kernel `flock` on the held directory descriptor serializes writers. The file format is plain SQLite and the same one earlier versions wrote. SQLite never reopens the untrusted database pathname or creates disk journals. Parent directories are walked through held descriptors. Owner, permissions, regular-file type, link count and size are checked; unsafe existing files are refused.

This deliberately rewrites the snapshot on each mutation. The library is capped at **64 MiB**, folders at **200**, pending note drafts at **100**, and each request/response at **256 KiB**. Notes accept **64 KiB of UTF-8**, titles 4 KiB, URLs 16 KiB and folder names 256 bytes. Favicons are bounded PNGs, at most 16 KiB and 64×64 pixels. Lists are paged at 100 items or the response byte budget, whichever comes first. The list loads the next page by itself as you scroll near the end.

Measured on the development machine with 10,000 bookmarks, 4,196-byte PNGs and a 44.3 MiB database: median cold **capture 25 ms**, **search 13 ms**, across fifteen separate helper runs each. On a real GPU with 3,000 bookmarks, a keystroke shows its results in about 20 ms, a reopened panel draws in about 6 ms, and rows move at the display's refresh rate. Run the benchmark below for your machine. Larger libraries would need a different descriptor-safe storage approach; no custom SQLite VFS is included.

The extension requests only `activeTab`, `nativeMessaging` and `favicon`. Its native-host mode permits capture only; it cannot invoke editing/deletion operations, choose a folder, or supply executable commands or filesystem paths. UI/helper communication uses bounded JSON on stdin/stdout. Production input is rendered as plain text; URLs must be HTTP(S), without credentials or control characters.

## Verification

```sh
./test.sh
```

That runs everything on throwaway data: `cargo test` for the helper, `tests/setup.test.sh` for setup and removal, `tests/run-js.sh` for the browser worker and `State.js` in headless Chromium, `tests/run-ui.sh` for the panel, `tests/lint.sh` for `qmllint`, then `omarchy plugin validate .`.

`run-ui.sh` copies the installed Omarchy controls and the plugin UI into a disposable offscreen Quickshell with an isolated library. It uses real keys and a real mouse through capture, notes, autosave and retry, folders, menus, drag and drop, confirmations, odd rows, failed pages, narrow widths and reopening. It does not restart the real shell. The usual Qt test runner cannot load this installation's statically linked Quickshell plugins, so the check runs in Quickshell itself.

For timings, run `cargo test --release --locked --test helper -- --ignored --nocapture`.

The browser worker tests use controlled Chrome API responses. They do **not** replace a live check: load the unpacked extension, save a page, confirm its title/favicon in Omakeep, edit its note, close Chrome, and reopen the library. Repeat capture while an existing note has unsaved edits. Live favicon access and Chrome's native-host registration must be checked in the browser.

## Removal

First remove Omakeep from `chrome://extensions`, then run from this checkout:

```sh
./setup.sh unshortcut
omarchy plugin disable omakeep
./setup.sh remove chromium
omarchy shell shell rescanPlugins
```

Use the same browser argument used during installation. Removal checks ownership before deleting the plugin link and native-host registration. It removes only the exact marked shortcut block and retains other bindings. The source checkout, bookmark library and shortcut backups under `~/.local/state/omakeep-backups` remain. No daemon, timer, credentials or packages need removal. For a later regular marketplace installation, the corresponding plugin removal command is `omarchy plugin remove omakeep`; this development setup uses a checkout link instead.

The UI follows [Omamail](https://github.com/huacnlee/omamail)'s native layout/theming patterns. Browser capture follows Omarchy's installed Copy URL extension. See [BUILD_PLAN.md](BUILD_PLAN.md) for scope and remaining verification.
