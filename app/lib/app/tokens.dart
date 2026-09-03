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
const kGlass = Color(0x12FFFFFF); // white α .07
const kGlassBorder = Color(0x1AFFFFFF); // white α .10
const kDialogBg = Color(0xFF161B33);

const kRadiusCard = 14.0;
const kRadiusCover = 12.0;
const kRadiusBar = 26.0;
const kNavHeight = 64.0;

/// Bottom padding for lists under the floating navigation bar.
///
/// The shell uses `extendBody: true`, so `MediaQuery.paddingOf(context).bottom`
/// inside a branch already covers the bar height plus the system inset (quite
/// a bit more with three-button navigation than with gestures). A constant
/// 104 dp under-estimated the latter case — we measure the real gap.
double listBottomPad(BuildContext context) =>
    MediaQuery.paddingOf(context).bottom + 16;

const kPrimaryGradient = LinearGradient(colors: [kAccent, kAccentAlt]);

const kBgGradient = RadialGradient(
  center: Alignment(-0.8, -1.0),
  radius: 1.6,
  colors: [kBgTop, kBgMid, kBgBottom],
  stops: [0.0, 0.45, 1.0],
);
