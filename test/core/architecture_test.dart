import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 架构不变式（dev-plan §1.3）：`lib/core/` 零 Flutter 依赖，
/// 保证核心逻辑可纯 Dart 运行、测试与跨平台复用。
///
/// M3 评审把「core 无 Flutter 依赖」列为值得保持的承诺——此测试让它
/// 从口头约定变成机器可验证：任何人往 core 里 import flutter 都会红。
void main() {
  test('lib/core/** 不得出现 package:flutter 引用', () {
    final offenders = <String>[];
    for (final entity in Directory('lib/core').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (entity.readAsStringSync().contains('package:flutter')) {
        offenders.add(entity.path);
      }
    }
    expect(
      offenders,
      isEmpty,
      reason: 'core 层必须保持纯 Dart，违规文件：$offenders',
    );
  });
}
