import 'app_log.dart';

/// 重试只执行尚未完成的步骤，避免重复注册监听器或重新打开已就绪的服务。
class StartupSequence {
  StartupSequence(this._steps);
  final List<Future<void> Function()> _steps;
  int _next = 0;

  Future<void> run() async {
    while (_next < _steps.length) {
      final watch = Stopwatch()..start();
      AppLog.debug({
        'event': 'startup_step',
        'attempt': _next,
        'outcome': 'started',
      });
      await _steps[_next]();
      AppLog.debug({
        'event': 'startup_step',
        'attempt': _next,
        'elapsedMs': watch.elapsedMilliseconds,
        'outcome': 'success',
      });
      _next++;
    }
  }
}
