/// Tracks a temporary playback speed override and its original value.
class TemporaryPlaybackSpeed {
  TemporaryPlaybackSpeed(this.originalSpeed);

  final double originalSpeed;
  bool active = false;

  double press() {
    active = true;
    return 2.0;
  }

  double release() {
    active = false;
    return originalSpeed;
  }

  double cancel() => release();
}
