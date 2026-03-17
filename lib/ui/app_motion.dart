import 'package:flutter/material.dart';

class AppMotion {
  const AppMotion._();

  static const Duration routeEnter = Duration(milliseconds: 280);
  static const Duration routeExit = Duration(milliseconds: 280);
  static const Duration playerRoute = Duration(milliseconds: 180);
  static const Duration sheetTransition = Duration(milliseconds: 220);
  static const Duration switchDuration = Duration(milliseconds: 280);
  static const Duration contentSwitchDuration = Duration(milliseconds: 320);
  static const Duration topBarFadeDuration = Duration(milliseconds: 320);
  static const Duration progressSizeDuration = Duration(milliseconds: 340);
  static const Duration progressFadeDuration = Duration(milliseconds: 300);

  static const Curve easeOut = Curves.linear;
  static const Curve easeIn = Curves.linear;
  static const Curve progressIn = Curves.linear;
  static const Curve progressOut = Curves.linear;
  static const Curve sheetEnterCurve = Curves.easeOutCubic;
  static const Curve sheetExitCurve = Curves.easeInCubic;

  static const Offset sheetLandscapeOffset = Offset(0.08, 0);
  static const Offset sheetPortraitOffset = Offset(0, 0.12);
  static const Offset sheetForwardOffset = Offset(0.12, 0);
  static const Offset sheetBackwardOffset = Offset(-0.12, 0);
}
