# Startup Configuration Window — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Early log entries survive the configuration phase: the core buffers them while a configuration window is open and replays them to the (then correctly configured) providers when the window closes — explicitly via `TDXLogger.CompleteConfiguration` or via a fallback timeout.

**Architecture:** The mechanism lives entirely in `TDXLogger` (DX.Logger.pas). The platform default provider keeps writing immediately; all other providers receive nothing while the window is open. Providers themselves stay unchanged. A short-lived watchdog thread implements the fallback timeout; the class destructor flushes a still-open window.

**Tech Stack:** Delphi (RTL only, cross-platform), DUnitX (tests/), no new dependencies.

**Spec:** `docs/superpowers/specs/2026-08-14-startup-configuration-window-design.md` — the spec is the binding authority for all semantics (buffer, replay, MinLevel, cap, drop policy, timing). Read it before every task.

## Global Constraints

- **Repo conventions (upstream):** English identifiers/comments/docs; Conventional Commit messages (`feat:`, `test:`, `docs:`); style per `docs/Delphi Style Guide EN.md` (T/F/L/A prefixes, PascalCase).
- **Work happens in `c:\Projekte\SDE_Zielsteuerungen\libs\DX.Logger`** on the existing branch `feat/startup-configuration-window` (Tasks 1–3). Task 5 works in the SDE repo — explicitly marked there.
- **Commit trailer:** end every commit message with `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`. No pushes, no PRs from implementers — the controller handles those.
- **Encoding:** `.pas` files in this repo: check the existing byte state before editing (`python -c "d=open(r'<file>','rb').read(); print(d[:3]==b'\xef\xbb\xbf', d.count(b'\r\n'), d.count(b'\n'))"`) and preserve exactly what is there (BOM presence and CRLF). Markdown: plain UTF-8.
- **Behavioral contract:** default provider output timing/format unchanged; `TLogEntry`, `ILogProvider`, `TAsyncLogProvider` unchanged; no API removals.
- **Build/tests:** build `tests/DX.Logger.Tests.dproj` with the SDE build script (`powershell -File ../../build-scripts/DelphiBuildDPROJ.ps1 -ProjectFile tests/DX.Logger.Tests.dproj` from the DX.Logger root — the script resolves Delphi itself) and run the produced test EXE (check `tests/DX.Logger.Tests.dproj` for its output path first; run with `--exitbehavior:Continue` if pauses block automation). All existing tests must stay green.
- Never touch `Build/` output artifacts; never commit `.dproj.local`/`.dsk`.

---

### Task 1: Core window + buffer + `CompleteConfiguration`

**Files:**
- Modify: `source/DX.Logger.pas`
- Test: `tests/DX.Logger.Tests.Core.pas` (extend; reuse the existing `TMockLogProvider`)

**Interfaces (Produces):**

```pascal
// New public class members on TDXLogger:

/// <summary>
/// Ends the configuration phase: replays all buffered startup entries (in
/// original order, filtered with the MinLevel valid now) to every registered
/// provider except the platform default provider, then discards the buffer.
/// Thread-safe and idempotent; may be called from any thread. Providers
/// registered after this call start empty and receive live entries only.
/// </summary>
class procedure CompleteConfiguration;

/// <summary>
/// Fallback timeout for the configuration window in milliseconds.
/// Default 10000. 0 disables auto-close (explicit CompleteConfiguration or
/// process shutdown only). Effective while the window is open.
/// </summary>
class property StartupTimeoutMs: Cardinal read ... write ...;   // implemented in Task 2; declare the field + property here with default set in the class constructor

/// <summary>
/// TEST SUPPORT ONLY: reopens the configuration window, clears the startup
/// buffer and drop counter, and re-arms the fallback watchdog with the
/// current StartupTimeoutMs. Not intended for production code.
/// </summary>
class procedure ResetStartupStateForTesting;
```

Internal state (private class/instance fields): window-open flag, startup buffer (`TList<TLogEntry>` capped at `C_STARTUP_BUFFER_MAX = 10000`), drop counter. The default provider needs to be distinguishable — keep the reference created in the constructor in a private field (`FDefaultProvider: ILogProvider`) instead of anonymous registration.

**Semantics to implement (from the spec — binding):**
- `Log(...)` builds the entry exactly as today. Dispatch changes: default provider always receives the entry immediately **if** `ALevel >= FMinLevel` (today's filter). While the window is open, the entry is **additionally appended to the buffer regardless of MinLevel** (move the `if ALevel < FMinLevel then Exit` check: it may no longer skip buffering — restructure so the entry is built when the window is open OR the level passes, buffered unfiltered, and default-dispatched only when the level passes; non-default providers receive nothing while open).
- Buffer full → increment drop counter, discard the incoming entry (newest dropped, oldest kept).
- `CompleteConfiguration`: under the class lock — if already closed, exit. Mark closed; snapshot + clear buffer and drop count; then (under the instance monitor, same discipline as `Log`) for each buffered entry with `Level >= FMinLevel` (MinLevel read at close time) dispatch to every provider **except** `FDefaultProvider`; if drops occurred, dispatch one final synthetic `Warn` entry (`'DX.Logger: %d startup log entries were dropped (startup buffer full)'`, timestamp `Now`, current thread id) to the same providers.
- After close, `Log` dispatches to all providers exactly as the current code does (single loop, no buffer interaction).
- `RegisterProvider`/`UnregisterProvider` unchanged in behavior; registration while open simply adds to the list (they receive the replay on close).
- `ResetStartupStateForTesting`: reopen window, clear buffer + drop counter (watchdog re-arm becomes real in Task 2; in this task it is a no-op comment placeholder that Task 2 fills).

- [ ] **Step 1: Write failing tests** — extend `TDXLoggerTests` (new test methods; reuse `TMockLogProvider`, `Setup`/`TearDown` as-is). Each test starts with `TDXLogger.ResetStartupStateForTesting;` and ends with `TDXLogger.CompleteConfiguration;` (leave the logger closed for the legacy tests; also add `TDXLogger.CompleteConfiguration` to `Setup` **before** the mock registration? No — do NOT touch `Setup`: instead add `TDXLogger.CompleteConfiguration;` as the first line of `ResetStartupStateForTesting`-independent legacy safety: the window in the test process is closed long before these tests run, and every new test closes it again. Keep legacy tests untouched.):

```pascal
[Test]
procedure TestWindowBuffersEntriesForNonDefaultProviders;
// Reset; register mock; DXLog('early-1'); DXLog('early-2');
// Assert.AreEqual(0, FMockProvider.GetEntryCount);      // window open: nothing
// TDXLogger.CompleteConfiguration;
// Assert.AreEqual(2, FMockProvider.GetEntryCount);      // replay complete
// Assert.AreEqual('early-1', FMockProvider.GetEntry(0).Message);  // order kept
// Assert.AreEqual('early-2', FMockProvider.GetEntry(1).Message);

[Test]
procedure TestCompleteConfigurationIsIdempotent;
// Reset; register mock; DXLog('x'); CompleteConfiguration; CompleteConfiguration;
// Assert.AreEqual(1, FMockProvider.GetEntryCount);      // no double replay

[Test]
procedure TestProviderRegisteredAfterCloseGetsNoReplay;
// Reset; DXLog('early'); CompleteConfiguration; register mock; DXLog('late');
// Assert.AreEqual(1, FMockProvider.GetEntryCount);
// Assert.AreEqual('late', FMockProvider.GetLastEntry.Message);

[Test]
procedure TestReplayAppliesMinLevelAtCloseTime;
// Reset; SetMinLevel(Info); DXLogTrace('t1');           // buffered despite filter
// SetMinLevel(TLogLevel.Trace); CompleteConfiguration;
// -> mock received 't1' (trace survived because MinLevel at close allows it)
// Then: Reset; SetMinLevel(TLogLevel.Trace); DXLogTrace('t2'); SetMinLevel(TLogLevel.Warn);
// CompleteConfiguration; -> mock did NOT receive 't2'.
// Restore SetMinLevel(TLogLevel.Trace) at the end (test-suite default).

[Test]
procedure TestBufferOverflowDropsNewestAndWarnsOnReplay;
// Reset; register mock; log 10001 entries ('e0'..'e10000');
// CompleteConfiguration;
// Assert.AreEqual(10001, FMockProvider.GetEntryCount);  // 10000 kept + 1 warn
// Assert.AreEqual('e0', FMockProvider.GetEntry(0).Message);           // oldest kept
// Assert.AreEqual('e9999', FMockProvider.GetEntry(9999).Message);     // newest kept is e9999
// LWarn := FMockProvider.GetLastEntry;
// Assert.AreEqual(TLogLevel.Warn, LWarn.Level);
// Assert.IsTrue(LWarn.Message.Contains('1 startup log entries were dropped'));

[Test]
procedure TestCompleteConfigurationFromWorkerThread;
// Reset; register mock; DXLog('from-main');
// Run CompleteConfiguration inside TThread.CreateAnonymousThread + TEvent wait (2 s timeout);
// Assert event was signaled and mock received 'from-main'.
```

- [ ] **Step 2: Run tests to verify they fail** — build the test project, run it; expected: compile error (`ResetStartupStateForTesting`/`CompleteConfiguration` undeclared). That is the RED state.
- [ ] **Step 3: Implement** in `source/DX.Logger.pas` per the Interfaces/Semantics block above. Keep the restructured `Log` method readable: early-out only when the window is closed AND the level is filtered; comment the why (unfiltered buffering) referencing the spec.
- [ ] **Step 4: Run tests to verify green** — all new tests pass AND all pre-existing tests stay green (the legacy tests run against a closed window, which is exactly today's behavior).
- [ ] **Step 5: Commit** — `feat: buffer startup log entries until configuration completes` (+ trailer).

---

### Task 2: Fallback watchdog + shutdown flush

**Files:**
- Modify: `source/DX.Logger.pas`
- Test: `tests/DX.Logger.Tests.Core.pas`

**Interfaces:**
- Consumes: Task 1 state (window flag, buffer, `CompleteConfiguration`, `ResetStartupStateForTesting`, `StartupTimeoutMs` declaration).
- Produces: working `StartupTimeoutMs` (default 10000 set in the class constructor); watchdog lifecycle; shutdown flush.

**Semantics (binding, from spec):**
- Watchdog: one short-lived thread (`TThread.CreateAnonymousThread`, `FreeOnTerminate := False` so it can be joined — store the TThread reference in a private class var) started on the first `Instance` access when the window is open and `StartupTimeoutMs > 0`. Body: wait on a `TEvent` (private class var) with `StartupTimeoutMs`; on timeout → call `CompleteConfiguration`; on event signal → exit without action. `CompleteConfiguration` sets the event (always, idempotent).
- `ResetStartupStateForTesting` re-arms: join + free any previous watchdog, recreate the event, restart the watchdog with the current `StartupTimeoutMs` (or none when 0).
- Class destructor: signal the event, join + free the watchdog, then if the window is still open call `CompleteConfiguration` (flush) **before** freeing the instance/lock. **Named risk to verify while implementing:** unit finalization order — provider units finalize before DX.Logger (they depend on it), so their class destructors may run first; the core holds `ILogProvider` interface references, so objects stay alive via refcounting as long as `FProviders` holds them. Read `source/DX.Logger.Provider.Async.pas` and `TFileLogProvider`'s class destructor to confirm the flush cannot touch a torn-down provider; document the finding in a code comment at the flush site. If a hazard exists, guard the flush (e.g. skip replay during finalization of providers is NOT acceptable — instead flush before provider teardown is impossible from the core; the correct guard is to keep interface refs alive, which the list does — verify and document).

- [ ] **Step 1: Failing tests:**

```pascal
[Test]
procedure TestWatchdogClosesWindowAfterTimeout;
// TDXLogger.StartupTimeoutMs := 200;
// TDXLogger.ResetStartupStateForTesting;   // re-arms with 200 ms
// register mock; DXLog('early');
// Assert.AreEqual(0, FMockProvider.GetEntryCount);
// Wait up to 2 s polling GetEntryCount (10 ms steps);
// Assert.AreEqual(1, FMockProvider.GetEntryCount);  // auto-close replayed
// TDXLogger.StartupTimeoutMs := 0;  // restore: no watchdog interference with other tests

[Test]
procedure TestStartupTimeoutZeroDisablesAutoClose;
// StartupTimeoutMs := 0; Reset; register mock; DXLog('early');
// Sleep(300); Assert.AreEqual(0, FMockProvider.GetEntryCount);
// CompleteConfiguration; Assert.AreEqual(1, ...);
```

- [ ] **Step 2: RED** (compile ok but tests fail — watchdog not implemented; `Reset` re-arm still a no-op).
- [ ] **Step 3: Implement** watchdog + shutdown flush + re-arm.
- [ ] **Step 4: GREEN** — full suite; also run the suite twice in a row to catch cross-test watchdog leakage.
- [ ] **Step 5: Commit** — `feat: fallback watchdog and shutdown flush for the configuration window` (+ trailer).

---

### Task 3: Documentation + CHANGELOG

**Files:**
- Modify: `README.md`, `docs/CONFIGURATION.md`, `CHANGELOG.md`
- Modify (headers only): `source/DX.Logger.pas`, `source/DX.Logger.Provider.TextFile.pas`, `source/DX.Logger.Provider.UI.pas`, `source/DX.Logger.Provider.Seq.pas`

**Content (binding):**
- New section **"Startup & Configuration Window"** in `README.md` (and the same, in more depth, in `docs/CONFIGURATION.md`): the behavior table from the spec; recommended DPR layout with this exact example:

```pascal
program MyApp;

uses
  // Memory managers (FastMM etc.) first — they must not depend on DX.Logger.
  // Then the logger and ALL provider units, before anything else, so their
  // initialization runs as early as possible:
  DX.Logger,
  DX.Logger.Provider.TextFile,
  Vcl.Forms,
  { ... },
  Main.Form in 'Main.Form.pas';

begin
  // Configure providers first, then close the configuration window.
  // Without CompleteConfiguration the window auto-closes after
  // TDXLogger.StartupTimeoutMs (default: 10 s) or at process shutdown —
  // early entries are never lost either way.
  TFileLogProvider.SetLogFileName('LOG\MyApp.log');
  TDXLogger.SetMinLevel(TLogLevel.Trace);
  TDXLogger.CompleteConfiguration;
  Application.Initialize;
  { ... }
end.
```

  Plus: a paragraph on UI providers (bind the memo in `FormCreate`, then call `CompleteConfiguration` there — or rely on the 10 s window — so the memo shows the boot lines), and `StartupTimeoutMs` (incl. `0`).
- Unit headers: `DX.Logger.pas` header comment gains a short "Startup behavior" note; the three provider headers replace the claim "logging is automatically activated by using this unit" with "the provider registers itself on unit initialization; entries are delivered once `TDXLogger.CompleteConfiguration` closes the configuration window (or the startup timeout elapses)".
- `CHANGELOG.md`: add under `[Unreleased]` → `### Added` (English, Keep-a-Changelog style): the configuration window, `CompleteConfiguration`, `StartupTimeoutMs`, shutdown flush; one `### Changed` note that non-default providers no longer write during the window (entries are buffered and replayed).

- [ ] **Step 1: Write docs** per the content block. **Step 2: Fact-check** every claim against the Task-1/2 implementation (method names, default values, drop policy). **Step 3: Build + run tests once** (docs must not break anything — headers are code files). **Step 4: Commit** — `docs: describe the startup configuration window and recommended DPR layout` (+ trailer).

---

### Task 4 (Controller): PR on omonien/DX.Logger

Push `feat/startup-configuration-window`, open a PR (English body: problem, mechanism, behavior changes, test evidence), await bot reviews if any, and **wait for Olaf's explicit approval before merging** (master is a shared default branch).

---

### Task 5: Adopt in SDE-Zielsteuerungen (SDE repo — only after the DX.Logger PR is merged)

**Repo/Branch:** `c:\Projekte\SDE_Zielsteuerungen`, new branch `feature/dxlogger-startup-adoption` based on `package/standort-vereinheitlichung` (or on `Wiet-Integration` if PR #12 has been merged by then — check first). German language rules of the SDE repo apply here.

**Files:**
- Modify: `libs/DX.Logger` (submodule bump to the merged master commit)
- Modify: `src/SDE.Logging.pas` — remove `GFileLoggerReady`, `GLoggerLock`, and the `EnsureSDEFileLogger` calls inside every `SDELog*` wrapper; rename `EnsureSDEFileLogger` to `KonfiguriereSDELogging` (plain, non-guarded configuration: set file name `LOG\<exe>.log`, max size, MinLevel — exactly today's values) and keep `BindSDELogMemo`/`UnbindSDELogMemo` as-is.
- Modify: `src/Wiet/SDEziel.dpr`, `src/Raabtal/SDEziel.dpr` — `SDE.Logging` becomes the **first** unit in the uses clause (its dependency chain pulls DX.Logger + both providers first); first statements after `begin`: `KonfiguriereSDELogging;` (no `CompleteConfiguration` here — see next line).
- Modify: `src/Main.Form.pas` — in `FormCreate`, directly after `BindSDELogMemo(Memo1.Lines)`: `TDXLogger.CompleteConfiguration;` (uses `DX.Logger`) — deterministic close with the memo already bound, so the memo shows the boot lines; document this decision in a one-line comment.
- Modify: every other program that calls `SDELog*` (`Testprogramm` DPRs, smoke tests — find them via `grep -rln "SDE.Logging" src tests --include=*.dpr`): same pattern (`SDE.Logging` first in uses, `KonfiguriereSDELogging` after `begin`; console tools may call `TDXLogger.CompleteConfiguration` right after configuration since they have no memo).
- Test: full SDE regression gate (both `SDEziel.dproj`, both `Testprogramm.dproj`, `tests/SDETests.dproj` + run, all three smoke projects + run, `SPSSimulator.dproj`, `SDETestclient.dproj`) plus a manual start of one `SDEziel.exe` verifying: `LOG\SDEziel.log` contains the boot lines exactly once, and the memo shows them too.

- [ ] Step 1: branch + submodule bump; Step 2: `SDE.Logging` simplification (compile-driven); Step 3: DPR/Form changes; Step 4: full gate + manual verification; Step 5: commit (German message + trailer), push, PR per SDE workflow.

---

## Self-Review (performed while writing)

- Spec coverage: window/buffer/replay (T1), MinLevel-at-close (T1), cap + drop-newest + warn (T1), idempotent/thread-safe close (T1), watchdog + `StartupTimeoutMs` + `0` semantics (T2), shutdown flush + finalization-order risk (T2 named risk), docs incl. DPR layout + UI paragraph (T3), CHANGELOG (T3), SDE adoption incl. memo-close decision (T5). Late-registration no-replay: T1 test 3.
- Placeholders: none; all test bodies and doc content specified.
- Type consistency: `CompleteConfiguration`/`ResetStartupStateForTesting`/`StartupTimeoutMs` named identically across tasks; `C_STARTUP_BUFFER_MAX` constant matches the repo's `C_`-prefix convention (see `C_DEFAULT_MAX_FILE_SIZE`).
