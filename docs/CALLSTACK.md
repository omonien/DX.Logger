# PRD – DX.Logger Callstack Extension

**Unit:** `DXLogger.Callstack`
**Status:** Draft v0.2
**Autor:** Esculenta GmbH
**Datum:** 2026-04-21
**Branch:** `feature/callstack` (DX.Logger-Repo)

---

## 1. Zielsetzung

`DXLogger.Callstack` erweitert die [DX.Logger](../README.md)-Bibliothek um automatisches Exception-Callstack-Logging.

Durch bloßes Einbinden der Unit in den `uses`-Abschnitt werden zwei Dinge aktiviert:

1. **Jede Exception** erhält automatisch einen vollständigen Callstack (via `Exception.StackTrace`).
2. **DX.Logger** hängt bei Einträgen auf Level `Error` und `Fatal` den Callstack transparent ans `Details`-Feld — ohne Änderung am bestehenden Logging-Code.

Ziel ist eine „Drop-in"-Erweiterung: Unit einbinden → fertig.

### 1.1 Abgrenzung zu DX.Logger-Core

| Aspekt | DX.Logger Core | DXLogger.Callstack |
|--------|---------------|-------------------|
| Abhängigkeit | eigenständig | benötigt `DX.Logger` |
| Aktivierung | immer aktiv | nur wenn Unit im `uses` |
| Aufgabe | Log-Pipeline, Provider | Stack-Capture + Map-Auflösung |
| Plattform | cross-platform | Windows Win32/Win64 (v1.0) |

### 1.2 Nicht-Ziele

- **Kein** Ersatz für madExcept oder EurekaLog (kein Crash-Dialog, kein automatisches Senden, keine Leak-Detection).
- **Keine** Symbol-Auflösung ohne `.map`-Datei (kein eigenes Debug-Format wie JCL `.jdbg`).
- **Keine** Unterstützung für FPC/Lazarus in Version 1.0.
- **Keine** GUI, kein Reporting, kein Persistenz-Layer.

---

## 2. Zielgruppe & Use Cases

### 2.1 Primäre Zielgruppe

- Teams, die bereits DX.Logger einsetzen (ELKE-Server, VCL/IntraWeb/Konsolen-Services).
- Build-Pipeline erzeugt ohnehin `.map`-Dateien (Linker-Option `-GD`).

### 2.2 Use Cases

| ID | Use Case | Beschreibung |
|----|----------|--------------|
| UC1 | Automatisches Stack-Logging | `DXLogError(E)` schreibt Message + Stack in einem Aufruf ins Log. |
| UC2 | Manueller Stack-Zugriff | `E.StackTrace` steht jederzeit im `except`-Block zur Verfügung. |
| UC3 | Server-Fehlerprotokoll | REST-/IntraWeb-Service loggt bei 500er-Fehler automatisch den vollständigen Aufrufpfad. |
| UC4 | Reraise mit Kontext | Bibliotheks-Code fängt Exception, reraised — Original-Stack bleibt erhalten. |
| UC5 | Diagnose im Support-Fall | Aus dem Seq/Logfile lässt sich der Aufrufpfad bis zur Quellzeile rekonstruieren. |

---

## 3. Funktionale Anforderungen

### 3.1 Pflicht (MUST)

- **F-1** Beim Auslösen einer Exception (`raise`) wird automatisch der aktuelle Callstack erfasst.
- **F-2** Der erfasste Stack ist über `Exception.StackTrace` (Standard-Property seit Delphi 2009) abrufbar.
- **F-3** Symbol-Auflösung gegen die `.map`-Datei neben der EXE/DLL: **Unit + Methode + Quellzeile + Offset**.
- **F-4** Funktioniert für aus Delphi geworfene Exceptions (`raise EFoo.Create(...)`).
- **F-5** Funktioniert für OS-Level-Exceptions (Access Violation, Division by Zero), die das RTL in `Exception`-Instanzen umsetzt.
- **F-6** Korrekte Behandlung von **Reraise** — der Stack des ursprünglichen `raise` bleibt erhalten.
- **F-7** Korrekte Behandlung von **ASLR** / unterschiedlicher Image-Base zur Laufzeit.
- **F-8** Single-Unit-Auslieferung — eine `.pas`-Datei, keine zusätzlichen Dateien zwingend erforderlich.
- **F-9** Aktivierung allein durch Einbinden in `uses`.
- **F-10** **DX.Logger-Integration**: Bei Log-Einträgen auf Level `Error` und höher wird `Exception.StackTrace` automatisch in das `Details`-Feld des `TLogEntry` geschrieben, sofern eine aktive Exception vorliegt.

### 3.2 Soll (SHOULD)

- **F-11** Lazy Loading der Map-Datei: Parsen erst beim ersten Stack-Zugriff, nicht beim Programmstart.
- **F-12** Konfigurierbare maximale Stack-Tiefe (Default: 32 Frames).
- **F-13** Konfigurierbares Skip-Pattern (z. B. RTL-Frames oberhalb von `System.SysUtils.RaiseExceptObject` ausblenden).
- **F-14** Thread-Safety — Stack-Erfassung und Map-Lookup aus mehreren Threads gleichzeitig sicher.
- **F-15** Fallback bei fehlender Map-Datei: `StackTrace` liefert den festen String `-- no call stack - map file not found --`. Keine Exception, keine rohen Adressen.
- **F-16** Optionales API zur **manuellen** Stack-Erfassung außerhalb von Exceptions (`DXCaptureStack: string`).
- **F-17** Konfigurierbare Mindest-Log-Level für automatische Stack-Anhängung (Default: `Error`).

### 3.3 Kann (MAY)

- **F-18** Ausgabeformat konfigurierbar (Plain-Text vs. JSON) — konsistent mit DX.Logger-Ausgabeformaten.
- **F-19** Optionales Caching der geparsten Map in kompakter Binärform (`.map.cache`).
- **F-20** Modul-übergreifende Auflösung: Adressen aus geladenen DLLs/BPLs, sofern deren `.map` vorhanden.

---

## 4. Nicht-funktionale Anforderungen

| Kategorie | Anforderung |
|-----------|-------------|
| **Performance** | Stack-Erfassung beim Raise: < 100 µs für 32 Frames. Auflösung beim ersten Zugriff: < 50 ms für Map ≤ 50.000 Symbole. |
| **Speicher** | Geparste Map: ≤ 5 MB Heap-Footprint pro 50.000 Symbole. |
| **Plattform** | Windows 32 Bit + 64 Bit (Win32, Win64). Linux/macOS optional in späteren Versionen. |
| **Compiler** | Delphi 10.4 Sydney und neuer. |
| **Lizenz** | MIT — konsistent mit DX.Logger. |
| **Abhängigkeiten** | Nur `DX.Logger`, Delphi-RTL und WinAPI. Keine externen Pakete. |
| **Build** | Keine zusätzlichen Build-Schritte außer der bereits vorhandenen Linker-Option „Detailed Map File". |

---

## 5. Architektur & Technisches Konzept

### 5.1 Einbettung in DX.Logger

```
DX.Logger (Core)
└── DXLogger.Callstack          ← diese Unit
    ├── RTL Exception Hooks     (GetExceptionStackInfoProc etc.)
    ├── Stack Capture           (RtlCaptureStackBackTrace)
    ├── Map File Parser         (Borland/Embarcadero .map)
    └── DX.Logger Hook          (TDXLogger.Instance Callback)
```

Im `initialization`-Block wird neben den RTL-Exception-Hooks auch ein Callback in `TDXLogger.Instance` registriert, der vor dem Weiterleiten an Provider prüft, ob eine aktive Exception vorliegt, und ggf. `Details` mit `AException.StackTrace` befüllt.

### 5.2 RTL Exception Hooks

```pascal
Exception.GetExceptionStackInfoProc  := DXCallstack_GetInfo;
Exception.CleanUpStackInfoProc       := DXCallstack_CleanUp;
Exception.GetStackInfoStringProc     := DXCallstack_InfoToString;
```

Im `finalization`-Block werden Callbacks defensiv zurückgesetzt (nur wenn noch auf eigene Funktionen zeigend).

### 5.3 DX.Logger-Integration

```pascal
// Registrierung im initialization-Block:
TDXLogger.Instance.OnBeforeLog :=
  procedure(var AEntry: TLogEntry; AException: Exception)
  begin
    if (AEntry.Level >= TLogLevel.Error) and Assigned(AException) then
      if AEntry.Details.IsEmpty then
        AEntry.Details := AException.StackTrace;
  end;
```

Damit funktioniert folgendes ohne jede Code-Änderung an bestehenden Log-Aufrufen:

```pascal
except
  on E: Exception do
    DXLogError(E.Message, E); // Details enthält automatisch den Stack
end;
```

### 5.4 Stack-Capture

- `RtlCaptureStackBackTrace` aus `kernel32.dll` (verfügbar ab Windows XP, robust unter x64).
- Ergebnis: `array of Pointer` mit Return-Adressen, gespeichert in dediziertem Record auf dem Heap.
- Pointer wandert nach `Exception.StackInfo`.

### 5.5 Map-Datei-Parser

- **Suchreihenfolge:** neben EXE/DLL gleichen Basisnamens → expliziter Pfad via Options.
- **Relevante Sections:** „Detailed map of segments", „Address Publics by Value", „Line numbers for …".
- **Datenstrukturen:** sortierte Arrays `(RVA, SymbolIndex)` und `(RVA, FileName, LineNo)` für Binär-Suche.
- **Adress-Translation:** `RVA = AbsoluteAddress - HInstance - CodeSectionOffset` (aus PE-Header gelesen).

### 5.6 Ausgabeformat (Plain-Text Default)

```
[$0000000000401A4F] MyApp.MainForm.Button1Click + $1F  (MainForm.pas line 142)
[$0000000000401C20] Vcl.Controls.TControl.Click + $4C
[$0000000000401D88] Vcl.Controls.TButton.CNCommand + $30
…
```

### 5.7 Thread-Safety

- Map-Datei wird einmal lazy geladen, danach **read-only** → lock-freier Lookup.
- Lazy-Init geschützt durch `TMonitor.Enter` mit Double-Checked-Locking.

---

## 6. API-Skizze

```pascal
unit DXLogger.Callstack;

interface

uses
  System.SysUtils,
  DX.Logger;

type
  TDXCallstackOptions = record
    MaxFrames:        Integer;     // Default 32
    SkipFrames:       Integer;     // Default 1
    IncludeAddresses: Boolean;     // Default True
    IncludeLineInfo:  Boolean;     // Default True
    MapFilePath:      string;      // leer = automatisch neben EXE
    MinLogLevel:      TLogLevel;   // Default Error — ab wann Stack ins DX.Logger-Details
  end;

var
  DXCallstackOptions: TDXCallstackOptions;

/// <summary>Manuelle Stack-Erfassung außerhalb einer Exception.</summary>
function DXCaptureStack: string;

/// <summary>Hook aktivieren (passiert automatisch im initialization-Block).</summary>
procedure DXCallstackInstall;

/// <summary>Hook deaktivieren.</summary>
procedure DXCallstackUninstall;

implementation
…
initialization
  DXCallstackInstall;
finalization
  DXCallstackUninstall;
end.
```

**Verwendung — minimal:**

```pascal
uses
  DX.Logger,
  DXLogger.Callstack; // <-- einmalig einbinden, kein weiterer Code nötig

try
  DoSomething;
except
  on E: Exception do
    DXLogError(E.Message, E); // Details enthält automatisch E.StackTrace
end;
```

**Verwendung — manueller Zugriff:**

```pascal
except
  on E: Exception do
  begin
    // Direktzugriff auf Stack-String (unabhängig von DX.Logger):
    Logger.Error(E.ClassName + ': ' + E.Message + sLineBreak + E.StackTrace);
  end;
end;
```

---

## 7. Build- & Deployment-Voraussetzungen

| Voraussetzung | Wert |
|---------------|------|
| Linker-Option „Map file" | **Detailed** (`-GD`) |
| `.map` neben EXE/BPL | ja |
| Stack-Frames im Compiler | empfohlen (`-$W+`) |
| DX.Logger Version | ≥ aktuell (feature/callstack-kompatibel) |

---

## 8. Risiken & Offene Punkte

| ID | Risiko / Frage | Mitigation |
|----|----------------|------------|
| R-1 | Map-Format variiert leicht zwischen Compiler-Versionen. | Parser tolerant gegen Whitespace/Zusatzspalten. |
| R-2 | x64 Stack Walking ohne `RtlCaptureStackBackTrace` instabil. | API zwingend benutzen, kein eigenes Frame-Walking unter x64. |
| R-3 | Map-Datei fehlt oder Projekt ohne `-GD` kompiliert. | Fallback F-15: fixer Hinweisstring `-- no call stack - map file not found --`, keine Exception. |
| R-4 | Konflikt mit anderen RTL-Hookern (z. B. madExcept). | Detection in `DXCallstackInstall`: vorhandene Hooks loggen; Option `ForceInstall`. |
| R-5 | `TDXLogger.OnBeforeLog`-Callback existiert noch nicht im Core. | Muss parallel in `DX.Logger.pas` ergänzt werden (kleines API-Delta). |
| O-1 | DLL-übergreifende Auflösung in v1.0 oder v1.1? | Aktuell v1.1 — in v1.0 nur EXE-eigene Map. |
| O-2 | JSON-Ausgabe in v1.0 oder Backlog? | Backlog (MAY, F-18). |

---

## 9. Abnahmekriterien

1. Test-Konsolenanwendung wirft `EAccessViolation` aus drei Ebenen Tiefe → `E.StackTrace` enthält korrekte Methodennamen + Quellzeilen.
2. Test mit benutzerdefinierter Exception → identisches Ergebnis.
3. Reraise-Test → Stack zeigt auf Original-Raise-Punkt.
4. Test ohne `.map`-Datei → keine Exception, `StackTrace` = `-- no call stack - map file not found --`.
5. Multi-Thread-Test (100 Threads × 1.000 Exceptions) → keine Crashes.
6. Performance-Test → Raise-Zeit ≤ 100 µs.
7. DX.Logger-Integration: `DXLogError(E.Message, E)` schreibt `E.StackTrace` ins `Details`-Feld ohne expliziten Code.
8. Single-Unit-Constraint: Unit allein über `uses DXLogger.Callstack` aktivierbar.

---

## 10. Roadmap

| Version | Inhalt |
|---------|--------|
| **0.1** | Stack-Capture + Map-Parser (EXE only) + Plain-Text-Ausgabe. Win32 + Win64. DX.Logger-Integration. |
| **0.2** | Multi-Modul-Auflösung (F-20). Konfigurations-Record vollständig. |
| **0.3** | JSON-Ausgabe, Map-Cache (`.map.cache`). |
| **1.0** | Stabilisierung, Doku, Freigabe für ELKE-Server. |
| **Backlog** | Linux-Port, verschlüsselte Map, Symbol-Server. |

---

## 11. Referenzen

- Embarcadero DocWiki: [`Exception.GetExceptionStackInfoProc`](https://docwiki.embarcadero.com/Libraries/en/System.SysUtils.Exception.GetExceptionStackInfoProc)
- Microsoft Docs: [`RtlCaptureStackBackTrace`](https://learn.microsoft.com/windows/win32/api/winnt/nf-winnt-rtlcapturestackbacktrace)
- JCL Debug (`JclDebug.pas`) — Open-Source-Referenzimplementierung (MPL 1.1)
- [DX.Logger README](../README.md)
- [DX.Logger Provider-Architektur](SEQ_PROVIDER.md)
