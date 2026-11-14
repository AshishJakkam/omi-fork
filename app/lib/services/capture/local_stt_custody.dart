/// Selected capture route, not an entitlement decision. Local speech is an
/// asynchronous consumer: enqueueing to it is never an audio-delivery receipt.
/// CaptureController supplies its resolved route; no preference/service lookup.
abstract final class LocalSttCustody {
  static bool selectedLocalRoute = false;
  static bool get keepsPhoneAudio => selectedLocalRoute;

  /// When the live lane last finished a window on the local engine, or null.
  ///
  /// The live socket and the batch runner share one model behind one native mutex, so a batch
  /// inference in flight makes the next live window wait for it - measured at 14.8 s for 3 s of
  /// audio while a 1,000-recording backlog was transcribing. The runner reads this and steps aside
  /// while live windows are arriving. It is a timestamp rather than a flag so it cannot latch: with
  /// no live window for [liveQuietWindow] the backlog resumes on its own.
  static DateTime? lastLiveWindowAt;

  static const Duration liveQuietWindow = Duration(seconds: 30);

  static bool get liveLaneActive {
    final last = lastLiveWindowAt;
    return last != null && DateTime.now().difference(last) < liveQuietWindow;
  }
}
