/// Connection states of the game socket (Phase 5).
///
/// This enum lives in the domain layer — not in the socket client —
/// on purpose: it is shared vocabulary, not a transport detail. The
/// data layer reports it, the provider graph stores it on the
/// UI-facing state, and the presentation layer switches on it (the
/// connection banner, the game screen's guards). Keeping it here,
/// dependency-free, lets all three layers name it without the
/// presentation layer importing the data layer (M-07 boundary).
library;

/// The game socket's connection state, as the UI sees it.
enum GameSocketConnectionState {
  /// No socket (never connected, or manually disconnected).
  disconnected,

  /// The first handshake is in flight.
  connecting,

  /// Live socket.
  connected,

  /// The socket dropped; the manager is retrying with back-off.
  reconnecting,
}
