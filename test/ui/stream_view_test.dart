import 'package:flutter_test/flutter_test.dart';
import 'package:notebase/ui/stream_view.dart';

void main() {
  group('dayLabel（ui-design §4 组头）', () {
    test('今天 / 昨天', () {
      final now = DateTime(2026, 9, 10, 15, 30);
      expect(dayLabel(now, now: now), '今天');
      expect(dayLabel(DateTime(2026, 9, 9, 23, 59), now: now), '昨天');
    });

    test('本年内 M月d日，跨年带年份', () {
      final now = DateTime(2026, 9, 10);
      expect(dayLabel(DateTime(2026, 9, 1), now: now), '9月1日');
      expect(dayLabel(DateTime(2025, 12, 31), now: now), '2025年12月31日');
    });

    // 夏令时切换日只有 23 小时，用本地零点相减会被 inDays 截断成 0 天，
    // 把「昨天」错标成「今天」。本组用例在 DST 时区（TZ=Europe/Berlin、
    // TZ=America/New_York）下运行才有区分度，非 DST 时区恒过。
    test('跨夏令时切换日仍判定为昨天', () {
      // 2026 年 DST 起始：柏林 3/29、纽约 3/8
      expect(dayLabel(DateTime(2026, 3, 29), now: DateTime(2026, 3, 30)), '昨天');
      expect(dayLabel(DateTime(2026, 3, 8), now: DateTime(2026, 3, 9)), '昨天');
    });
  });
}
