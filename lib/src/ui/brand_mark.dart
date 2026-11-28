import 'package:material_ui/material_ui.dart';

/// The Belltide logo: a bell above a wave, on the launcher icon's deep teal.
///
/// Drawn from the same shapes as the launcher icon
/// (android/app/src/main/res/drawable/ic_launcher_foreground.xml), so the mark
/// inside the app matches the one on the home screen.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 28});

  final double size;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: const CustomPaint(painter: _BrandMarkPainter()),
      ),
    );
  }
}

class _BrandMarkPainter extends CustomPainter {
  const _BrandMarkPainter();

  static const Color _background = Color(0xFF0F3D4A);
  static const Color _bell = Color(0xFFF4E9D8);
  static const Color _wave = Color(0xFF7FD1C7);

  /// The part of the icon's 108-unit canvas that holds the bell and the wave.
  static const double _cropStart = 22;
  static const double _cropSize = 64;

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.shortestSide;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & Size.square(side), Radius.circular(side * 0.28)),
      Paint()..color = _background,
    );

    canvas.save();
    canvas.scale(side / _cropSize);
    canvas.translate(-_cropStart, -_cropStart);

    final wave = Path()
      ..moveTo(36, 77.5)
      ..quadraticBezierTo(40.5, 73.5, 45, 77.5)
      ..quadraticBezierTo(49.5, 81.5, 54, 77.5)
      ..quadraticBezierTo(58.5, 73.5, 63, 77.5)
      ..quadraticBezierTo(67.5, 81.5, 72, 77.5);
    canvas.drawPath(
      wave,
      Paint()
        ..color = _wave
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // The bell is drawn on a 24-unit grid, placed like the icon's <group>.
    canvas.translate(28.8, 22);
    canvas.scale(2.1);
    final bell = Path()
      ..moveTo(12, 4.4)
      ..cubicTo(8.75, 4.4, 7, 6.9, 7, 10.1)
      ..lineTo(7, 13.8)
      ..cubicTo(7, 15.1, 6.2, 16, 5, 16.6)
      ..lineTo(5, 17.6)
      ..lineTo(19, 17.6)
      ..lineTo(19, 16.6)
      ..cubicTo(17.8, 16, 17, 15.1, 17, 13.8)
      ..lineTo(17, 10.1)
      ..cubicTo(17, 6.9, 15.25, 4.4, 12, 4.4)
      ..close();
    final fill = Paint()..color = _bell;
    canvas.drawPath(bell, fill);
    canvas.drawCircle(const Offset(12, 3.5), 1.3, fill);
    canvas.drawCircle(const Offset(12, 20.1), 1.7, fill);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BrandMarkPainter oldDelegate) => false;
}
