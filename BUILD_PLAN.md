# Omakeep build plan

Status: planned; implementation has not started. Ponytail full review: approved for the scope below. This is a complexity review, not a security certification or a claim that the implementation has passed tests.

## Objective

Build a local Omarchy bookmark library with notes and folders, accessible while Chrome is closed. Use Omamail as the UI reference. Use QML, plain JavaScript and SQLite, with no Python, Rust, build step or npm dependencies.

## User flow

1. Click the Chrome extension button or its browser shortcut.
2. Save the active page's URL and title to Inbox. Confirm success only after the database commits.
3. Open that bookmark in Omakeep to choose a folder and write notes. Failure to open the window must not undo or misreport the successful save.
4. Reach the library later through the Omarchy bar or a global shortcut. Open links in the default browser or copy their URLs.

Capturing an existing URL selects the existing bookmark without overwriting its title, notes or folder. Capture works even when the Omakeep window or Omarchy shell is unavailable. Incoming captures never replace unsaved editor text.

## First version

- Bookmarks: add manually or from Chrome, edit title/URL/notes, move to a folder, open, copy and delete with confirmation.
- Folders: create, rename and delete top-level folders. Each bookmark belongs to one folder or Inbox. Deleting a folder moves its bookmarks to Inbox in the same transaction.
- Views: All bookmarks, Inbox and user folders; newest bookmarks first.
- Search: literal substring search across title, URL and notes, scoped to the selected view. Debounce input and page results.
- Notes: a plain-text editor; Markdown syntax can be stored, but is not rendered.
- Editing: Save and Ctrl+S. Guard navigation away from dirty edits with Save/Discard/Cancel; preserve the draft on write failure. Hiding and reopening the window within a shell session preserves the draft. Saved data survives browser and shell restarts; unsaved crash recovery is outside this version.
- Keyboard: global library shortcut, Ctrl+F search, arrows for list navigation, Enter to select and an explicit action to open the URL. Text fields retain normal editing keys. Escape dismisses the current transient view before closing the window.

## UI reference

Follow Omamail's native window, compact toolbar, thin dividers, theme typography and responsive folder/list/detail arrangement. Use Omarchy's `qs.Ui` controls and `qs.Commons` theme values; inherit semantic colours instead of hard-coding a palette. Use native Qt list virtualization and input controls. At narrow widths, show the list or editor with back navigation.

| Region | Contents |
| --- | --- |
| Toolbar | Search and Add bookmark |
| Sidebar | All bookmarks, Inbox, user folders and folder management |
| List | Title, domain and short note excerpt |
| Editor | Title, URL, folder, notes, Save, Open, Copy URL and Delete |

Use visible focus, accessible names and tooltips for icon buttons. Every text sink carrying a title, folder, note or error explicitly uses plain text. Keep notifications generic where host-owned controls cannot guarantee plain-text rendering.

Reference implementations:

- [Omamail](https://github.com/huacnlee/omamail): window lifecycle, layout, theme and focus patterns. The installed reference is `~/.config/omarchy/plugins/omamail/`, especially `App.qml`, `BarWidget.qml` and `components/SearchBar.qml`.
- Omarchy's installed Copy URL extension and `omarchy-chromium-copy-url-host`: browser native-messaging registration and shell handoff. Reuse the integration pattern, with bounded messages and checked errors.
- [Nearby](https://github.com/jfg96/omarchy-nearby): QML/helper separation and JSON over stdin/stdout. Its Rust implementation and persistent network service are not needed here.
- [Browserpass](https://github.com/browserpass/browserpass-native): native-host packaging and browser registration.

Adapt only the necessary patterns; do not fork another application. Retain licence notices for any copied code.

## Implementation shape

| Part | Responsibility |
| --- | --- |
| `manifest.json`, `BarWidget.qml` | Plugin identity `omakeep`, bar entry and opening the window |
| `App.qml`, a few `components/*.qml` | Native window, selection, draft state and views |
| `helper.mjs` | Shared validation, database operations and protocol entry points |
| `extension/manifest.json`, `extension/background.js` | Manifest V3 capture button/shortcut and save feedback |
| `tests/helper.test.mjs` | Focused checks with `node:test` and `node:assert` |
| `setup.mjs`, `README.md` | Explicit local setup/removal and runtime documentation |

Start with these boundaries. Split the helper only if the actual code becomes difficult to read. No repository layer, plugin framework, generic transport abstraction or separate settings system.

Use Node's built-in `node:sqlite`, `node:fs`, `node:child_process` and `URL`. The installed Node 26.7.0 passed an in-memory create/insert/read check during planning. `node:sqlite` is currently a release-candidate API: document and check the supported Node version at setup; do not silently download a runtime or substitute an npm database package. See [Node SQLite documentation](https://nodejs.org/api/sqlite.html).

Both QML and Chrome invoke the same short-lived helper. QML sends bounded JSON through stdin; Chrome uses its length-prefixed native-messaging protocol. Both adapters call the same operation functions. QML starts processes asynchronously; synchronous SQLite work runs in the helper, outside the shell's UI thread. The helper exits after responding. No HTTP listener, daemon, polling loop or background Node process.

Use the shell's existing `keepLoaded` panel support to preserve in-session UI state. No separate `Service.qml` is needed initially. Reload data on open, capture handoff and completed mutations. Ignore stale search responses and keep at most one current search plus the latest pending query; never spawn a process for every keystroke.

### Storage

Store the library at `$XDG_DATA_HOME/omakeep/bookmarks.sqlite`, falling back to `~/.local/share/omakeep/bookmarks.sqlite`. Keep data outside the plugin checkout so updates and removal preserve it.

- `folders`: integer ID and unique non-empty name.
- `bookmarks`: integer ID, unique URL, title, notes, nullable folder ID and creation/update timestamps.
- Enable foreign keys; folder deletion uses `ON DELETE SET NULL`. Use parameterized statements, constraints, transactions and a finite busy timeout for concurrent writers.
- Keep the supplied URL's query and fragment intact. Trim surrounding whitespace; do not invent URL canonicalization. An edit that collides with another bookmark reports the conflict instead of merging records.
- Fetch list summaries in pages of at most 100, stopping earlier at the response byte budget and returning a continuation cursor. Bound folder results too. Load full notes only for the selected bookmark. Start with ordinary SQL search; mark its linear-scan ceiling with a `ponytail:` comment and add full-text indexing only when measurements justify it.

### Trust boundaries

Apply the installed `omarchy-plugin-security` skill to the real implementation. These are the relevant requirements for this scope:

- Capture only on the extension's explicit button/shortcut action, using `activeTab` and `nativeMessaging`. Use a stable extension ID and exact `allowed_origins`. No content script or blanket browsing permissions are necessary. See [Chrome native messaging](https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging).
- Native-host mode exposes capture only; browser payloads cannot request arbitrary SQL, filesystem paths, commands or destructive library operations. QML's separate entry mode owns editing operations.
- Validate types, allowed operations, IDs and lengths in the helper. Accept HTTP/HTTPS URLs with a host; reject embedded credentials and control characters. Local website URLs can be saved because capture does not fetch them.
- Bound native-message lengths before allocating payloads, reject malformed/truncated frames, and enforce a request deadline. Initial limits: URL 16 KiB, title 4 KiB, folder name 256 bytes, notes 64 KiB, request/response 256 KiB. Reject oversized input rather than silently trimming it.
- Bound stdout/stderr at the producer and in QML before assembling a response; validate the response shape before updating models. Fetch oversized lists through pagination. Cancel superseded reads, serialize UI mutations and retain drafts until a successful commit is acknowledged.
- Invoke fixed executables with argument arrays; pass notes and URLs through stdin. Do not interpolate data into shell commands. Native-host setup must resolve a supported Node executable and avoid depending on interactive shell initialization or inherited `NODE_OPTIONS`.
- Create private storage with owner-only permissions. Review database, parent-directory and journal-file handling together. Test symlinks, non-regular files and permission failures. A pathname check followed by `DatabaseSync(path)` is not proof of race-safe access.
- Prove the Node/SQLite file-opening approach in step 1 before calling storage hardened. If the public API cannot enforce a required boundary, record and resolve that limitation within the JavaScript/no-build constraint; do not add a custom SQLite VFS or silently switch languages.
- Shell IPC only opens/selects a bounded bookmark ID; it does not save, delete, return notes or execute supplied URLs. The native helper commits before requesting a UI handoff, and a dirty editor retains its draft when another bookmark is captured.

## Ordered work and acceptance checks

1. **Helper and storage.** Implement schema, operations and both protocol adapters. Leave one focused runnable test file covering persistence after reopen, repeated/concurrent captures, preservation of notes/folders, URL edit conflicts, folder deletion, literal search, bounds, malformed frames and hostile file paths. Measure cold helper startup and save/search latency with a synthetic 10,000-bookmark library. Aim for sub-200 ms save/search operations on this machine; record actual results before optimizing. Resolve the file-opening boundary before accepting storage as complete; independent UI work can proceed while that is investigated.
2. **Native UI.** Build the Omamail-inspired layout, data flow, folder management, search, notes and keyboard access. Verify narrow/wide windows, light/dark themes, empty/error states, focus, draft preservation and delayed/stale responses. Deleting a folder must never delete bookmarks. A failed save must never clear or claim to have saved the draft.
3. **Browser capture.** Implement the Manifest V3 button and shortcut; reuse the helper's capture function. Verify new and duplicate URLs, success/error feedback, a missing host, a disabled plugin and a closed shell. Only committed saves display success. Check capture while the editor has unsaved changes.
4. **Explicit local setup.** Register the plugin and native host for the browser/profile actually used. Resolve the Node executable during setup. Load the extension unpacked; document any browser UI action that must be done manually. Add a conflict-free global shortcut during setup, with a backup outside automatically scanned directories and validation of changed Hyprland config. Loading the plugin performs no installation, downloads or shared-config edits.
5. **Final verification and documentation.** Run `node --test`, `/usr/lib/qt6/bin/qmllint` against the actual Omarchy imports, and `omarchy plugin validate .`. Perform the complete flow: capture, add notes, file, close Chrome, reopen Omakeep, search and open the bookmark. Restart the shell and confirm committed data survives. Exercise removal on a disposable setup: remove only owned registration/config entries, leave the library intact, and ensure no helper remains running. Document supported runtime, data paths, setup, removal, limits and measured performance.

Use focused QML interaction checks where they catch an actual regression; do not copy Omamail's full test harness. Run the marketplace baseline and review the exact distributable tree only if marketplace submission is later requested. Passing that scanner is not a substitute for the boundary checks above.

## Deliberate omissions

No nested folders, tags, sync, accounts, page archiving, favicon fetching, previews, Markdown rendering, automatic note saving, import/export, AI features, store publication or compiled packaging in the first version. No speculative abstractions or unused dependencies. Add a feature when the user asks for it or a measured limit requires it.

## Ponytail review

Reviewed at full intensity: reuse Omarchy/Qt controls and native messaging; use Node's standard library and SQLite constraints; keep one implementation of each operation; perform work only on demand. Tests protect storage, trust boundaries and user edits. No additional scaffolding is approved by this plan.

Completion means the verified local capture-to-library flow works with Chrome closed, the UI follows Omamail, data is preserved on failures/removal, and the documented JavaScript implementation requires no build step.
