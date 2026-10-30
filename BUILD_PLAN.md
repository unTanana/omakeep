# Omakeep build plan

Status: first implementation built and installed locally on 2026-09-11. Rebuilt on 2026-10-30 with the approved changes: the Node helper is replaced by one static Rust binary, setup is a bash script, and the panel has the new UI. The library file and the browser extension ID did not change. See "Implementation evidence" for what passed and what still needs a person. This is not a security certification.

## Objective

Build a local Omarchy bookmark library with notes and folders, accessible while Chrome is closed. Use Omamail as the UI reference. Use QML, plain JavaScript and SQLite, plus one small static Rust helper, with no Python, Node or npm dependencies. The helper binary is kept in the repo, so only changing it needs Rust.

## User flow

1. Click the Chrome extension button or use its configurable browser shortcut, following Omarchy's Copy URL extension pattern. This capture shortcut is separate from the global shortcut that opens the library.
2. Save the active page's URL and page title, with its favicon when available. New captures have no folder and appear in All.
3. Show "Saved to Omakeep" only after the database commits, without opening Omakeep or changing focus. Keep browsing; capture requires no editing step.
4. Open the library later through the Omarchy bar or its global shortcut. Open a bookmark's note to write in it, or move it with Move, its menu or a drag onto a folder; changes save automatically. Click a row or press Enter on it to open its page in the default browser.

Capturing an existing URL reports "Already saved" without overwriting its title, notes or folder or changing the UI selection. Capture works even when the Omakeep window or Omarchy shell is unavailable. Incoming captures never replace pending note edits or steal focus from an active note editor. Captured bookmarks are loaded when the library is next opened.

## First version

- Bookmarks: add manually or from Chrome, edit notes, move to a folder, open, copy and delete with confirmation. Chrome supplies the page title as the item title. A manually pasted URL accepts an optional title, falling back to its hostname; it does not trigger page scraping.
- Favicons: show the saved page favicon immediately to the left of its title. Capture a small raster icon from Chrome when available and store it locally. Missing or invalid icons use a generic fallback; icon failure never prevents saving a valid bookmark.
- Folders: create, rename and delete top-level folders. Each bookmark belongs to one folder or has no folder. Deleting a folder clears its bookmarks' folder assignment in the same transaction, preserving their notes and keeping them in All.
- Views: All at the top of the sidebar, followed directly by user folders, each with its bookmark count; newest bookmarks first. No Inbox view or section headings.
- Search: literal substring search across title, URL and notes, scoped to the selected view. Results are paged; scrolling near the end loads the next page.
- Notes: expand a bookmark to reveal its plain-text note editor in the list. Markdown syntax can be stored, but is not rendered. Collapsed rows show the favicon, a one-line title, the site, Note / Move / menu buttons and the note's first line. There is no separate detail pane.
- Editing: save notes automatically after a short typing pause, and flush pending edits on leaving the editor, collapsing the item or hiding the window. Show Saved only after the database acknowledges the current draft; retain drafts and offer Retry on failure. No routine Save button or Save/Discard/Cancel prompt. Saved data survives browser and shell restarts; unsaved crash recovery remains outside this version.
- Keyboard: the global shortcut opens the library with search focused; Ctrl+F or `/` focuses search, Down enters the list, Up/Down moves between items, and Enter on an item opens its page. Right expands its note while keeping focus on the item; Left collapses it, then moves focus to folders. Up/Down switches folders and Right enters the selected folder’s contents, including empty folders. R renames the focused bookmark or folder in place, prefilled; bookmark rename changes only the title. D asks for confirmation before deleting the focused bookmark and its note, or the focused folder. All cannot be renamed or deleted. F opens the selected bookmark’s folder picker directly; Up/Down highlights a folder, Enter moves the bookmark and note, and Escape cancels. Closing the picker returns focus to the bookmark. E expands the selected bookmark’s note and focuses its editor once loaded; moving elsewhere cancels the pending focus. Tab reaches the editor and other controls. Escape returns from editing to the item, then dismisses transient UI before closing the window. Ctrl+N adds a bookmark; Ctrl+Shift+N creates a folder; `?` shows shortcuts. Bare shortcuts never override normal text editing.

## UI reference

The accepted interaction design is specified below. Production saves bookmarks and notes to SQLite.

Follow Omamail's native window, compact toolbar, thin dividers and theme typography, with a sidebar and one bookmark list. Use Omarchy's `qs.Ui` controls and `qs.Commons` theme values; inherit semantic colours instead of hard-coding a palette. Use native Qt list virtualization and input controls. At narrow widths, replace the sidebar with a folder picker and keep notes expanding within the list.

| Region | Contents |
| --- | --- |
| Toolbar | Search, Add bookmark, Shortcuts and Close |
| Sidebar | All, user folders with counts directly underneath, New folder pinned at the bottom, with Sort with AI under it while bookmarks have no folder |
| List header | Current view name and count; Rename and Delete only when a user folder is selected |
| Row | Favicon, one-line title, site and folder, Note / Move / menu always visible, note preview |
| Open row | Full title and link, note editor, save state, Open page, folder, Copy link, Rename, Delete |
| Footer | Only while scrolling: Loading more, or a failed page with Retry |

Clicking anywhere on a row opens the page and closes Omakeep; Note expands or collapses it. Expanding alone does not open the browser or move focus into the editor. Titles stay on one line with a tooltip and show in full in an open row; the row shows the full link on hover. Folder choices include No folder. Right-click gives a menu on rows, folders and the empty list. Drag a row onto a folder to move it, with Undo. Add, rename and new folder happen in place. Deleting a bookmark or folder requires confirmation. The approved mockup is kept outside this repo, in the omakeep-design folder.

Use visible focus, accessible names and tooltips for icon buttons. Every text sink carrying a title, folder, note or error explicitly uses plain text. Keep notifications generic where host-owned controls cannot guarantee plain-text rendering.

Reference implementations:

- [Omamail](https://github.com/huacnlee/omamail): window lifecycle, layout, theme and focus patterns. The installed reference is `~/.config/omarchy/plugins/omamail/`, especially `App.qml`, `BarWidget.qml` and `components/SearchBar.qml`.
- Omarchy's installed Copy URL extension and `omarchy-chromium-copy-url-host`: browser shortcut, native-messaging registration and save confirmation pattern. Reuse the integration pattern, with bounded messages and checked errors.
- [Nearby](https://github.com/jfg96/omarchy-nearby): QML/helper separation and JSON over stdin/stdout. Its Rust implementation and persistent network service are not needed here.
- [Browserpass](https://github.com/browserpass/browserpass-native): native-host packaging and browser registration.

Adapt only the necessary patterns; do not fork another application. Retain licence notices for any copied code.

## Implementation shape

| Part | Responsibility |
| --- | --- |
| `manifest.json`, `BarWidget.qml` | Plugin identity `omakeep`, bar entry and opening the window |
| `App.qml`, `Helper.qml`, `State.js` | Native window, bounded process I/O and draft state |
| `BookmarkRow.qml`, `FolderRow.qml`, `AddSheet.qml`, `FolderNameEditor.qml`, `Blank.qml` | The list, the sidebar and the in-place forms |
| `PopupMenu.qml`, `DialogLayer.qml`, `Toast.qml` | Menus and pickers, confirmations, and short messages with Undo |
| `KeepButton.qml`, `Label.qml`, `Glyph.qml`, `Field.qml`, `Favicon.qml`, `HighlightText.qml`, `WrappedText.qml`, `Icons.js` | Small shared pieces on top of the Omarchy controls |
| `src/main.rs`, `Cargo.toml`, `build.sh`, `bin/omakeep-helper` | The helper: validation, database operations and both protocol entry points |
| `extension/manifest.json`, `extension/background.js` | Manifest V3 capture button/shortcut and save feedback |
| `tests/helper.rs`, `tests/setup.test.sh`, `tests/js.html`, `tests/qml/tst_ui.qml`, `test.sh` | `cargo test`, shell, headless Chromium and offscreen Quickshell checks |
| `setup.sh`, `README.md` | Explicit local setup/removal and runtime documentation |

Start with these boundaries. Split the helper only if the actual code becomes difficult to read. No repository layer, plugin framework, generic transport abstraction or separate settings system.

The helper is one static binary with SQLite compiled in, so nothing on the system can break it except deleting the file. It takes the write lock with `flock(2)` directly and bounds its own lifetime at eight seconds. The binary is tracked as a plain file; `./build.sh` rebuilds it from `src/` with pinned dependencies. The move from Node, and why Rust over C, is written up in the port report kept with the mockup.

Both QML and Chrome invoke the same short-lived helper. QML sends bounded JSON through stdin; Chrome uses its length-prefixed native-messaging protocol. Both adapters call the same operation functions. QML starts processes asynchronously; synchronous SQLite work runs in the helper, outside the shell's UI thread. The helper exits after responding. No HTTP listener, daemon, polling loop or background process.

Use the shell's existing `keepLoaded` panel support to preserve in-session UI state. No separate `Service.qml` is needed initially. Reload data on open and completed mutations without replacing pending drafts or resetting focus. Capture does not open or refresh the panel; no capture-to-panel IPC is needed. Ignore stale search responses and keep at most one running search plus the latest pending query, so fast typing cannot queue up work and a search needs no timer.

Keep pending notes keyed by bookmark ID outside disposable list delegates. Start with a 350 ms debounce and one outstanding UI mutation; coalesce queued note writes to the latest draft for each bookmark. An acknowledgement clears only the draft it saved, so an older response cannot mark newer typing as saved. Folder changes persist immediately through the same queue; note and folder writes each update only their own fields. Deleting a bookmark cancels its queued note writes and runs after any outstanding write. Navigation and window hiding flush pending work while retaining drafts in the loaded panel. On failure, keep a visible unsaved/error indication, including on collapsed rows, and a Retry action across views; do not add an automatic retry loop.

Retrieve the optional favicon through Chrome's built-in [`_favicon` resource](https://developer.chrome.com/docs/extensions/how-to/ui/favicons), requesting a 32 px image with the `favicon` permission. Verify access from the extension's capture context early. Bound retrieval time and size; a failure or unavailable icon falls back to the generic icon. Pass PNG bytes with the capture, store them with the bookmark, and render locally. No website crawler, third-party favicon service, icon-refresh task or icon-fetching process in the native UI is needed.

### Storage

Store the library at `$XDG_DATA_HOME/omakeep/bookmarks.sqlite`, falling back to `~/.local/share/omakeep/bookmarks.sqlite`. Keep data outside the plugin checkout so updates and removal preserve it.

- `folders`: integer ID and unique non-empty name.
- `bookmarks`: integer ID, unique URL, title, notes, nullable folder ID, optional favicon PNG blob and creation/update timestamps. All is a view over every bookmark, not a stored folder.
- Enable foreign keys; folder deletion uses `ON DELETE SET NULL`. Use parameterized statements and constraints; serialize concurrent writers with the bounded `flock` wait below.
- Resolve the file-opening boundary with a bounded SQLite snapshot: read once through a validated descriptor, deserialize into an in-memory database, then serialize and atomically publish mutations through an exclusive temporary file with file/directory fsync. SQLite never opens the database pathname or disk journals. Hold a directory descriptor throughout; system `flock` locks that open-file description before reading a mutation's snapshot and retains the lock until publication finishes. Reads see an atomic snapshot. The library cap is 64 MiB; this deliberately rewrites the snapshot per mutation, with a `ponytail:` comment naming the ceiling and upgrade path.
- Cap folders at 200 and pending note drafts at 100. Reject creation beyond the folder limit; require resolving pending notes before expanding another editor at the draft limit. Save failures retain the current text for correction and Retry.
- Keep the supplied URL's query and fragment intact. Trim surrounding whitespace; do not invent URL canonicalization. Duplicate capture returns the existing record instead of merging or overwriting it.
- Fetch list rows, including their small cached icons, in pages of at most 100, stopping earlier at the response byte budget and returning a continuation cursor. Bound folder results too. Load full notes only when an item expands, preferring any pending local draft over stored text. Start with ordinary SQL search; mark its linear-scan ceiling with a `ponytail:` comment and add full-text indexing only when measurements justify it.

### Trust boundaries

Apply the installed `omarchy-plugin-security` skill to the real implementation. These are the relevant requirements for this scope:

- Capture only on the extension's explicit button/shortcut action, using `activeTab`, `nativeMessaging` and `favicon`. Use a stable extension ID and exact `allowed_origins`. No content script or blanket browsing permissions are necessary. See [Chrome native messaging](https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging).
- Native-host mode exposes capture only; browser payloads cannot request arbitrary SQL, filesystem paths, commands or destructive library operations. QML's separate entry mode owns editing operations.
- Validate types, allowed operations, IDs and lengths in the helper. Accept HTTP/HTTPS URLs with a host; reject embedded credentials and control characters. Local website URLs can be saved because the native helper does not fetch pages or favicon URLs.
- Treat icon bytes as untrusted: accept only bounded base64 PNG data, at most 16 KiB decoded and 64 × 64 pixels, with checked encoding, PNG signature and dimensions. Invalid icons fall back without rejecting the bookmark. Never pass browser-supplied image URLs, SVG or filesystem paths to QML; serve only stored raster data. Include icons in all request/response byte budgets.
- Bound native-message lengths before allocating payloads, reject malformed/truncated frames, and enforce a request deadline. Initial limits: URL 16 KiB, title 4 KiB, folder name 256 bytes, notes 64 KiB, request/response 256 KiB. Reject oversized input rather than silently trimming it.
- Bound stdout/stderr at the producer and in QML before assembling a response; validate the response shape before updating models. Fetch oversized lists through pagination. Cancel superseded reads, serialize UI mutations and retain drafts until a successful commit is acknowledged.
- Invoke fixed executables with argument arrays; pass notes and URLs through stdin. Do not interpolate data into shell commands. The panel and the browser both call the helper directly, with no launcher, so it depends on no shell setup or inherited environment.
- Create private storage with owner-only permissions. Review database, parent-directory and journal-file handling together. Test symlinks, non-regular files and permission failures. A pathname check followed by `DatabaseSync(path)` is not proof of race-safe access.
- The SQLite pathname boundary is resolved by the descriptor-read/in-memory-snapshot approach above. Keep regression checks for unsafe files, symlinked parents, simultaneous writers and preservation after reopen; no custom SQLite VFS is needed.
- A read must never be stricter than the old one: one bad stored row or folder drops alone and can never blank the list. `tests/fixtures` and the panel test both cover this.
- The native helper commits before acknowledging capture; confirmation failure must not undo or misreport the committed bookmark. Capture does not request a bookmark-reveal UI handoff, and pending note drafts survive another bookmark being captured.

## Ordered work and acceptance checks

1. **Helper and storage.** Implement schema, operations and both protocol adapters. Leave one focused runnable test file covering persistence after reopen, repeated/concurrent captures, preservation of notes/folders, folder deletion, literal search, optional icon validation/persistence, bounds, malformed frames and hostile file paths. Measure cold helper startup and save/search latency with a synthetic 10,000-bookmark library, including icons in paginated response budgets. Aim for sub-200 ms helper save/search operations on this machine; record actual results before optimizing. Resolve the file-opening boundary before accepting storage as complete; independent UI work can proceed while that is investigated.
2. **Native UI.** Build the accepted sidebar/list design, inline notes, folder management, search and keyboard access. Check favicon/title placement, intact page titles, Enter opening the focused page, Right/Left expanding/collapsing without opening, Left reaching folders, Up/Down switching them, Right entering their contents during loading or when empty, R renaming, D confirming deletion, cancellation preserving data, and normal typing inside notes. Verify narrow/wide windows, light/dark themes and empty/error states. Exercise autosave during continued typing, item collapse, filtering, folder changes, delegate recycling and window hiding; delayed acknowledgements must not clear newer drafts. Test a failed write and Retry, duplicate capture during editing, and deleting a bookmark with queued writes. Deleting a folder preserves bookmarks and notes. Only acknowledged current drafts display Saved.
3. **Browser capture.** Implement the Manifest V3 button and configurable shortcut; reuse the helper's capture function. Verify captured page titles, favicon access, missing/invalid/slow icons, new and duplicate URLs, success/error feedback, a missing host, a disabled plugin and a closed shell. Only committed captures display success; icon failure does not block a bookmark. Confirm that capture leaves Chrome focused, keeps a closed Omakeep window closed, and preserves selection and pending note edits in an already open library. Open the library afterwards and verify the saved bookmark appears in All, can be edited, and retains its icon with Chrome closed and networking unavailable.
4. **Explicit local setup.** Register the plugin and native host for the browser/profile actually used. Load the extension unpacked; document any browser UI action that must be done manually. Add a conflict-free global shortcut during setup, with a backup outside automatically scanned directories and validation of changed Hyprland config. Loading the plugin performs no installation, downloads or shared-config edits.
5. **Final verification and documentation.** Run `./test.sh`, which covers `cargo test`, `/usr/lib/qt6/bin/qmllint` against the actual Omarchy imports, and `omarchy plugin validate .`. Perform the complete flow: capture a page with its title/favicon using the browser shortcut, receive confirmation while remaining in Chrome, open Omakeep later, expand the bookmark, write a note, verify autosave, choose a folder, close Chrome, reopen Omakeep, search and press Enter to open the bookmark. Restart the shell and confirm committed notes, folder assignments and icons survive. Exercise removal on a disposable setup: remove only owned registration/config entries, leave the library intact, and ensure no helper remains running. Document supported runtime, data paths, setup, removal, limits and measured performance.

Use focused QML interaction checks where they catch an actual regression; do not copy Omamail's full test harness. Run the marketplace baseline and review the exact distributable tree only if marketplace submission is later requested. Passing that scanner is not a substitute for the boundary checks above.

## Deliberate omissions

No nested folders, tags, sync, accounts, page archiving, page previews, Markdown rendering, import/export, AI features or store publication. No Inbox view, separate detail pane, URL editor, manual Save workflow, website scraping or background favicon refresh. No speculative abstractions or unused dependencies. Add a feature when the user asks for it or a measured limit requires it.

## Implementation evidence and remaining checks

Results of the 2026-10-30 rebuild. All of it ran on throwaway data.

- `cargo test`: unit and integration checks on the real binary covering persistence, duplicate and concurrent capture, capture-only browser access, malformed and bounded frames, URLs, PNGs, unsafe file paths, the exact old schema, and odd old rows that must not blank a list.
- `tests/setup.test.sh`: disposable setup, removal, shortcut and ownership checks.
- `tests/run-js.sh`: browser worker and `State.js` in headless Chromium.
- `tests/run-ui.sh`: the real Omarchy controls in an offscreen Quickshell, driven by real keys and a real mouse, then a second fresh process confirming saved data survives. Qt's standalone test runner cannot load this installation's statically linked Quickshell plugins, so the check runs inside Quickshell.
- `tests/lint.sh` and `omarchy plugin validate .`: passed against installed imports and the actual plugin tree. The lint wrapper checks JSON results because qmllint's JSON mode can return zero while reporting diagnostics.
- Benchmark, ignored `cargo test` case: 10,000 bookmarks with 4,196-byte PNGs, 44.3 MiB. Median of fifteen cold helper runs: list 12 ms, search 13 ms, capture 25 ms. The Node helper measured 39 ms search and 54 ms capture on the same library.
- 31 and 3,000 bookmarks in the panel on the real GPU (RTX 4090, 4K at 120 Hz, in a private headless gamescope, so times include up to two frames of waiting to present). First open with rows on screen 70 to 80 ms, reopen 6 ms, keystroke to results 21 ms, folder switch 14 to 21 ms, note open 25 ms, wheel and scrollbar a median of 9 to 10 ms a frame and worst about 20 ms. Closed, the panel made no CPU wake-ups at all.
- Sort with AI on a copy of the real library, 33 bookmarks and no folders, Claude on a subscription. Agent startup alone is about 1.5 s, and Claude's background traffic added 1 to 4 s more, so it is switched off for this one call. Replying per folder instead of per bookmark cut the answer from about 830 to about 170 bytes. Together: about 4 s down to about 2 s, with the same 25 of 33 filed. Trimming links and titles saved nothing and filed fewer. Haiku took 5.4 to 6 s, so Sonnet stays.
- Real Chromium with the unpacked extension, on a throwaway profile with the installed host registration: save, duplicate, title and favicon kept, every other operation refused, the extension ID unchanged.
- Remaining manual gate: the toolbar button and Alt+Shift+K pressed by a person, and the visual look on the real desktop. The panel's real Wayland window was only opened once, for a read check.

Live keyboard verification after restarting the shared Omarchy shell: Left/Down/Right folder navigation, bookmark/folder R rename, and bookmark/folder D confirmation all worked. Dialogs were canceled without modifying user data. A plugin rescan had retained the old QML components; a full shell restart loaded the current UI. Check the actual running window after future updates.

## Ponytail review

Reviewed again at full intensity for the accepted design: use one list with native disclosure controls, Chrome's favicon resource, a small inline PNG blob and one debounced mutation queue. Browser capture saves with confirmation; editing happens later, removing the need for capture-to-panel IPC. Reuse Omarchy/Qt controls, native messaging and SQLite constraints. Tests protect storage, trust boundaries and pending user edits. No additional scaffolding, service or dependency is approved by this plan.

Completion means the verified capture-to-library flow works with Chrome closed, the UI matches the accepted simple design within Omamail's native styling, Enter opens pages, inline notes save automatically, favicons remain available offline, data is preserved on failures/removal, and using Omakeep requires nothing beyond the checkout and its setup script.
