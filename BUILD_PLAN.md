# Omakeep build plan

Status: first implementation built and installed locally on 2026-09-11. The helper, UI, extension worker and setup/removal checks pass; QML lint and Omarchy manifest validation pass. The user confirmed successful capture from the unpacked Chromium extension. Live keyboard navigation and native clipboard copying are verified; remaining manual checks are listed below. Simplified design accepted on 2026-09-11; Ponytail full complexity review remains approved. This is not a security certification.

## Objective

Build a local Omarchy bookmark library with notes and folders, accessible while Chrome is closed. Use Omamail as the UI reference. Use QML, plain JavaScript and SQLite, with no Python, Rust, build step or npm dependencies.

## User flow

1. Click the Chrome extension button or use its configurable browser shortcut, following Omarchy's Copy URL extension pattern. This capture shortcut is separate from the global shortcut that opens the library.
2. Save the active page's URL and page title, with its favicon when available. New captures have no folder and appear in All.
3. Show "Saved to Omakeep" only after the database commits, without opening Omakeep or changing focus. Keep browsing; capture requires no editing step.
4. Open the library later through the Omarchy bar or its global shortcut. Expand the bookmark to write a note or choose a folder; changes save automatically. Press Enter on a bookmark to open its page in the default browser.

Capturing an existing URL reports "Already saved" without overwriting its title, notes or folder or changing the UI selection. Capture works even when the Omakeep window or Omarchy shell is unavailable. Incoming captures never replace pending note edits or steal focus from an active note editor. Captured bookmarks are loaded when the library is next opened.

## First version

- Bookmarks: add manually or from Chrome, edit notes, move to a folder, open, copy and delete with confirmation. Chrome supplies the page title as the item title. A manually pasted URL accepts an optional title, falling back to its hostname; it does not trigger page scraping.
- Favicons: show the saved page favicon immediately to the left of its title. Capture a small raster icon from Chrome when available and store it locally. Missing or invalid icons use a generic fallback; icon failure never prevents saving a valid bookmark.
- Folders: create, rename and delete top-level folders. Each bookmark belongs to one folder or has no folder. Deleting a folder clears its bookmarks' folder assignment in the same transaction, preserving their notes and keeping them in All.
- Views: All at the top of the sidebar, followed directly by user folders; newest bookmarks first. No Inbox view, section headings or counts.
- Search: literal substring search across title, URL and notes, scoped to the selected view. Debounce input and page results.
- Notes: expand a bookmark to reveal its plain-text note editor in the list. Markdown syntax can be stored, but is not rendered. Collapsed items show their favicon, page title and a Note / Add note disclosure, without a note excerpt or separate detail pane.
- Editing: save notes automatically after a short typing pause, and flush pending edits on leaving the editor, collapsing the item or hiding the window. Show Saved only after the database acknowledges the current draft; retain drafts and offer Retry on failure. No routine Save button or Save/Discard/Cancel prompt. Saved data survives browser and shell restarts; unsaved crash recovery remains outside this version.
- Keyboard: the global shortcut opens the library with search focused; Ctrl+F or `/` focuses search, Down enters the list, Up/Down moves between items, and Enter on an item opens its page. Right expands its note while keeping focus on the item; Left collapses it, then moves focus to folders. Up/Down switches folders and Right enters the selected folder’s contents, including empty folders. R opens a prefilled rename dialog for the focused bookmark or folder; bookmark rename changes only the title. D asks for confirmation before deleting the focused bookmark and its note, or the focused folder. All cannot be renamed or deleted. F opens the selected bookmark’s folder picker directly; Up/Down highlights a folder, Enter moves the bookmark and note, and Escape cancels. Closing the picker returns focus to the bookmark. E expands the selected bookmark’s note and focuses its editor once loaded; moving elsewhere cancels the pending focus. Tab reaches the editor and other controls. Escape returns from editing to the item, then dismisses transient UI before closing the window. Ctrl+N adds a bookmark; Ctrl+Shift+N creates a folder; `?` shows shortcuts. Bare shortcuts never override normal text editing.

## UI reference

The accepted interaction design is specified below. Production saves bookmarks and notes to SQLite.

Follow Omamail's native window, compact toolbar, thin dividers and theme typography, with a sidebar and one bookmark list. Use Omarchy's `qs.Ui` controls and `qs.Commons` theme values; inherit semantic colours instead of hard-coding a palette. Use native Qt list virtualization and input controls. At narrow widths, replace the sidebar with a folder picker and keep notes expanding within the list.

| Region | Contents |
| --- | --- |
| Toolbar | Search and Add bookmark |
| Sidebar | All, user folders directly underneath, New folder at the bottom |
| List header | Current view name; Folder options only when a user folder is selected |
| Collapsed item | Favicon on the left, page title as the open action, Note / Add note disclosure on the right |
| Expanded item | Note editor, save state, folder selector and More containing Copy link / Rename bookmark / Delete bookmark |
| Footer | Enter to open, Right/Left to expand/collapse, Shortcuts help |

Clicking the title opens the page; clicking the disclosure expands or collapses the note. Expanding alone does not open the browser or move focus into the editor. Keep page titles intact, wrapping when necessary; expose the full URL on hover/focus. Folder choices include No folder. Folder options contains rename/delete; deleting a bookmark or folder requires confirmation.

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
| `App.qml`, `BookmarkRow.qml`, `FolderPicker.qml`, `Helper.qml`, `State.js` | Native window, controls, bounded process I/O and draft state |
| `helper.mjs` | Shared validation, database operations and protocol entry points |
| `extension/manifest.json`, `extension/background.js` | Manifest V3 capture button/shortcut and save feedback |
| `tests/helper.test.mjs` | Focused checks with `node:test` and `node:assert` |
| `setup.mjs`, `README.md` | Explicit local setup/removal and runtime documentation |

Start with these boundaries. Split the helper only if the actual code becomes difficult to read. No repository layer, plugin framework, generic transport abstraction or separate settings system.

Use Node's built-in `node:sqlite`, `node:fs`, `node:child_process` and `URL`. Node 26.1+ is required for SQLite serialization/deserialization; the installed Node 26.7.0 passes the implementation checks. `node:sqlite` is currently a release-candidate API: setup checks the required API and pins the supported executable without downloading a runtime or substituting an npm database package. See [Node SQLite documentation](https://nodejs.org/api/sqlite.html). The installed system `flock` supplies the write lock and `timeout` bounds helper lifetime.

Both QML and Chrome invoke the same short-lived helper. QML sends bounded JSON through stdin; Chrome uses its length-prefixed native-messaging protocol. Both adapters call the same operation functions. QML starts processes asynchronously; synchronous SQLite work runs in the helper, outside the shell's UI thread. The helper exits after responding. No HTTP listener, daemon, polling loop or background Node process.

Use the shell's existing `keepLoaded` panel support to preserve in-session UI state. No separate `Service.qml` is needed initially. Reload data on open and completed mutations without replacing pending drafts or resetting focus. Capture does not open or refresh the panel; no capture-to-panel IPC is needed. Ignore stale search responses and keep at most one current search plus the latest pending query; never spawn a process for every keystroke.

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
- Invoke fixed executables with argument arrays; pass notes and URLs through stdin. Do not interpolate data into shell commands. Native-host setup must resolve a supported Node executable and avoid depending on interactive shell initialization or inherited `NODE_OPTIONS`.
- Create private storage with owner-only permissions. Review database, parent-directory and journal-file handling together. Test symlinks, non-regular files and permission failures. A pathname check followed by `DatabaseSync(path)` is not proof of race-safe access.
- The Node/SQLite pathname boundary is resolved by the descriptor-read/in-memory-snapshot approach above. Keep regression checks for unsafe files, symlinked parents, simultaneous writers and preservation after reopen; no custom SQLite VFS or language change is needed.
- The native helper commits before acknowledging capture; confirmation failure must not undo or misreport the committed bookmark. Capture does not request a bookmark-reveal UI handoff, and pending note drafts survive another bookmark being captured.

## Ordered work and acceptance checks

1. **Helper and storage.** Implement schema, operations and both protocol adapters. Leave one focused runnable test file covering persistence after reopen, repeated/concurrent captures, preservation of notes/folders, folder deletion, literal search, optional icon validation/persistence, bounds, malformed frames and hostile file paths. Measure cold helper startup and save/search latency with a synthetic 10,000-bookmark library, including icons in paginated response budgets. Aim for sub-200 ms helper save/search operations on this machine; record actual results before optimizing. Resolve the file-opening boundary before accepting storage as complete; independent UI work can proceed while that is investigated.
2. **Native UI.** Build the accepted sidebar/list design, inline notes, folder management, search and keyboard access. Check favicon/title placement, intact page titles, Enter opening the focused page, Right/Left expanding/collapsing without opening, Left reaching folders, Up/Down switching them, Right entering their contents during loading or when empty, R renaming, D confirming deletion, cancellation preserving data, and normal typing inside notes. Verify narrow/wide windows, light/dark themes and empty/error states. Exercise autosave during continued typing, item collapse, filtering, folder changes, delegate recycling and window hiding; delayed acknowledgements must not clear newer drafts. Test a failed write and Retry, duplicate capture during editing, and deleting a bookmark with queued writes. Deleting a folder preserves bookmarks and notes. Only acknowledged current drafts display Saved.
3. **Browser capture.** Implement the Manifest V3 button and configurable shortcut; reuse the helper's capture function. Verify captured page titles, favicon access, missing/invalid/slow icons, new and duplicate URLs, success/error feedback, a missing host, a disabled plugin and a closed shell. Only committed captures display success; icon failure does not block a bookmark. Confirm that capture leaves Chrome focused, keeps a closed Omakeep window closed, and preserves selection and pending note edits in an already open library. Open the library afterwards and verify the saved bookmark appears in All, can be edited, and retains its icon with Chrome closed and networking unavailable.
4. **Explicit local setup.** Register the plugin and native host for the browser/profile actually used. Resolve the Node executable during setup. Load the extension unpacked; document any browser UI action that must be done manually. Add a conflict-free global shortcut during setup, with a backup outside automatically scanned directories and validation of changed Hyprland config. Loading the plugin performs no installation, downloads or shared-config edits.
5. **Final verification and documentation.** Run `node --test`, `/usr/lib/qt6/bin/qmllint` against the actual Omarchy imports, and `omarchy plugin validate .`. Perform the complete flow: capture a page with its title/favicon using the browser shortcut, receive confirmation while remaining in Chrome, open Omakeep later, expand the bookmark, write a note, verify autosave, choose a folder, close Chrome, reopen Omakeep, search and press Enter to open the bookmark. Restart the shell and confirm committed notes, folder assignments and icons survive. Exercise removal on a disposable setup: remove only owned registration/config entries, leave the library intact, and ensure no helper remains running. Document supported runtime, data paths, setup, removal, limits and measured performance.

Use focused QML interaction checks where they catch an actual regression; do not copy Omamail's full test harness. Run the marketplace baseline and review the exact distributable tree only if marketplace submission is later requested. Passing that scanner is not a substitute for the boundary checks above.

## Deliberate omissions

No nested folders, tags, sync, accounts, page archiving, page previews, Markdown rendering, import/export, AI features, store publication or compiled packaging in the first version. No Inbox view, separate detail pane, URL editor, manual Save workflow, website scraping or background favicon refresh. No speculative abstractions or unused dependencies. Add a feature when the user asks for it or a measured limit requires it.

## Implementation evidence and remaining checks

- `node --test`: helper persistence, duplicate/concurrent capture, note/folder preservation, literal search, native capture-only authorization, malformed/bounded frames, URLs/PNG validation, unsafe file paths, autosave acknowledgement races/retry/deletion, extension feedback, and disposable setup/removal.
- `node tests/run-ui.mjs`: actual Quickshell/Omarchy controls in an isolated configuration; keyboard focus, folder navigation (wide/narrow and empty/loading), R rename and D confirmation/cancellation, Right expansion without focus theft, note typing, real save rejection and recovery, collapse flushing, reopen, folder deletion, and rendered wide/narrow/light layouts. A second fresh Quickshell process confirms committed note persistence. Qt's standalone test runner cannot load this installation's statically linked Quickshell plugins, so the check runs inside Quickshell.
- `node tests/lint.mjs` and `omarchy plugin validate .`: passed against installed imports and the actual plugin tree. The lint wrapper checks JSON file results because qmllint's JSON mode can return zero while reporting diagnostics.
- `node tests/benchmark.mjs`: 10,000 bookmarks with 4,196-byte PNGs; 44.3 MiB database. Seven cold helper invocations per operation measured median capture 54 ms and search 39 ms on this machine, including process startup. Results stay below the planned 200 ms target.
- Local setup registers Chromium's native host, enables the Omakeep bar entry and adds the unused Super+Shift+K binding. The extension uses Alt+Shift+K. The exact shortcut block has a backup outside scanned configuration directories; Hyprland reload/config validation passed. The installed Omakeep window opens successfully.
- User confirmed the unpacked Chromium extension loaded and successfully saved a page. Remaining manual gate: verify actual `_favicon` access, confirmation without focus change, offline favicon rendering, Enter opening the browser, and the full flow after closing Chrome/restarting the shell. Browser-control connection is unavailable in this session; worker mocks and direct native-protocol checks do not count as this gate passing.

Live keyboard verification after restarting the shared Omarchy shell: Left/Down/Right folder navigation, bookmark/folder R rename, and bookmark/folder D confirmation all worked. Dialogs were canceled without modifying user data. A plugin rescan had retained the old QML components; a full shell restart loaded the current UI. Check the actual running window after future updates.

## Ponytail review

Reviewed again at full intensity for the accepted design: use one list with native disclosure controls, Chrome's favicon resource, a small inline PNG blob and one debounced mutation queue. Browser capture saves with confirmation; editing happens later, removing the need for capture-to-panel IPC. Reuse Omarchy/Qt controls, native messaging, Node's standard library and SQLite constraints. Tests protect storage, trust boundaries and pending user edits. No additional scaffolding, service, dependency or build step is approved by this plan.

Completion means the verified capture-to-library flow works with Chrome closed, the UI matches the accepted simple design within Omamail's native styling, Enter opens pages, inline notes save automatically, favicons remain available offline, data is preserved on failures/removal, and the documented JavaScript implementation requires no build step.
