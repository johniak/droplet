import 'package:flutter/material.dart';

const kBgTop = Color(0xFF1E2A55);
const kBgMid = Color(0xFF0D1020);
const kBgBottom = Color(0xFF090B14);
const kAccent = Color(0xFF7C9DFF);
const kAccentAlt = Color(0xFF9B6BFF);
const kText = Color(0xFFEEF1FF);
const kTextDim = Color(0xFF8E96B8);
const kDanger = Color(0xFFFF8A8A);
const kOk = Color(0xFF5BE0A0);
const kGlass = Color(0x12FFFFFF); // biały α .07
const kGlassBorder = Color(0x1AFFFFFF); // biały α .10
const kDialogBg = Color(0xFF161B33);

const kRadiusCard = 14.0;
const kRadiusCover = 12.0;
const kRadiusBar = 26.0;
const kNavHeight = 64.0;

/// Dolny padding list pod pływającym paskiem nawigacji.
///
/// Powłoka ma `extendBody: true`, więc `MediaQuery.paddingOf(context).bottom`
/// wewnątrz gałęzi to już wysokość paska plus wcięcie systemowe (przy
/// nawigacji trójprzyciskowej sporo więcej niż przy gestach). Stała 104 dp
/// nie doszacowywała tego drugiego przypadku — liczymy realny odstęp.
double listBottomPad(BuildContext context) =>
    MediaQuery.paddingOf(context).bottom + 16;

const kPrimaryGradient = LinearGradient(colors: [kAccent, kAccentAlt]);

const kBgGradient = RadialGradient(
  center: Alignment(-0.8, -1.0),
  radius: 1.6,
  colors: [kBgTop, kBgMid, kBgBottom],
  stops: [0.0, 0.45, 1.0],
);
