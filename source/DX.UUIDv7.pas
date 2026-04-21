unit DX.UUIDv7;

{
  DX.UUIDv7 - RFC 9562 UUIDv7 Generator for Delphi

  Copyright (c) 2026 Olaf Monien
  SPDX-License-Identifier: MIT

  UUIDv7-Layout (128 bit):
    +------------------------------------------------------------------+
    | 48-bit Unix-ms-Timestamp | 4 bit ver=7 | 12-bit rand_a            |
    | 2 bit var=10b            | 62-bit rand_b                          |
    +------------------------------------------------------------------+

  Randomness-Quelle: OS-RNG via CreateGUID (unter Windows CryptGenRandom/
  UuidCreate). Threadsicher und kryptographisch stark — keine Randomize-
  Initialisierung noetig.
}

interface

uses
  System.SysUtils;

/// <summary>
/// Erzeugt eine RFC-9562-UUIDv7. Zeitgeordnet pro Quelle und Millisekunde,
/// kollisionsarm durch 74 bit Random-Anteil.
/// </summary>
function CreateGuidV7: TGUID;

/// <summary>
/// Liefert den Standard-Stringrepraesentation: lowercase, mit Bindestrichen,
/// ohne geschweifte Klammern. Beispiel: '01952f7e-3b2a-7000-8a4c-d5e6f7890abc'.
/// </summary>
function GuidV7ToString(const AGuid: TGUID): string;

/// <summary>
/// Versucht, einen RFC-Standardstring (mit oder ohne Klammern, case-insensitiv)
/// als UUIDv7 zu parsen. Liefert False bei ungueltiger Laenge, ungueltigen
/// Zeichen oder wenn die Version-Bits nicht 7 sind.
/// </summary>
function TryParseGuidV7(const AStr: string; out AGuid: TGUID): Boolean;

implementation

uses
  System.DateUtils;

function UnixMilliseconds: Int64;
var
  LNow: TDateTime;
begin
  // UTC-Now in Millisekunden seit Unix-Epoch. Einmal Now aufrufen und cachen, damit
  // Sekunden- und Millisekunden-Anteil garantiert aus demselben Moment stammen
  // (sonst Race an Sekundengrenzen, bis zu 999ms off).
  LNow := TTimeZone.Local.ToUniversalTime(Now);
  Result := DateTimeToUnix(LNow, False) * 1000 + MilliSecondOf(LNow);
end;

function CreateGuidV7: TGUID;
var
  LMs: Int64;
  LBytes: array[0..15] of Byte;
  LRand: TGUID;
  i: Integer;
begin
  LMs := UnixMilliseconds;

  // Bytes 0-5: 48-bit Unix-ms-Timestamp, big-endian
  LBytes[0] := Byte(LMs shr 40);
  LBytes[1] := Byte(LMs shr 32);
  LBytes[2] := Byte(LMs shr 24);
  LBytes[3] := Byte(LMs shr 16);
  LBytes[4] := Byte(LMs shr 8);
  LBytes[5] := Byte(LMs);

  // Bytes 6-15: Random aus OS-RNG (CreateGUID -> CryptGenRandom/UuidCreate).
  // Threadsicher und kryptographisch stark; 10 von 16 TGUID-Bytes reichen fuer die
  // benoetigten 74 Random-Bits (12 bit rand_a + 62 bit rand_b).
  CreateGUID(LRand);
  Move(LRand, LBytes[6], 10);

  // Version 7 in Byte 6 (oberes Nibble): 0111xxxx
  LBytes[6] := (LBytes[6] and $0F) or $70;

  // Variant 10b in Byte 8 (oberste 2 Bits): 10xxxxxx
  LBytes[8] := (LBytes[8] and $3F) or $80;

  // In TGUID-Layout uebertragen. TGUID-Felder sind Little-Endian fuer D1/D2/D3 in MSWindows;
  // RFC-Standard ist Big-Endian. Wir packen so, dass GuidToString (Delphi-Default) das
  // gewuenschte Big-Endian-Layout liefert.
  Result.D1 := (Cardinal(LBytes[0]) shl 24) or (Cardinal(LBytes[1]) shl 16) or
               (Cardinal(LBytes[2]) shl 8)  or Cardinal(LBytes[3]);
  Result.D2 := (Word(LBytes[4]) shl 8) or Word(LBytes[5]);
  Result.D3 := (Word(LBytes[6]) shl 8) or Word(LBytes[7]);
  for i := 0 to 7 do
    Result.D4[i] := LBytes[8 + i];
end;

function GuidV7ToString(const AGuid: TGUID): string;
begin
  // Delphi-Default: '{XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX}' (uppercase, mit Klammern).
  // Wir entfernen Klammern und lowercase-en.
  Result := AGuid.ToString.Replace('{', '').Replace('}', '').ToLower;
end;

function TryParseGuidV7(const AStr: string; out AGuid: TGUID): Boolean;
var
  LStripped: string;
begin
  Result := False;
  AGuid := TGUID.Empty;

  LStripped := AStr.Trim;
  if LStripped = '' then
    Exit;

  // Klammer-Form akzeptieren: "{...}"
  if LStripped.StartsWith('{') and LStripped.EndsWith('}') then
    LStripped := LStripped.Substring(1, LStripped.Length - 2);

  // Standard-Laenge ist 36 (8-4-4-4-12 + 4 Bindestriche)
  if Length(LStripped) <> 36 then
    Exit;

  try
    AGuid := TGUID.Create('{' + LStripped + '}');
  except
    on EConvertError do
      Exit;
  end;

  // Version-Bits pruefen (Byte 6 der RFC-Sequenz = D3 top nibble)
  if ((AGuid.D3 shr 12) and $F) <> 7 then
  begin
    AGuid := TGUID.Empty;
    Exit;
  end;

  Result := True;
end;

end.
