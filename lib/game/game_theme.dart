// SPDX-License-Identifier: MIT
/// Bảng màu và text style của Mê cung ViScript — riêng khỏi Material theme
/// để màn chơi có không khí "game" thay vì "app" (nền tối indigo, nhấn amber).
library;

import 'package:flutter/material.dart';

/// Nền gradient màn chọn + màn chơi.
const Color kGameBgTop = Color(0xFF171E33);
const Color kGameBgBottom = Color(0xFF232B4D);

/// Panel/bảng chơi.
const Color kGamePanel = Color(0xFF1C2438);
const Color kGamePanelBorder = Color(0xFF3A4668);

/// Màu nhấn (nút chạy, sao, tiêu đề phụ).
const Color kGameAccent = Color(0xFFFBBF24);
const Color kGameAccentDark = Color(0xFF8A5A0B);

/// Trạng thái.
const Color kGameSuccess = Color(0xFF34D399);
const Color kGameDanger = Color(0xFFEF4444);

/// Chữ.
const Color kGameText = Color(0xFFE8ECF8);
const Color kGameTextDim = Color(0xFF9AA7C7);

/// Điểm nhấn robot (khớp sprite).
const Color kGameRobot = Color(0xFF4F8EF7);

const LinearGradient kGameBgGradient = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [kGameBgTop, kGameBgBottom],
);

const LinearGradient kRunButtonGradient = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [Color(0xFFFDC442), Color(0xFFF5A623)],
);

TextStyle gameTitleStyle(double size) => TextStyle(
      color: kGameText,
      fontSize: size,
      fontWeight: FontWeight.w800,
      letterSpacing: 1.2,
      height: 1.1,
    );

TextStyle gameDimStyle([double size = 13]) => TextStyle(
      color: kGameTextDim,
      fontSize: size,
      height: 1.25,
);

TextStyle gameStateStyle(Color color) => TextStyle(
      color: color,
      fontSize: 13,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.3,
);

/// Trang trí nút chạy chính: gradient amber, chữ nâu đậm, bóng nổi.
ButtonStyle runButtonStyle({EdgeInsets padding = const EdgeInsets.symmetric(
  horizontal: 28,
  vertical: 14,
)}) {
  return FilledButton.styleFrom(
    backgroundColor: Colors.transparent,
    foregroundColor: const Color(0xFF3D2B00),
    padding: padding,
    textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: 1.1),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
  );
}
