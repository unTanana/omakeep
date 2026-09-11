# Omakeep

Local bookmarks, notes and folders for Omarchy. Save a page from Chromium/Chrome, keep browsing, and edit it later in a native window.

Plain JavaScript, QML and SQLite. No Python, npm packages, build step, HTTP server or persistent helper process.

## Local setup

Requires Omarchy Quattro, Node **26.1+** with SQLite serialization (tested with 26.7.0), and Omarchy's installed `flock`, `timeout` and `notify-send`. Setup resolves the current Node executable; it does not install packages or download a runtime.

From this checkout:

```sh
node setup.mjs install chromium
omarchy shell shell rescanPlugins
omarchy plugin enable omakeep --section right
node setup.mjs shortcut
```

Use `google-chrome` instead of `chromium` for Google Chrome. Registration applies to that browser's normal user-data directory. Custom `--user-data-dir` installations need their own native-host registration.

In that browser, open `chrome://extensions`, enable **Developer mode**, choose **Load unpacked**, and select this checkout's `extension` directory. Pin Omakeep's toolbar button so its success/error badge is visible. Its stable extension ID is `lefgnegnkcnkapehnnkfnkmdfiaahnmf`.

**Alt+Shift+K** saves the active page. Change that shortcut at `chrome://extensions/shortcuts` if necessary. **Super+Shift+K** opens Omakeep; setup refuses to replace an existing binding. The global shortcut is optional; the bar icon also opens the library.

Keep the checkout in place: setup links the plugin to it and generates `run-helper` and `native-host` launchers with absolute paths. After moving the checkout or changing Node installations, remove the old setup and run setup again. `node setup.mjs prepare` creates only the local helper launcher for development.

After editing QML, check the running window: this Omarchy version can retain old components even after `rescanPlugins`. If it does, let pending edits finish, run `omarchy restart shell`, then reopen Omakeep. This restarts the shared desktop shell.

## Using it

- Capture saves the URL, page title and an available favicon under **All**, with no folder. Success appears only after durable storage. The Omakeep window stays closed and browser focus stays put.
- Capturing the same URL reports **Already saved** and preserves its title, notes and folder. Query strings and fragments are significant.
- Open Omakeep later, expand the note and type. Notes save after a short pause and when leaving the editor. Choose a folder below the note. **More** contains Copy link, Rename bookmark and Delete bookmark.
- Failed saves retain the draft in the running window, including across searches and window hiding. Correct the issue and use **Retry**. An unsaved draft does not survive a shell crash/restart.
- Deleting a folder keeps its bookmarks and notes in All. Bookmark and folder deletion require confirmation.
- Search matches literal text in titles, URLs and notes within the current view. Manual add accepts a URL and optional title; without one, the hostname is used.

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
| Escape | Return from editing, dismiss a dialog, then close |
| Ctrl+N | Add a bookmark |
| Ctrl+Shift+N | Create a folder |
| `?` from a bookmark | Show shortcuts |

## Storage and boundaries

Data lives in `$XDG_DATA_HOME/omakeep/bookmarks.sqlite`, normally `~/.local/share/omakeep/bookmarks.sqlite`, outside the plugin checkout. It contains URLs, titles, plain-text notes, folders and cached PNG favicons. There are no accounts, sync services or background page requests. Chrome's built-in favicon resource is optional; failure uses a generic icon.

The helper reads a bounded SQLite snapshot through a validated, non-symlink file descriptor, uses Node's in-memory SQLite API, then publishes writes with a private temporary file, fsync and atomic rename. A kernel `flock` on the held directory descriptor serializes writers. SQLite never reopens the untrusted database pathname or creates disk journals. Parent directories are walked through held descriptors. Owner, permissions, regular-file type, link count and size are checked; unsafe existing files are refused.

This deliberately rewrites the snapshot on each mutation. The library is capped at **64 MiB**, folders at **200**, pending note drafts at **100**, and each request/response at **256 KiB**. Notes accept **64 KiB of UTF-8**, titles 4 KiB, URLs 16 KiB and folder names 256 bytes. Favicons are bounded PNGs, at most 16 KiB and 64×64 pixels. Lists are paged at 100 items or the response byte budget, whichever comes first. The UI shows Load more for another page.

Measured on the development machine with 10,000 bookmarks, 4,196-byte PNGs and a 44.3 MiB database: median cold **capture 54 ms**, **search 39 ms**, across seven separate helper invocations each. Run the benchmark below for your machine. Larger libraries would need a different descriptor-safe storage approach; no custom SQLite VFS is included.

The extension requests only `activeTab`, `nativeMessaging` and `favicon`. Its native-host mode permits capture only; it cannot invoke editing/deletion operations or supply executable commands or filesystem paths. UI/helper communication uses bounded JSON on stdin/stdout. Production input is rendered as plain text; URLs must be HTTP(S), without credentials or control characters.

## Verification

```sh
node setup.mjs prepare
node --test
node tests/run-ui.mjs
node tests/benchmark.mjs
node tests/lint.mjs
omarchy plugin validate .
```

`run-ui.mjs` copies the actual installed Omarchy controls and plugin UI into a disposable Quickshell configuration, uses an isolated database, exercises keyboard navigation, autosave/retry, collapse, reopening and folder preservation, and renders wide/narrow/light screenshots. It does not restart the real shell. The usual Qt test runner cannot load this installation's statically linked Quickshell plugins, so the check runs in Quickshell itself.

Browser worker tests use controlled Chrome API responses. They do **not** replace live verification: load the unpacked extension, save a page, confirm its title/favicon in Omakeep, edit its note, close Chrome, and reopen the library. Repeat capture while an existing note has unsaved edits. Live favicon access and Chrome's native-host registration must be checked in the browser.

## Removal

First remove Omakeep from `chrome://extensions`, then run from this checkout:

```sh
node setup.mjs unshortcut
omarchy plugin disable omakeep
node setup.mjs remove chromium
omarchy shell shell rescanPlugins
```

Use the same browser argument used during installation. Removal checks ownership before deleting the plugin link, native-host registration and generated launchers. It removes only the exact marked shortcut block and retains other bindings. The source checkout, bookmark library and shortcut backups under `~/.local/state/omakeep-backups` remain. No daemon, timer, credentials or packages need removal. For a later regular marketplace installation, the corresponding plugin removal command is `omarchy plugin remove omakeep`; this development setup uses a checkout link instead.

The UI follows [Omamail](https://github.com/huacnlee/omamail)'s native layout/theming patterns. Browser capture follows Omarchy's installed Copy URL extension. See [BUILD_PLAN.md](BUILD_PLAN.md) for scope and remaining verification.
