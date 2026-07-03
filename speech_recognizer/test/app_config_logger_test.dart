import 'package:flutter_test/flutter_test.dart';
import 'package:speech_recognizer/app.dart';
import 'package:speech_recognizer/app_logger.dart';

void main() {
  test('AppConfigs uses Spanish recognizer language', () {
    expect(AppConfigs.language, 'es');
  });

  test('AppLogger methods are callable without throwing', () {
    expect(() => AppLogger.debug('debug message'), returnsNormally);
    expect(() => AppLogger.info('info message'), returnsNormally);
    expect(() => AppLogger.warning('warning message'), returnsNormally);
    expect(() => AppLogger.error('error message'), returnsNormally);
    expect(() => AppLogger.fatal('fatal message'), returnsNormally);
  });
}
