import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

void main() {
  final iconDir = Directory('assets/icons');
  if (!iconDir.existsSync()) {
    iconDir.createSync(recursive: true);
  }

  final appIcon = _buildAppIcon(size: 1024);
  File('assets/icons/app_icon.png')
    ..createSync(recursive: true)
    ..writeAsBytesSync(img.encodePng(appIcon));

  final splashIcon = _buildSplashIcon(size: 960);
  File('assets/icons/splash_icon.png')
    ..createSync(recursive: true)
    ..writeAsBytesSync(img.encodePng(splashIcon));
}

img.Image _buildAppIcon({required int size}) {
  final image = img.Image(width: size, height: size);
  img.fill(image, color: img.ColorRgb8(0, 0, 0));
  _drawGlyph(
    image,
    glyphColor: img.ColorRgb8(255, 255, 255),
    margin: size * 0.18,
    strokeWidth: size * 0.07,
  );
  return image;
}

img.Image _buildSplashIcon({required int size}) {
  final image = img.Image(width: size, height: size, numChannels: 4);
  img.fill(image, color: img.ColorUint8.rgba(0, 0, 0, 0));
  _drawGlyph(
    image,
    glyphColor: img.ColorRgb8(255, 255, 255),
    margin: size * 0.12,
    strokeWidth: size * 0.085,
  );
  return image;
}

void _drawGlyph(
  img.Image image, {
  required img.Color glyphColor,
  required double margin,
  required double strokeWidth,
}) {
  final width = image.width.toDouble();
  final height = image.height.toDouble();
  final centerY = height * 0.5;
  final chevronLeft = margin;
  final chevronMidX = width * 0.47;
  final chevronTopY = height * 0.29;
  final chevronBottomY = height * 0.71;
  final underscoreStartX = width * 0.58;
  final underscoreEndX = width - margin;
  final underscoreY = height * 0.69;

  _drawThickLine(
    image,
    chevronLeft,
    chevronTopY,
    chevronMidX,
    centerY,
    glyphColor,
    strokeWidth,
  );
  _drawThickLine(
    image,
    chevronLeft,
    chevronBottomY,
    chevronMidX,
    centerY,
    glyphColor,
    strokeWidth,
  );
  _drawThickLine(
    image,
    underscoreStartX,
    underscoreY,
    underscoreEndX,
    underscoreY,
    glyphColor,
    strokeWidth,
  );
}

void _drawThickLine(
  img.Image image,
  double x1,
  double y1,
  double x2,
  double y2,
  img.Color color,
  double strokeWidth,
) {
  final radius = strokeWidth / 2;
  final dx = x2 - x1;
  final dy = y2 - y1;
  final distance = math.sqrt(dx * dx + dy * dy);
  final steps = math.max(1, distance.ceil());

  for (var step = 0; step <= steps; step++) {
    final t = step / steps;
    final x = x1 + dx * t;
    final y = y1 + dy * t;
    img.fillCircle(
      image,
      x: x.round(),
      y: y.round(),
      radius: radius.round(),
      color: color,
    );
  }
}
