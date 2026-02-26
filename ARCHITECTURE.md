# waymark.nvim — Architecture

Visual reference for contributors. All diagrams use [Mermaid](https://mermaid.js.org/) and render on GitHub natively.

---

## Module Dependency Graph

Hub-and-spoke: `state` is the shared mutable hub, `config` is read-only shared config. No module requires another module's internal locals — communication happens through `state` fields or public API calls.

```mermaid
graph TD
    init["<b>init.lua</b><br/>setup(), public API"]

    subgraph core ["Core (hub)"]
        state["<b>state.lua</b><br/>All mutable state<br/>Mark lists, indices,<br/>timers, counters"]
        config["<b>config.lua</b><br/>Defaults, validation,<br/>M.current (read-only)"]
    end

    subgraph modules ["Feature modules (spokes)"]
        automark["<b>automark.lua</b><br/>Tracking, cleanup,<br/>on_key/autocmd hooks"]
        bookmark["<b>bookmark.lua</b><br/>CRUD, save/load,<br/>atomic persistence"]
        allmark["<b>allmark.lua</b><br/>Merged timeline,<br/>clock-domain bridge"]
        popup["<b>popup.lua</b><br/>Interactive window,<br/>selection, preview"]
        extmarks["<b>extmarks.lua</b><br/>Neovim extmark CRUD,<br/>sign placement, sync"]
    end

    subgraph support ["Support modules"]
        commands["<b>commands.lua</b><br/>User commands,<br/>keymap registration"]
        filter["<b>filter.lua</b><br/>Buffer ignore logic,<br/>filetype/pattern cache"]
        highlights["<b>highlights.lua</b><br/>Highlight group setup,<br/>ColorScheme autocmd"]
        util["<b>util.lua</b><br/>Path, cursor, jump,<br/>preview helpers"]
    end

    init --> config & state
    init --> automark & bookmark & commands

    automark --> state & config & util & filter & extmarks
    bookmark --> state & config & util & filter & extmarks
    allmark --> state & config & util & filter & extmarks
    popup --> state & config & util & extmarks & bookmark
    extmarks --> state & config & util
    commands --> state & config & filter & automark & bookmark & allmark & popup
    filter --> state & config & util
    util --> state & config
    highlights --> config

    automark -.->|"lazy require<br/>(avoid circular)"| bookmark
    allmark -.->|"lazy require"| bookmark
    extmarks -.->|"lazy require"| bookmark
    filter -.->|"lazy require"| bookmark

    style state fill:#4a9eff,color:#fff,stroke:#2d7cd6
    style config fill:#6bc46d,color:#fff,stroke:#4a9f4c
    style init fill:#ff9f43,color:#fff,stroke:#d68030
```

> **Key constraint:** Dashed lines are lazy `require()` calls inside functions (not top-level) to break circular dependencies. Every dashed arrow points to `bookmark` — this is the only module that gets lazy-required.

---

## Setup Sequence

`init.setup(opts)` initializes modules in dependency order. Steps are numbered to match the comments in `init.lua`.

```mermaid
sequenceDiagram
    participant User
    participant init as init.lua
    participant cfg as config
    participant hl as highlights
    participant cmd as commands
    participant flt as filter
    participant ext as extmarks
    participant am as automark
    participant bm as bookmark
    participant st as state

    User->>init: require("waymark").setup(opts)

    Note over init: 1. Config
    init->>cfg: setup(opts)
    cfg->>cfg: Merge defaults + validate

    Note over init: 2. Cache flush
    init->>st: ignore_cache = {}

    Note over init: 3. Highlights
    init->>hl: setup()
    hl->>hl: Create highlight groups + ColorScheme autocmd

    Note over init: 4–5. Commands & keymaps
    init->>cmd: register_commands()
    init->>cmd: register_keymaps()

    Note over init: 6–9. Feature modules
    init->>flt: setup()
    flt->>flt: BufFilePost, BufWinEnter autocmds
    init->>ext: setup()
    ext->>ext: BufEnter/BufDelete autocmds
    init->>am: setup()
    am->>am: on_key, InsertLeave, BufLeave, LspAttach hooks
    init->>bm: setup()
    bm->>bm: VimEnter, VimLeavePre autocmds

    Note over init: 10. Late bootstrap (if lazy-loaded)
    alt vim_did_enter == 1
        init->>bm: load()
        init->>st: sync_mark_id_counter()
        init->>bm: cleanup()
        init->>ext: restore_for_buffer()
    end

    init->>st: setup_done = true
```

---

## Automark Tracking Flow

Automarks are created by four event sources. Each goes through the same `add()` pipeline with distance/time heuristics and a cleanup pass.

```mermaid
flowchart TD
    subgraph triggers ["Event Sources"]
        onkey["<b>on_key</b><br/>Debounced (idle_ms)<br/>after any keypress"]
        insert["<b>InsertLeave</b><br/>Immediate on exiting<br/>insert mode"]
        bufleave["<b>BufLeave</b><br/>Cursor position when<br/>leaving a buffer"]
        lsp["<b>LspAttach</b><br/>textDocument/definition<br/>jump callback"]
    end

    onkey & insert & bufleave & lsp --> getcursor

    getcursor["util.get_cursor_position()"]
    getcursor -->|nil: ignored buffer| stop1(("Skip"))
    getcursor -->|"{fname, row, col}"| shouldtrack

    shouldtrack{"should_track_position?"}
    shouldtrack -->|"Different file"| yes
    shouldtrack -->|"≥ min_lines away"| yes
    shouldtrack -->|"≥ min_interval_ms<br/>AND moved ≥ 1 line"| yes
    shouldtrack -->|"Same position /<br/>too close / too soon"| touchonly

    touchonly["Touch timestamp only<br/>(if force=true)"]
    touchonly --> done(("Done"))

    yes --> bookmarkcheck

    bookmarkcheck{"Bookmark exists<br/>at same file:line?"}
    bookmarkcheck -->|Yes| skipbookmark["Update bookmark timestamp<br/>(bookmark wins)"]
    skipbookmark --> done

    bookmarkcheck -->|No| cleanup

    cleanup["<b>Cleanup pass</b> (reverse iteration)<br/>① ≤ 2 lines away → always remove<br/>② ≤ cleanup_lines away, same window/tab,<br/>  older than recent_ms → remove"]

    cleanup --> create["Create WaymarkAutomark<br/>{id, fname, row, col, timestamp,<br/>window_id, tab_id}"]

    create --> evict{"#automarks ><br/>automark_limit?"}
    evict -->|Yes| evictold["Remove oldest mark<br/>(extmarks.remove)"]
    evict -->|No| place
    evictold --> place

    place["extmarks.place()<br/>Sign in gutter"]
    place --> updatestate["state.last_position = {fname, row, time}<br/>state.automarks_idx = -1<br/>state.merged_last_mark = nil"]
    updatestate --> done

    style triggers fill:#f5f5f5,stroke:#ccc
    style done fill:#6bc46d,color:#fff
    style stop1 fill:#999,color:#fff
```

---

## Bookmark Save Pipeline

Two branches: synchronous (VimLeavePre) and asynchronous (normal operation). Both use atomic writes. The async branch adds generation counting to abandon superseded writes.

```mermaid
flowchart TD
    save["bookmark.save(sync?)"]

    save -->|"sync = true<br/>(VimLeavePre)"| syncbranch
    save -->|"sync = false/nil<br/>(normal operation)"| asyncbranch

    subgraph syncbranch ["Synchronous Branch"]
        direction TB
        s1["Stop debounce timer"]
        s2["dirty = false<br/>generation++"]
        s3["JSON encode bookmarks"]
        s4["Open tmp file (.tmp.sync)"]
        s5["Write → fsync → close"]
        s6{"Write OK?"}
        s7["rename(tmp → bookmarks.json)"]
        s8["unlink(tmp)"]

        s1 --> s2 --> s3 --> s4 --> s5 --> s6
        s6 -->|Yes| s7
        s6 -->|No| s8
    end

    subgraph asyncbranch ["Asynchronous Branch"]
        direction TB
        a1["dirty = true"]
        a2["Restart debounce timer (300ms)"]
        a3["Timer fires → dirty = false"]
        a4["JSON encode + capture gen"]
        a5["seq++ → unique tmp filename"]
        a6["uv.fs_open (async)"]

        a6 --> gencheck1

        gencheck1{"gen ==<br/>save_generation?"}
        gencheck1 -->|"No (superseded)"| abandon1["Close fd + unlink tmp"]
        gencheck1 -->|Yes| a7["uv.fs_write (async)"]
        a7 --> a8["uv.fs_fsync (async)"]
        a8 --> a9["uv.fs_close (async)"]

        a9 --> gencheck2{"gen ==<br/>save_generation?"}
        gencheck2 -->|"No (superseded)"| abandon2["unlink tmp"]
        gencheck2 -->|Yes| a10["uv.fs_rename(tmp → bookmarks.json)"]

        a1 --> a2 --> a3 --> a4 --> a5 --> a6
    end

    subgraph atomic ["Atomic Write Pattern"]
        direction LR
        t1["Write to<br/>temp file"] --> t2["fsync<br/>(data on disk)"] --> t3["rename over<br/>target file"]
    end

    style atomic fill:#fff3cd,stroke:#ffc107
    style abandon1 fill:#e74c3c,color:#fff
    style abandon2 fill:#e74c3c,color:#fff
```

> **Why generation counting?** Rapid edits produce multiple save requests. Without generation checks, an older async write completing after a newer one would overwrite fresher data. Each async callback verifies its captured generation still matches the current one — if not, it discards its temp file and exits.

---

## Allmark Timeline: Dual Clock Domain Bridge

Automarks use monotonic milliseconds (immune to NTP/DST), bookmarks use epoch seconds (survive restarts). The allmark timeline unifies them using session anchors recorded at startup.

```mermaid
flowchart LR
    subgraph mono ["Monotonic Domain (session-only)"]
        am1["Automark A<br/>timestamp: 15200 ms"]
        am2["Automark B<br/>timestamp: 42800 ms"]
        anchor_mono["session_start_mono<br/>= uv.now() at setup"]
    end

    subgraph epoch ["Epoch Domain (persistent)"]
        bm1["Bookmark X<br/>timestamp: 1740000100"]
        bm2["Bookmark Y<br/>timestamp: 1740000350"]
        anchor_epoch["session_start_epoch<br/>= os.time() at setup"]
    end

    subgraph bridge ["mono_to_epoch() conversion"]
        formula["epoch_seconds =<br/>session_start_epoch +<br/>(mono_ms − session_start_mono) / 1000"]
    end

    subgraph merged ["Merged Timeline (sort_time: epoch seconds)"]
        direction TB
        m1["Bookmark X<br/>sort_time: 1740000100"]
        m2["Automark A → converted<br/>sort_time: 1740000115"]
        m3["Bookmark Y<br/>sort_time: 1740000350"]
        m4["Automark B → converted<br/>sort_time: 1740000343"]
        m1 --- m2 --- m4 --- m3
    end

    am1 & am2 --> bridge
    anchor_mono --> bridge
    anchor_epoch --> bridge
    bridge --> merged
    bm1 & bm2 -->|"Already epoch"| merged

    style mono fill:#e8f4fd,stroke:#4a9eff
    style epoch fill:#e8f8e8,stroke:#6bc46d
    style bridge fill:#fff3cd,stroke:#ffc107
    style merged fill:#f5f0ff,stroke:#9b59b6
```

> **Deduplication:** Before merging, bookmark positions are recorded in a `fname\0row` lookup set. Automarks at the same file:line as a bookmark are suppressed — the bookmark "wins" since it's persistent.

---

## Navigation State Machine

All three subsystems (automark, bookmark, allmark) share the same navigation pattern. The `-1` staging sentinel means "not navigating yet."

```mermaid
stateDiagram-v2
    [*] --> Staging: Plugin loaded /<br/>mark added /<br/>mark deleted

    Staging: idx = -1 (staging)
    Staging: "Not navigating any list"

    AtMark: idx = N (1-based)
    AtMark: Viewing mark N of total

    state navigating <<choice>>

    Staging --> navigating: prev() / next()

    navigating --> AtMark: prev() →<br/>idx = #list<br/>(enter from end)
    navigating --> AtMark: next() →<br/>idx = 1<br/>(enter from start)

    AtMark --> AtMark: prev() → idx - count<br/>(clamp to 1)
    AtMark --> AtMark: next() → idx + count<br/>(clamp to #list)

    AtMark --> Staging: Mark added / deleted<br/>(resets to -1)

    note right of AtMark
        Navigation sets state.navigating = true
        (prevents automark creation during jumps)
        Cleared after timeout or end_navigation()
    end note

    note left of Staging
        Three independent indices:
        • state.automarks_idx
        • state.bookmarks_idx
        • state.merged_last_mark (ID-based)
    end note
```

```mermaid
sequenceDiagram
    participant User
    participant nav as prev()/next()
    participant st as state
    participant util as util.jump_to_position

    User->>nav: :WaymarkPrev (count=1)

    nav->>st: begin_navigation_with_fallback()
    st->>st: navigating = true<br/>nav_generation++
    st->>st: Start 500ms fallback timer<br/>(captures generation)

    alt idx == -1 (staging)
        nav->>nav: idx = #list (enter from end)
    else idx > 1
        nav->>nav: idx = idx - count
    end

    nav->>util: jump_to_position(fname, row, col)
    util-->>User: Cursor moves to mark

    Note over st: Fallback timer fires
    alt generation unchanged
        st->>st: navigating = false
    else generation changed (new nav started)
        st->>st: Timer discarded (stale)
    end
```

---

## Extmark Lifecycle

Extmarks (sign column indicators) are placed, synced, and restored as buffers load and unload. `extmarks.lua` is the sole authority — no other module touches `nvim_buf_set_extmark` directly.

```mermaid
flowchart TD
    subgraph events ["Buffer Events"]
        enter["<b>BufEnter</b><br/>Buffer gains focus"]
        delete["<b>BufDelete</b><br/>Buffer unloaded"]
        vimenter["<b>VimEnter</b><br/>Startup complete"]
    end

    enter --> restore["restore_for_buffer(bufnr)<br/>Find all marks matching<br/>this buffer's filename"]
    vimenter --> restore

    restore --> place["place(mark, ns, sign, hl)<br/>nvim_buf_set_extmark()"]
    place --> stored["mark.extmark_id = id<br/>mark.bufnr = bufnr"]

    delete --> clearrefs["Clear extmark_id + bufnr<br/>on all marks for that buffer"]

    subgraph sync ["Position Sync (before navigation)"]
        direction TB
        syncfn["sync_from_extmark(mark, ns)"]
        check{"extmark_id exists<br/>AND buf valid?"}
        getpos["nvim_buf_get_extmark_by_id()"]
        update["mark.row = extmark_row + 1"]
        nochange["Keep mark.row as-is"]

        syncfn --> check
        check -->|Yes| getpos --> update
        check -->|No| nochange
    end

    style events fill:#f5f5f5,stroke:#ccc
    style sync fill:#e8f4fd,stroke:#4a9eff
```

> **Why sync before navigate?** When the user edits text, Neovim moves extmarks with the text automatically. But the mark struct's `.row` field is stale. `sync_from_extmark` reads the extmark's actual position back into the mark before any jump, ensuring navigation goes to the right line.

---

## Data Flow Summary

End-to-end: from user action to persisted state.

```mermaid
flowchart LR
    subgraph input ["User Actions"]
        edit["Edit text"]
        leave["Leave buffer"]
        insertleave["Exit insert mode"]
        lspjump["LSP go-to-definition"]
        addbm["Toggle bookmark"]
    end

    subgraph tracking ["Automark Tracking"]
        debounce["Debounce timer<br/>(idle_ms)"]
        heuristic["Distance / time<br/>heuristics"]
        cleanup["Proximity cleanup"]
    end

    subgraph marks ["Mark Storage (state.lua)"]
        automarks["state.automarks[]<br/>WaymarkAutomark"]
        bookmarks["state.bookmarks[]<br/>WaymarkBookmark"]
    end

    subgraph display ["Display"]
        extmark["Extmark signs<br/>in gutter"]
        popup_ui["Popup window<br/>(bookmarks)"]
        echopos["Echo position<br/>in cmdline"]
    end

    subgraph persist ["Persistence"]
        json["waymark-bookmarks.json<br/>(atomic write)"]
    end

    edit & leave & insertleave & lspjump --> debounce --> heuristic --> cleanup --> automarks
    addbm --> bookmarks
    automarks & bookmarks --> extmark
    bookmarks --> popup_ui
    automarks & bookmarks --> echopos
    bookmarks -->|"save()"| json
    json -->|"load()"| bookmarks

    style input fill:#f5f5f5,stroke:#ccc
    style marks fill:#e8f4fd,stroke:#4a9eff
    style persist fill:#e8f8e8,stroke:#6bc46d
    style display fill:#f5f0ff,stroke:#9b59b6
```

---

## Type Hierarchy

All `@class` definitions and where they're produced and consumed.

```mermaid
classDiagram
    class WaymarkAutomark {
        +integer id
        +string fname
        +integer row
        +integer col
        +number timestamp  ← monotonic ms
        +integer? window_id
        +integer? tab_id
        +integer? extmark_id
        +integer? bufnr
    }

    class WaymarkBookmark {
        +integer id
        +string fname
        +integer row
        +integer col
        +number timestamp  ← epoch seconds
        +integer? extmark_id
        +integer? bufnr
    }

    class WaymarkMergedMark {
        +integer id
        +string fname
        +integer row
        +integer col
        +number sort_time  ← epoch seconds
        +string kind  ← "automark"|"bookmark"
        +integer? window_id
        +integer? tab_id
    }

    class WaymarkCursorPosition {
        +string fname
        +integer row
        +integer col
    }

    class WaymarkLastPosition {
        +string fname
        +integer row
        +number time  ← monotonic ms
    }

    class WaymarkBookmarkSerialized {
        +integer id
        +string fname
        +integer row
        +integer col
        +number timestamp
    }

    class WaymarkBookmarkFile {
        +WaymarkBookmarkSerialized[] bookmarks
        +integer saved_at
    }

    class WaymarkConfig {
        +integer automark_limit
        +integer idle_ms
        +string automark_sign
        +string bookmark_sign
        +WaymarkMappings mappings
        +... 25 more fields
    }

    WaymarkAutomark <|-- WaymarkMergedMark : merged into (kind="automark")
    WaymarkBookmark <|-- WaymarkMergedMark : merged into (kind="bookmark")
    WaymarkBookmark <|-- WaymarkBookmarkSerialized : subset for JSON
    WaymarkBookmarkSerialized *-- WaymarkBookmarkFile : array member
    WaymarkCursorPosition ..> WaymarkAutomark : fields used to construct
    WaymarkCursorPosition ..> WaymarkBookmark : fields used to construct
```
