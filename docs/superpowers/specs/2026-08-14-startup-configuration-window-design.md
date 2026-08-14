# Design: Startup Configuration Window

**Date:** 2026-08-14 · **Status:** Approved by Olaf Monien (design discussion 2026-08-13/14) · **Target:** DX.Logger core

## Problem

`TFileLogProvider` registers itself with `TDXLogger` in its unit `initialization` section and becomes active immediately — with *default* configuration (e.g. log file `<AppName>.log` next to the executable, 10 MB rotation). `TSeqLogProvider` and `TUILogProvider` do not self-register; their `initialization` sections (where present) only set internal defaults, and registering them with `TDXLogger` is left to the host application (typically in the DPR body, alongside their other configuration calls). Application-specific configuration (`SetLogFileName`, `SetMaxFileSize`, `SetMinLevel`, Seq server URL …) can run at the earliest in the DPR body, i.e. *after* the first log calls are already possible for self-registering providers.

Consequences observed in production (SDE-Zielsteuerungen):

1. Early log entries are written to the wrong file; `SetLogFileName` mitigates by renaming the existing file — a workaround at the symptom level.
2. Configuration calls race against a provider that is already writing. Host applications end up building their own guards (`EnsureSDEFileLogger` with a ready-flag and a critical section wrapped around every log call).
3. There is no way to configure a provider *before* it processes entries without losing the early entries.

## Goals

- Early log entries (before app configuration) must **never be lost** and must end up in the **correctly configured** targets.
- Providers must be usable immediately after unit initialization — including from worker threads.
- The platform default provider (console / OutputDebugString / NSLog / syslog) keeps writing **immediately** at all times (live diagnostics).
- Existing applications that are not adapted keep working without code changes (behavior may differ only by a small startup delay).
- Document the recommended DPR layout: logger units first in the `uses` clause (only after memory managers such as FastMM), `TDXLogger.CompleteConfiguration` as the first statement(s) after `begin` once configuration is done.

## Non-Goals

- No replay for providers registered *after* the window closes (the buffer dies with the window).
- No change to the provider API (`ILogProvider`, `TAsyncLogProvider`) — the mechanism lives entirely in the core.
- No persistent/looping timer infrastructure; the fallback watchdog is one short-lived thread.

## Design

### Configuration window

`TDXLogger` owns a **configuration window** that is open from process start:

| Situation | Default provider | All other registered providers |
|---|---|---|
| Window **open** | writes immediately (current MinLevel applies, as today) | receive **nothing**; every entry is appended to the **startup buffer** (unfiltered, all levels) |
| Window **closes** | unchanged | buffered entries are replayed **in original order**, filtered with the MinLevel valid *at close time*; buffer is discarded afterwards |
| Window **closed** | unchanged | live dispatch as today |

The buffer stores entries **unfiltered** (ignoring the current MinLevel) so that a later `SetMinLevel(Trace)` still delivers early trace lines. The default provider's immediate output keeps honoring the current MinLevel, exactly as today.

### Closing the window

```pascal
class procedure TDXLogger.CompleteConfiguration;
```

- Thread-safe, idempotent, callable from any thread. Second and later calls are no-ops.
- Closes the window: replays the buffer (order preserved, filtered with the now-valid MinLevel) to all registered non-default providers, then discards the buffer.
- Providers registered while the window was open take part in the replay. Providers registered after the close start empty and live.

Naming rationale: the call ends the *configuration phase*. It deliberately does not suggest that logging only starts here (`StartLogging` was rejected for exactly that reason).

### Fallback timer

```pascal
class property StartupTimeoutMs: Cardinal; // default 10000; 0 = no auto-close
```

- Default **10 000 ms** — generous enough that late registrants such as the UI provider (bound in `FormCreate`) are usually still inside the window and therefore see the boot lines.
- Mechanics: a single short-lived watchdog thread starts with the first `TDXLogger.Instance` access (in practice: the first provider registration in unit initialization); it waits on an event with the timeout. `CompleteConfiguration` sets the event → the watchdog exits without action. On timeout the watchdog calls `CompleteConfiguration` itself.
- `StartupTimeoutMs = 0` disables auto-close (explicit close or shutdown flush only). Changing the value is effective while the window is open.
- A runtime class property was chosen over a compiler define: Delphi defines are value-less symbols; a numeric timeout would require an ugly symbol matrix, and the property can be set in the same early DPR line as the explicit close.

### Shutdown flush

The class destructor closes a still-open window (replay to registered providers, then normal teardown). Early entries are therefore never lost, even in short-lived CLI processes that never call `CompleteConfiguration` and exit before the timeout. The watchdog event is signaled and the thread joined during teardown.

### Buffer cap

- Fixed cap: **10 000 entries** (constant).
- On overflow the **newest** entries are dropped (the oldest boot lines carry the highest diagnostic value) and a drop counter is kept.
- If entries were dropped, the replay emits one final `Warn` entry stating the number of dropped startup entries.

### Thread safety

Buffer and window state are guarded by the existing lock regime (`TMonitor` on the instance for provider dispatch, class-level lock for class state). `CompleteConfiguration` may be called from any thread; replay happens under the same lock discipline as today's provider dispatch (async providers only enqueue in `Log`, so holding the lock during replay is equivalent to today's behavior).

## Provider impact

**None.** `TFileLogProvider` keeps self-registering in its `initialization` section; `TSeqLogProvider` and `TUILogProvider` keep being registered explicitly by the host application, unchanged. Either way, the core simply withholds entries until the window closes. The rename heuristic in `SetLogFileName` remains as a safety net for post-close configuration but becomes irrelevant in the documented flow (no file has been written before the close). Unit header documentation is updated.

## Behavior changes (intentional)

1. Non-default providers no longer write during the window. An unadapted existing application sees its file entries appear up to `StartupTimeoutMs` later than before — in exchange they are complete and correctly configured. This is the accepted compatibility trade-off.
2. The UI provider now typically shows boot lines (bound within the 10 s window → replay). Applications that close the window early deliberately opt out of this.

## Documentation plan

- README + `docs/CONFIGURATION.md`: new section "Startup & Configuration Window" covering: recommended DPR `uses` order (DX.Logger and all provider units first, only after memory managers such as FastMM or similar systems that do not depend on DX.Logger), example DPR (`configure providers` → `TDXLogger.CompleteConfiguration` as first statements after `begin`; without the call the 10 s fallback applies), the behavior table above, `StartupTimeoutMs`.
- Unit headers of `DX.Logger.pas` and the shipped providers updated accordingly.
- `CHANGELOG.md`: `feat:` entry, minor version bump per repo convention.

## Test plan (DUnitX, tests/)

Using a test provider (records received entries):

1. Entries logged while the window is open do not reach the provider; after `CompleteConfiguration` all arrive, in order.
2. Provider registered after the close: no replay, live entries only.
3. MinLevel semantics: trace entry logged during the window, `SetMinLevel(Trace)` called afterwards (release-default scenario) → replay contains the trace entry; with `SetMinLevel(Warn)` at close time, lower-level entries are filtered out of the replay.
4. Timeout auto-close with a small `StartupTimeoutMs` (e.g. 200 ms).
5. `CompleteConfiguration` is idempotent and safe from a worker thread.
6. Buffer overflow: cap exceeded → oldest kept, drop warning emitted on replay.
7. State reset between tests follows the existing core test patterns.

## Follow-up (separate package, SDE repo)

Adopt the mechanism in SDE-Zielsteuerungen: update the submodule reference, shrink `SDE.Logging` (ready-flag and critical section removed; `EnsureSDEFileLogger` becomes a plain configuration routine), apply the documented DPR `uses` order and `CompleteConfiguration` to both `SDEziel.dpr` and the test/smoke programs.
