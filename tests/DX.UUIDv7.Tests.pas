unit DX.UUIDv7.Tests;

interface

uses
  DUnitX.TestFramework,
  System.SysUtils,
  System.RegularExpressions,
  DX.UUIDv7;

type
  [TestFixture]
  TUUIDv7Tests = class
  public
    [Test] procedure TestVersionBitsAre7;
    [Test] procedure TestVariantBitsAreRfc4122;
    [Test] procedure TestStringRoundTrip;
    [Test] procedure TestStringFormatLowercaseDashedNoBraces;
    [Test] procedure TestMonotonicNonDecreasing;
    [Test] procedure TestTryParseRejectsNonV7;
    [Test] procedure TestTryParseAcceptsBraces;
    [Test] procedure TestTryParseRejectsGarbage;
  end;

implementation

procedure TUUIDv7Tests.TestVersionBitsAre7;
var
  LGuid: TGUID;
begin
  LGuid := CreateGuidV7;
  // Version-Nibble sitzt in Bits 12-15 von D3 (Big-Endian-Sicht: Byte 6 der RFC-Sequenz).
  // In Delphis TGUID.D3 (Word) sind die Version-Bits die obersten 4 Bits.
  Assert.AreEqual<Byte>(7, (LGuid.D3 shr 12) and $F,
    'Version-Nibble muss 7 sein (RFC 9562)');
end;

procedure TUUIDv7Tests.TestVariantBitsAreRfc4122;
var
  LGuid: TGUID;
begin
  LGuid := CreateGuidV7;
  // Variant-Bits: obersten 2 Bits von D3 (Word -> Byte 0) muessen 10b sein
  Assert.AreEqual<Byte>(2, (LGuid.D4[0] shr 6) and $3,
    'Variant-Bits muessen RFC-4122 (10b) sein');
end;

procedure TUUIDv7Tests.TestStringRoundTrip;
var
  LGuid, LRound: TGUID;
  LStr: string;
begin
  LGuid := CreateGuidV7;
  LStr := GuidV7ToString(LGuid);
  Assert.IsTrue(TryParseGuidV7(LStr, LRound), 'TryParse muss eigene Ausgabe akzeptieren');
  Assert.IsTrue(IsEqualGUID(LGuid, LRound), 'Round-Trip muss identische GUID liefern');
end;

procedure TUUIDv7Tests.TestStringFormatLowercaseDashedNoBraces;
var
  LStr: string;
const
  CPattern = '^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$';
begin
  LStr := GuidV7ToString(CreateGuidV7);
  Assert.IsTrue(TRegEx.IsMatch(LStr, CPattern),
    'Format muss lowercase mit Bindestrichen ohne Klammern sein, Version-Nibble 7: ' + LStr);
end;

procedure TUUIDv7Tests.TestMonotonicNonDecreasing;
var
  LPrev, LCurr: string;
  i: Integer;
  LStrictIncreaseSeen: Boolean;
begin
  LStrictIncreaseSeen := False;
  LPrev := GuidV7ToString(CreateGuidV7);
  for i := 1 to 200 do
  begin
    // Sleep periodically so the loop traverses multiple ms buckets —
    // otherwise 200 tight iterations all share the same timestamp and
    // the test only verifies equality, not non-decreasing order.
    if i mod 50 = 0 then
      Sleep(2);

    LCurr := GuidV7ToString(CreateGuidV7);
    // String-Vergleich auf 48-bit-Timestamp-Praefix (erste 13 hex-Zeichen + Bindestrich)
    // Wir akzeptieren Gleichheit (Burst innerhalb 1ms), aber kein Rueckwaerts.
    Assert.IsTrue(Copy(LCurr, 1, 13) >= Copy(LPrev, 1, 13),
      Format('Timestamp-Praefix darf nicht rueckwaerts laufen: prev=%s curr=%s', [LPrev, LCurr]));
    if Copy(LCurr, 1, 13) > Copy(LPrev, 1, 13) then
      LStrictIncreaseSeen := True;
    LPrev := LCurr;
  end;
  Assert.IsTrue(LStrictIncreaseSeen,
    'Timestamp-Praefix muss im Laufe des Tests mindestens einmal strikt steigen — sonst ist der Test nicht aussagekraeftig');
end;

procedure TUUIDv7Tests.TestTryParseRejectsNonV7;
var
  LGuid: TGUID;
begin
  // Klassische UUIDv4-String: Version-Nibble = 4
  Assert.IsFalse(
    TryParseGuidV7('a0b1c2d3-1234-4567-89ab-cdef01234567', LGuid),
    'UUIDv4 muss abgelehnt werden');
end;

procedure TUUIDv7Tests.TestTryParseAcceptsBraces;
var
  LGuid, LParsed: TGUID;
  LWithBraces: string;
begin
  LGuid := CreateGuidV7;
  LWithBraces := '{' + GuidV7ToString(LGuid) + '}';
  Assert.IsTrue(TryParseGuidV7(LWithBraces, LParsed),
    'TryParse muss {...}-Form akzeptieren');
  Assert.IsTrue(IsEqualGUID(LGuid, LParsed));
end;

procedure TUUIDv7Tests.TestTryParseRejectsGarbage;
var
  LGuid: TGUID;
begin
  Assert.IsFalse(TryParseGuidV7('', LGuid), 'Leerstring muss abgelehnt werden');
  Assert.IsFalse(TryParseGuidV7('not-a-guid', LGuid));
  Assert.IsFalse(TryParseGuidV7('01952f7e-3b2a-7000-8a4c-d5e6f7890abc-extra', LGuid),
    'Ueberlange Strings muessen abgelehnt werden');
end;

initialization
  TDUnitX.RegisterTestFixture(TUUIDv7Tests);

end.
