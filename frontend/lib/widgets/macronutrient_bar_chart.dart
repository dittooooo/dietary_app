import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../color/app_colors.dart';

/// 共用比例尺的營養素圖表；文字獨立配置，避免高比例柱體擠壓標籤。
class MacronutrientBarChart extends StatelessWidget {
  const MacronutrientBarChart({
    super.key,
    required this.carbsPercent,
    required this.proteinPercent,
    required this.fatPercent,
    required this.carbsGrams,
    required this.proteinGrams,
    required this.fatGrams,
  });

  final int carbsPercent, proteinPercent, fatPercent;
  final double carbsGrams, proteinGrams, fatGrams;

  @override
  Widget build(BuildContext context) {
    final percentages = [carbsPercent, proteinPercent, fatPercent];
    final grams = [carbsGrams, proteinGrams, fatGrams];
    const labels = ['碳水化合物', '蛋白質', '脂肪'];
    const colors = [Color(0xFF7C83FD), Color(0xFFFF7A45), Color(0xFFFFB800)];
    final baseStyle = DefaultTextStyle.of(context).style;
    final tickStyle = baseStyle.copyWith(
      fontSize: 10,
      color: Colors.black45,
      fontWeight: FontWeight.w500,
    );
    final percentStyle = baseStyle.copyWith(
      fontSize: 13,
      color: AppColors.textPrimary,
      fontWeight: FontWeight.bold,
    );
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);

    Size measure(
      String text,
      TextStyle style, [
      double width = double.infinity,
    ]) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: direction,
        textScaler: scaler,
      )..layout(maxWidth: width);
      final size = painter.size;
      painter.dispose();
      return size;
    }

    final tickSize = measure('100%', tickStyle);
    final axisWidth = tickSize.width.ceilToDouble() + 12;
    const rightPadding = 8.0;
    const plotHeight = 140.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final slotWidth = math.max(
          1.0,
          (constraints.maxWidth - axisWidth - rightPadding) / 3,
        );
        final percentageHeight = percentages
            .map((value) => measure('$value%', percentStyle, slotWidth).height)
            .reduce(math.max)
            .ceilToDouble();
        final plotTop = percentageHeight + 4;
        final baseline = plotTop + plotHeight;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: baseline + tickSize.height / 2,
              child: Stack(
                children: [
                  for (final tick in [100, 75, 50, 25, 0])
                    Positioned(
                      top:
                          plotTop +
                          (1 - tick / 100) * plotHeight -
                          tickSize.height / 2,
                      left: 0,
                      right: rightPadding,
                      height: tickSize.height,
                      child: Row(
                        children: [
                          SizedBox(
                            width: axisWidth,
                            child: Text('$tick%', style: tickStyle),
                          ),
                          Expanded(
                            child: Container(
                              key: ValueKey('macro-grid-$tick'),
                              height: 1,
                              color: Colors.black.withValues(alpha: 0.06),
                            ),
                          ),
                        ],
                      ),
                    ),
                  Positioned(
                    top: 0,
                    left: axisWidth,
                    right: rightPadding,
                    height: baseline,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (var i = 0; i < 3; i++)
                          Expanded(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '${percentages[i]}%',
                                  style: percentStyle,
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 4),
                                Container(
                                  key: ValueKey('macro-bar-$i'),
                                  width: math.min(52.0, slotWidth * 0.65),
                                  height:
                                      percentages[i].clamp(0, 100) /
                                      100 *
                                      plotHeight,
                                  decoration: BoxDecoration(
                                    color: colors[i],
                                    borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(8),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: EdgeInsets.only(left: axisWidth, right: rightPadding),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < 3; i++)
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            labels[i],
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            '約 ${grams[i].round()} g',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.black54,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
