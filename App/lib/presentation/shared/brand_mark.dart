import 'package:flutter/material.dart';

/// The Necaramba mark (a keycap with Q and Й), matching the Dock icon.
class BrandMarkView extends StatelessWidget {
  const BrandMarkView({super.key, this.size = 26});
  final double size;
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: CustomPaint(size: Size.square(size), painter: _BrandMarkPainter()),
  );
}

class _BrandMarkPainter extends CustomPainter {
  static const plate = Color(0xff3b3fd9);
  static const side = Color(0xff2a2da6);
  static const face = Color(0xfff7f7fb);
  static const latin = Color(0xff1d1d1f);

  @override
  void paint(Canvas canvas, Size size) {
    final u = size.width / 100;
    RRect rect(double x, double y, double w, double h, double r) =>
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x * u, y * u, w * u, h * u),
          Radius.circular(r * u),
        );
    canvas.drawRRect(rect(0, 0, 100, 100, 22.5), Paint()..color = plate);
    canvas.drawRRect(rect(21, 22, 58, 60, 12), Paint()..color = side);
    canvas.drawRRect(rect(21, 17, 58, 58, 12), Paint()..color = face);
    void legend(String text, Color color, double x, double baseline, bool end) {
      final painter = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            fontFamily: '.AppleSystemUIFont',
            fontSize: 19 * u,
            fontWeight: FontWeight.w700,
            color: color,
            height: 1,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final ascent = painter.computeDistanceToActualBaseline(
        TextBaseline.alphabetic,
      );
      painter.paint(
        canvas,
        Offset((end ? x - painter.width : x) * 1, baseline - ascent),
      );
    }

    legend('Q', latin, 31 * u, 40 * u, false);
    legend('Й', plate, 69 * u, 66 * u, true);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
