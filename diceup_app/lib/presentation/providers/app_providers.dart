/// The Riverpod composition root (M3.3, H-07; D-06).
///
/// The single wiring point (SDD §3.2): repositories → use cases →
/// [OfflineGameController] → screens. [main] awaits
/// [initializeApp] before the first frame and [DiceUpApp] exposes
/// the completed [StartupResult] here, so every provider below
/// reads from one startup outcome and no screen constructs a
/// repository, a use case or a controller directly (enforced by
/// `tool/check_boundaries.sh`).
///
/// The domain stays framework-free: [OfflineGameController] is
/// plain Dart and takes its collaborators by constructor injection;
/// this file is the only place that constructs it in production
/// code. The view ([GameScreen]) reads the controller through
/// [offlineGameControllerProvider] and holds no copy of the game
/// state — a state change driven through the provider is what the
/// screen renders, never a second copy.
///
/// Lifecycle: [offlineGameControllerProvider] is `autoDispose`. The
/// game screen watches it while mounted, which keeps the provider
/// alive; when the screen leaves, the last listener drops and the
/// provider disposes the controller (timers cancelled) via
/// `ref.onDispose`. The screen never disposes a provider-owned
/// controller itself. A fresh navigation to the game route creates
/// a fresh controller — a fresh match per navigation, exactly as
/// the pre-Riverpod screen built a fresh controller per screen.
///
/// Tests override providers in a [ProviderScope]: see
/// `test/test_providers.dart`. Overriding [diceRollerProvider]
/// (fixed dice), [feedbackServiceProvider] (recording fake) or
/// [vibrationEnabledProvider] replaces the production wiring
/// without touching the screen — those are the only seams, and
/// there is exactly one of each: [GameScreen] takes no controller,
/// dice, feedback or vibration parameter anymore.
///
/// Single-scope rule: there is exactly one [ProviderScope] per
/// widget tree. [DiceUpApp] owns the app tree's scope (with named
/// test seams — fixed dice, fake feedback, vibration flag — for
/// tests); a bare screen's tests build their own scope via
/// `test/test_providers.dart`. Never nest scopes: Riverpod owns a
/// non-overridden provider in the outermost scope, so its
/// transitive watches resolve there and cannot see an inner
/// scope's overrides — the controller graph would read the
/// un-overridden [startupResultProvider] and fail (verified by
/// probe 2026-11-22: a [DiceUpApp] wrapped in an outer scope
/// fails to start a match, while the same tree with a single
/// scope works).
///
/// Not yet migrated (explicit next step, recorded in
/// docs/IMPLEMENTATION-PLAN.md M3.3): the settings, history,
/// statistics, home and setup screens still read their
/// repositories through [AppDependenciesScope] (M1.6). They are
/// migrated one screen at a time; the game flow + startup wiring
/// in this file is the M3.3 scope.
library;

import 'dart:async';

import 'package:diceup/data/local/app_dependencies.dart';
import 'package:diceup/data/local/app_startup.dart';
import 'package:diceup/data/online/auth_api_client.dart';
import 'package:diceup/data/online/auth_config.dart';
import 'package:diceup/data/online/auth_models.dart';
import 'package:diceup/data/online/auth_service.dart';
import 'package:diceup/data/online/game_api_client.dart';
import 'package:diceup/data/online/game_models.dart';
import 'package:diceup/data/online/game_room_service.dart';
import 'package:diceup/data/online/game_socket_client.dart';
import 'package:diceup/data/online/token_storage.dart';
import 'package:diceup/domain/engine/board.dart';
import 'package:diceup/domain/engine/dice_roller.dart';
import 'package:diceup/domain/engine/game_state.dart';
import 'package:diceup/domain/engine/ludo_game.dart';
import 'package:diceup/domain/offline_game_controller.dart';
import 'package:diceup/domain/online/connection_state.dart';
import 'package:diceup/domain/repositories/local_match_repository.dart';
import 'package:diceup/domain/repositories/local_player_repository.dart';
import 'package:diceup/domain/repositories/local_statistics_repository.dart';
import 'package:diceup/domain/repositories/settings_repository.dart';
import 'package:diceup/domain/repositories/snapshot_repository.dart';
import 'package:diceup/domain/snapshot_writer.dart';
import 'package:diceup/domain/usecases/apply_move.dart';
import 'package:diceup/domain/usecases/roll_dice.dart';
import 'package:diceup/domain/usecases/start_offline_match.dart';
import 'package:diceup/presentation/feedback/feedback_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The completed startup outcome. Must be provided by the app
/// entry ([DiceUpApp] overrides it with the awaited
/// [initializeApp] result, or with its own initializer's result in
/// tests). There is no default: a screen that reads the graph
/// without a provided startup fails loudly instead of silently
/// playing with the wrong repositories.
final startupResultProvider = Provider<StartupResult>(
  (ref) => throw UnimplementedError(
    'No StartupResult provided — the app must run inside DiceUpApp '
    '(or a test ProviderScope overriding startupResultProvider).',
  ),
);

/// The repositories built at startup, or null when the database
/// could not be opened even after recovery (degraded play: the
/// match stays playable, nothing is persisted).
final appDependenciesProvider = Provider<AppDependencies?>(
  (ref) => ref.watch(startupResultProvider).dependencies,
);

/// Repository providers: each is the same instance the startup
/// dependencies hold — one construction site, no second copy.
final localMatchRepositoryProvider = Provider<LocalMatchRepository?>(
  (ref) => ref.watch(appDependenciesProvider)?.matches,
);

final localStatisticsRepositoryProvider = Provider<LocalStatisticsRepository?>(
  (ref) => ref.watch(appDependenciesProvider)?.statistics,
);

final settingsRepositoryProvider = Provider<SettingsRepository?>(
  (ref) => ref.watch(appDependenciesProvider)?.settings,
);

final localPlayerRepositoryProvider = Provider<LocalPlayerRepository?>(
  (ref) => ref.watch(appDependenciesProvider)?.players,
);

final snapshotRepositoryProvider = Provider<SnapshotRepository?>(
  (ref) => ref.watch(appDependenciesProvider)?.snapshots,
);

/// The serialised snapshot writer (FR-29): the dependencies'
/// single ordered [SnapshotSaver], shared by the game screen's
/// roll saves and the controller's move saves.
final snapshotWriterProvider = Provider<SnapshotWriter?>(
  (ref) => ref.watch(appDependenciesProvider)?.snapshotSaver,
);

/// Dice source. Null in production (the engine's random roller);
/// tests override with a [FixedDiceRoller].
final diceRollerProvider = Provider<DiceRoller?>((ref) => null);

/// Haptics behind the [FeedbackService] abstraction (M1.7, D-32).
/// Production sends one light impact per completed move; tests
/// override with a recording fake.
final feedbackServiceProvider = Provider<FeedbackService>(
  (ref) => const HapticFeedbackService(),
);

/// Vibration override. Null in production (the controller resolves
/// the persisted setting itself); tests override with `true` /
/// `false` to pin the gate without touching storage.
final vibrationEnabledProvider = Provider<bool?>((ref) => null);

// -- Use cases (M3.1) -----------------------------------------------------

/// Starts a fresh offline match from a [MatchSetup] (thin
/// orchestration over the engine; the dice source comes from
/// [diceRollerProvider]).
final startOfflineMatchProvider = Provider<StartOfflineMatch>(
  (ref) => StartOfflineMatch(diceRoller: ref.watch(diceRollerProvider)),
);

/// Rolls the dice for the current player (synchronous, no
/// persistence of its own — the controller persists the result).
final rollDiceProvider = Provider<RollDice>((ref) => RollDice());

/// Applies one move and owns its persistence side effects
/// (snapshot-after-move, exactly-once completion recording).
/// Null when there is nothing to persist into (degraded startup):
/// the controller then applies the engine move without recording,
/// exactly as it did before M3.3.
final applyMoveProvider = Provider<ApplyMove?>((ref) {
  final matches = ref.watch(localMatchRepositoryProvider);
  final snapshots = ref.watch(snapshotRepositoryProvider);
  if (matches == null || snapshots == null) return null;
  return ApplyMove(
    matches: matches,
    snapshots: snapshots,
    snapshotWriter: ref.watch(snapshotWriterProvider),
  );
});

// -- Controller -----------------------------------------------------------

/// The offline match controller, owned by the provider graph.
///
/// Constructed from the repository, use-case and feedback
/// providers above; disposed (timers cancelled) when the last
/// listener — the game screen — leaves. Behaviour is bit-identical
/// to the pre-Riverpod screen: same 700–1,199 ms AI pacing (D-31),
/// same 6 x 90 ms dice tumble, same status strings, same win
/// trigger, same snapshot/completion semantics.
///
/// Vibration resolution preserves the M3.2 screen's exact
/// expression: the override wins, otherwise the startup-loaded
/// value, otherwise on. Note `loadedSettings` is currently always
/// empty from [AppDependencies.fromDatabase] (startup loads the
/// settings into [StartupResult.settings] instead), so the
/// effective initial value is on and the persisted value is picked
/// up by the controller's repository refresh after start — the
/// quirk is preserved, not silently fixed, in M3.3.
final offlineGameControllerProvider =
    Provider.autoDispose<OfflineGameController>((ref) {
      final dependencies = ref.watch(appDependenciesProvider);
      final feedback = ref.watch(feedbackServiceProvider);
      final vibrationOverride = ref.watch(vibrationEnabledProvider);
      final controller = OfflineGameController(
        diceRoller: ref.watch(diceRollerProvider),
        matches: ref.watch(localMatchRepositoryProvider),
        settings: ref.watch(settingsRepositoryProvider),
        snapshots: ref.watch(snapshotRepositoryProvider),
        snapshotWriter: ref.watch(snapshotWriterProvider),
        startOfflineMatch: ref.watch(startOfflineMatchProvider),
        rollDice: ref.watch(rollDiceProvider),
        applyMove: ref.watch(applyMoveProvider),
        vibrationEnabled:
            vibrationOverride ??
            (dependencies?.loadedSettings['vibration_enabled'] != '0'),
        vibrationRefreshEnabled: vibrationOverride == null,
        // One light haptic per completed move (M1.7, D-32), wired
        // here — the controller's [onMoveApplied] hook — so the
        // screen never touches haptics directly. Fire-and-forget
        // and never throwing into the turn loop, exactly as the
        // screen's `_vibrateOnMove` did.
        onMoveApplied: () {
          unawaited(feedback.vibrateMove().catchError((_) {}));
        },
      );
      ref.onDispose(controller.dispose);
      return controller;
    });

// -- Online auth (Phase 5, Stage 2) --------------------------------------
//
// The auth graph follows the same rule as the offline graph: this
// file is the only construction site. Screens read the session
// through [authStateProvider] and never construct a client, storage
// or service (enforced by `tool/check_boundaries.sh` — new
// presentation files must not import the data layer).
//
// [AuthNotifier] owns the UI-facing auth state; [AuthService] owns
// the session (API + secure storage + silent refresh). The notifier
// restores the persisted session once, when first watched — Home
// watches it for the Play Online entry, so restore happens on
// launch without any change to [main].

/// Auth API configuration (base URL; dart-define override, loopback
/// dev default). Overridden in tests to point at the test backend.
final authConfigProvider = Provider<AuthConfig>(
  (ref) => AuthConfig.fromEnvironment(),
);

/// The REST client for the backend auth + users API.
final authApiClientProvider = Provider<AuthApiClient>((ref) {
  final client = AuthApiClient(config: ref.watch(authConfigProvider));
  ref.onDispose(client.close);
  return client;
});

/// Secure token storage (platform secure storage only).
final tokenStorageProvider = Provider<TokenStorage>(
  (ref) => SecureTokenStorage(),
);

/// The session-owning auth service.
final authServiceProvider = Provider<AuthService>(
  (ref) => AuthService(
    client: ref.watch(authApiClientProvider),
    storage: ref.watch(tokenStorageProvider),
  ),
);

/// UI-facing auth state, owned by [AuthNotifier].
final authStateProvider = NotifierProvider<AuthNotifier, AuthState>(
  AuthNotifier.new,
);

/// Whether the user is signed in, from the UI's point of view.
enum AuthStatus {
  /// The persisted session is still being restored (app launch).
  restoring,

  /// No session (signed out, or restore found nothing / failed).
  signedOut,

  /// A live session is held.
  signedIn,
}

/// The auth state screens render.
///
/// [errorCode] is a backend envelope code (`INVALID_CREDENTIALS`,
/// `EMAIL_TAKEN`, `TOKEN_EXPIRED`, `RATE_LIMITED`, …) or a
/// client-side code (`NETWORK_ERROR`, `TIMEOUT`) — screens map it
/// to localised copy via `authErrorMessage`, never render the raw
/// code. [fieldErrors] carries per-field validation messages.
/// [infoCode] reports a non-error outcome (`registerDone`,
/// `verifyDone`, `verifyResent`, `forgotSent`, `resetDone`,
/// `passwordChanged`) for the success banner / navigation.
class AuthState {
  const AuthState({
    this.status = AuthStatus.restoring,
    this.user,
    this.isBusy = false,
    this.errorCode,
    this.fieldErrors = const <String, String>{},
    this.infoCode,
    this.matchesPlayed,
    this.matchesWon,
  });

  final AuthStatus status;
  final AuthUser? user;
  final bool isBusy;
  final String? errorCode;
  final Map<String, String> fieldErrors;
  final String? infoCode;

  /// Online totals from the last `GET /users/me` (FR-07), shown on
  /// the account screen. Null until a profile has been fetched.
  final int? matchesPlayed;
  final int? matchesWon;

  AuthState copyWith({
    AuthStatus? status,
    AuthUser? user,
    bool clearUser = false,
    bool? isBusy,
    String? errorCode,
    bool clearError = false,
    Map<String, String>? fieldErrors,
    String? infoCode,
    bool clearInfo = false,
    int? matchesPlayed,
    int? matchesWon,
  }) => AuthState(
    status: status ?? this.status,
    user: clearUser ? null : (user ?? this.user),
    isBusy: isBusy ?? this.isBusy,
    errorCode: clearError ? null : (errorCode ?? this.errorCode),
    fieldErrors: fieldErrors ?? this.fieldErrors,
    infoCode: clearInfo ? null : (infoCode ?? this.infoCode),
    matchesPlayed: matchesPlayed ?? this.matchesPlayed,
    matchesWon: matchesWon ?? this.matchesWon,
  );
}

/// Drives [AuthState] from [AuthService].
///
/// Every method returns whether the operation succeeded; failures
/// land in the state as [AuthState.errorCode] / [fieldErrors] for
/// the screen to render — methods never throw to the UI. The one
/// exception is [fetchProfile], which returns the profile (or null
/// on failure) for the account screen.
class AuthNotifier extends Notifier<AuthState> {
  @override
  AuthState build() {
    unawaited(_restore());
    return const AuthState();
  }

  AuthService get _service => ref.read(authServiceProvider);

  Future<void> _restore() async {
    final session = await _service.restoreSession();
    if (!ref.mounted) return;
    state = session == null
        ? state.copyWith(status: AuthStatus.signedOut)
        : state.copyWith(status: AuthStatus.signedIn, user: session.user);
  }

  Future<bool> login({
    required String identifier,
    required String password,
  }) async {
    state = state.copyWith(isBusy: true, clearError: true, clearInfo: true);
    try {
      final session = await _service.login(
        identifier: identifier,
        password: password,
      );
      state = state.copyWith(
        status: AuthStatus.signedIn,
        user: session.user,
        isBusy: false,
      );
      return true;
    } on ApiException catch (e) {
      state = state.copyWith(
        isBusy: false,
        errorCode: e.code,
        fieldErrors: e.fieldErrors,
      );
      return false;
    }
  }

  Future<bool> register({
    required String email,
    required String username,
    required String password,
    String? displayName,
  }) async {
    state = state.copyWith(isBusy: true, clearError: true, clearInfo: true);
    try {
      final session = await _service.register(
        email: email,
        username: username,
        password: password,
        displayName: displayName,
      );
      state = state.copyWith(
        status: AuthStatus.signedIn,
        user: session.user,
        isBusy: false,
        infoCode: 'registerDone',
      );
      return true;
    } on ApiException catch (e) {
      state = state.copyWith(
        isBusy: false,
        errorCode: e.code,
        fieldErrors: e.fieldErrors,
      );
      return false;
    }
  }

  Future<bool> verifyEmail({required String token}) async {
    state = state.copyWith(isBusy: true, clearError: true, clearInfo: true);
    try {
      await _service.verifyEmail(token: token);
      final user = _service.session?.user;
      state = state.copyWith(user: user, isBusy: false, infoCode: 'verifyDone');
      return true;
    } on ApiException catch (e) {
      state = state.copyWith(
        isBusy: false,
        errorCode: e.code,
        fieldErrors: e.fieldErrors,
      );
      return false;
    }
  }

  Future<bool> resendVerification({required String email}) async {
    state = state.copyWith(isBusy: true, clearError: true, clearInfo: true);
    try {
      await _service.resendVerification(email: email);
      state = state.copyWith(isBusy: false, infoCode: 'verifyResent');
      return true;
    } on ApiException catch (e) {
      state = state.copyWith(
        isBusy: false,
        errorCode: e.code,
        fieldErrors: e.fieldErrors,
      );
      return false;
    }
  }

  Future<bool> forgotPassword({required String email}) async {
    state = state.copyWith(isBusy: true, clearError: true, clearInfo: true);
    try {
      await _service.forgotPassword(email: email);
      state = state.copyWith(isBusy: false, infoCode: 'forgotSent');
      return true;
    } on ApiException catch (e) {
      state = state.copyWith(
        isBusy: false,
        errorCode: e.code,
        fieldErrors: e.fieldErrors,
      );
      return false;
    }
  }

  Future<bool> resetPassword({
    required String token,
    required String newPassword,
  }) async {
    state = state.copyWith(isBusy: true, clearError: true, clearInfo: true);
    try {
      await _service.resetPassword(token: token, newPassword: newPassword);
      state = state.copyWith(
        status: AuthStatus.signedOut,
        clearUser: true,
        isBusy: false,
        infoCode: 'resetDone',
      );
      return true;
    } on ApiException catch (e) {
      state = state.copyWith(
        isBusy: false,
        errorCode: e.code,
        fieldErrors: e.fieldErrors,
      );
      return false;
    }
  }

  Future<bool> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    state = state.copyWith(isBusy: true, clearError: true, clearInfo: true);
    try {
      await _service.changePassword(
        currentPassword: currentPassword,
        newPassword: newPassword,
      );
      state = state.copyWith(
        status: AuthStatus.signedOut,
        clearUser: true,
        isBusy: false,
        infoCode: 'passwordChanged',
      );
      return true;
    } on ApiException catch (e) {
      state = state.copyWith(
        isBusy: false,
        errorCode: e.code,
        fieldErrors: e.fieldErrors,
      );
      return false;
    }
  }

  Future<OwnProfile?> fetchProfile() async {
    state = state.copyWith(isBusy: true, clearError: true, clearInfo: true);
    try {
      final profile = await _service.fetchProfile();
      state = state.copyWith(
        user: profile.user,
        matchesPlayed: profile.matchesPlayed,
        matchesWon: profile.matchesWon,
        isBusy: false,
      );
      return profile;
    } on ApiException catch (e) {
      state = state.copyWith(
        isBusy: false,
        errorCode: e.code,
        fieldErrors: e.fieldErrors,
      );
      return null;
    }
  }

  Future<void> logout() async {
    state = state.copyWith(isBusy: true, clearError: true, clearInfo: true);
    await _service.logout();
    state = state.copyWith(
      status: AuthStatus.signedOut,
      clearUser: true,
      isBusy: false,
    );
  }
}

// -- Online rooms + matchmaking (Phase 5, Stage 3) ------------------------
//
// Same rule as the auth graph: this file is the only construction site.
// Screens read the lobby / matchmaking state through the notifiers and
// never construct a client, socket or service (enforced by
// `tool/check_boundaries.sh` — new presentation files must not import
// the data layer). [GameRoomService] owns the REST + socket calls;
// the notifiers own only UI-facing state.

/// The REST client for the rooms + matchmaking API.
final gameApiClientProvider = Provider<GameApiClient>((ref) {
  final client = GameApiClient(config: ref.watch(authConfigProvider));
  ref.onDispose(client.close);
  return client;
});

/// The `/game` socket client (connection manager).
final gameSocketClientProvider = Provider<GameSocketClient>((ref) {
  final client = GameSocketClient();
  ref.onDispose(() {
    unawaited(client.disconnect());
    client.dispose();
  });
  return client;
});

/// The rooms + matchmaking service (SDD §5.1.8 GameRoomModule API).
final gameRoomServiceProvider = Provider<GameRoomService>((ref) {
  final service = GameRoomService(
    auth: ref.watch(authServiceProvider),
    client: ref.watch(gameApiClientProvider),
    socket: ref.watch(gameSocketClientProvider),
  );
  ref.onDispose(service.dispose);
  return service;
});

/// Presentation view of a room member: plain values the lobby screen
/// renders. Built from the data-layer [RoomMember] by the provider
/// graph — screens never import the data layer (boundary rule,
/// `tool/check_boundaries.sh`).
class LobbyMember {
  const LobbyMember({
    required this.userId,
    required this.username,
    required this.displayName,
    required this.isReady,
    required this.isHost,
    required this.joinedAt,
  });

  factory LobbyMember.fromMember(RoomMember member) => LobbyMember(
    userId: member.userId,
    username: member.username,
    displayName: member.displayName,
    isReady: member.isReady,
    isHost: member.isHost,
    joinedAt: member.joinedAt,
  );

  final String userId;
  final String username;
  final String displayName;
  final bool isReady;
  final bool isHost;
  final String joinedAt;
}

/// Presentation view of a room, built from the data-layer [RoomView]
/// by the provider graph. Start gating delegates to the wrapped view
/// so the FR-47 rule lives in exactly one place.
class LobbyRoom {
  LobbyRoom._({
    required this.id,
    required this.code,
    required this.hostId,
    required this.maxPlayers,
    required this.status,
    required this.rulesetVersion,
    required this.members,
    required this.matchId,
    required RoomView view,
  }) : _view = view;

  factory LobbyRoom.fromRoomView(RoomView view) => LobbyRoom._(
    id: view.id,
    code: view.code,
    hostId: view.hostId,
    maxPlayers: view.maxPlayers,
    status: view.status,
    rulesetVersion: view.rulesetVersion,
    members: view.members.map(LobbyMember.fromMember).toList(growable: false),
    matchId: view.matchId,
    view: view,
  );

  final String id;
  final String code;
  final String hostId;
  final int maxPlayers;
  final String status;
  final String rulesetVersion;
  final List<LobbyMember> members;
  final String? matchId;

  final RoomView _view;

  bool get isOpen => _view.isOpen;
  bool get isPlaying => _view.isPlaying;
  bool canStart(String userId) => _view.canStart(userId);
  String? startBlocker(String userId) => _view.startBlocker(userId);
}

/// UI-facing lobby state, owned by [RoomLobbyNotifier].
class RoomLobbyState {
  const RoomLobbyState({
    this.room,
    this.isBusy = false,
    this.errorCode,
    this.matchStarted,
    this.infoCode,
    this.connectionState = GameSocketConnectionState.disconnected,
  });

  final LobbyRoom? room;
  final bool isBusy;
  final String? errorCode;
  final MatchStarted? matchStarted;
  final String? infoCode;

  /// The socket's connection state (Stage 7: the lobby shows the
  /// connection banner while in a room).
  final GameSocketConnectionState connectionState;

  RoomLobbyState copyWith({
    LobbyRoom? room,
    bool clearRoom = false,
    bool? isBusy,
    String? errorCode,
    bool clearError = false,
    MatchStarted? matchStarted,
    bool clearMatchStarted = false,
    String? infoCode,
    bool clearInfo = false,
    GameSocketConnectionState? connectionState,
  }) => RoomLobbyState(
    room: clearRoom ? null : (room ?? this.room),
    isBusy: isBusy ?? this.isBusy,
    errorCode: clearError ? null : (errorCode ?? this.errorCode),
    matchStarted: clearMatchStarted
        ? null
        : (matchStarted ?? this.matchStarted),
    infoCode: clearInfo ? null : (infoCode ?? this.infoCode),
    connectionState: connectionState ?? this.connectionState,
  );
}

/// Drives [RoomLobbyState] from [GameRoomService].
///
/// Every method returns whether the operation succeeded; failures land
/// in the state as [RoomLobbyState.errorCode] for the screen to render
/// — methods never throw to the UI. Live `room:updated` broadcasts
/// replace the state wholesale (the server is the authority).
class RoomLobbyNotifier extends Notifier<RoomLobbyState> {
  StreamSubscription<RoomView>? _roomSub;
  StreamSubscription<MatchStarted>? _matchSub;
  StreamSubscription<GameSocketConnectionState>? _connectionSub;

  @override
  RoomLobbyState build() {
    final service = ref.read(gameRoomServiceProvider);
    _roomSub = service.roomUpdates.listen((room) {
      if (!ref.mounted) return;
      state = state.copyWith(
        room: LobbyRoom.fromRoomView(room),
        clearError: true,
      );
    });
    _matchSub = service.matchStarted.listen((started) {
      if (!ref.mounted) return;
      state = state.copyWith(matchStarted: started);
    });
    _connectionSub = service.connectionStates.listen((next) {
      if (!ref.mounted) return;
      state = state.copyWith(connectionState: next);
    });
    ref.onDispose(() {
      unawaited(_roomSub?.cancel());
      unawaited(_matchSub?.cancel());
      unawaited(_connectionSub?.cancel());
    });
    final current = service.currentRoom;
    return RoomLobbyState(
      room: current == null ? null : LobbyRoom.fromRoomView(current),
      connectionState: service.connectionState,
    );
  }

  GameRoomService get _service => ref.read(gameRoomServiceProvider);

  /// Manual reconnect (the connection banner's retry, Stage 7).
  Future<bool> retryConnection() async {
    try {
      await _service.connectSocket();
      return true;
    } on ApiException catch (e) {
      state = state.copyWith(errorCode: e.code);
      return false;
    }
  }

  /// Consume the pending `match:started` (the lobby screen calls
  /// this as it navigates to the game screen, so a return to the
  /// lobby does not re-announce — or re-navigate on — the same
  /// start).
  void clearMatchStarted() {
    state = state.copyWith(clearMatchStarted: true);
  }

  /// Enter the lobby for an existing room (e.g. after a matchmaking
  /// match): loads it and joins its socket room for live updates.
  Future<bool> enterRoom(String roomId) async {
    state = state.copyWith(isBusy: true, clearError: true, clearInfo: true);
    try {
      final room = await _service.refreshCurrentRoom(roomId);
      state = state.copyWith(room: LobbyRoom.fromRoomView(room), isBusy: false);
      return true;
    } on ApiException catch (e) {
      state = state.copyWith(isBusy: false, errorCode: e.code);
      return false;
    }
  }

  Future<bool> createRoom({required int maxPlayers}) async {
    state = state.copyWith(isBusy: true, clearError: true, clearInfo: true);
    try {
      final room = await _service.createRoom(maxPlayers: maxPlayers);
      state = state.copyWith(room: LobbyRoom.fromRoomView(room), isBusy: false);
      return true;
    } on ApiException catch (e) {
      state = state.copyWith(isBusy: false, errorCode: e.code);
      return false;
    }
  }

  Future<bool> joinRoom(String code) async {
    state = state.copyWith(isBusy: true, clearError: true, clearInfo: true);
    try {
      final room = await _service.joinRoom(code);
      state = state.copyWith(room: LobbyRoom.fromRoomView(room), isBusy: false);
      return true;
    } on ApiException catch (e) {
      state = state.copyWith(isBusy: false, errorCode: e.code);
      return false;
    }
  }

  Future<bool> setReady(bool ready) async {
    try {
      await _service.setReady(ready);
      return true;
    } on ApiException catch (e) {
      state = state.copyWith(errorCode: e.code);
      return false;
    }
  }

  Future<bool> startMatch() async {
    state = state.copyWith(isBusy: true, clearError: true);
    try {
      await _service.startMatch();
      state = state.copyWith(isBusy: false);
      return true;
    } on ApiException catch (e) {
      state = state.copyWith(isBusy: false, errorCode: e.code);
      return false;
    }
  }

  Future<bool> leaveRoom() async {
    state = state.copyWith(isBusy: true, clearError: true);
    try {
      await _service.leaveRoom();
      state = state.copyWith(clearRoom: true, isBusy: false);
      return true;
    } on ApiException catch (e) {
      state = state.copyWith(isBusy: false, errorCode: e.code);
      return false;
    }
  }

  void clearError() {
    state = state.copyWith(clearError: true);
  }
}

/// UI-facing lobby state.
final roomLobbyProvider = NotifierProvider<RoomLobbyNotifier, RoomLobbyState>(
  RoomLobbyNotifier.new,
);

/// UI-facing matchmaking state, owned by [MatchmakingNotifier].
class MatchmakingState {
  const MatchmakingState({
    this.status,
    this.position = 0,
    this.queueSize = 0,
    this.groupSize = 4,
    this.roomId,
    this.roomCode,
    this.isBusy = false,
    this.errorCode,
  });

  final MatchmakingStatus? status;
  final int position;
  final int queueSize;
  final int groupSize;
  final String? roomId;
  final String? roomCode;
  final bool isBusy;
  final String? errorCode;

  bool get isQueued => status?.isQueued ?? false;
  bool get isMatched => status?.isMatched ?? false;

  MatchmakingState copyWith({
    MatchmakingStatus? status,
    int? position,
    int? queueSize,
    int? groupSize,
    String? roomId,
    String? roomCode,
    bool? isBusy,
    String? errorCode,
    bool clearError = false,
  }) => MatchmakingState(
    status: status ?? this.status,
    position: position ?? this.position,
    queueSize: queueSize ?? this.queueSize,
    groupSize: groupSize ?? this.groupSize,
    roomId: roomId ?? this.roomId,
    roomCode: roomCode ?? this.roomCode,
    isBusy: isBusy ?? this.isBusy,
    errorCode: clearError ? null : (errorCode ?? this.errorCode),
  );
}

/// Drives [MatchmakingState] from [GameRoomService].
class MatchmakingNotifier extends Notifier<MatchmakingState> {
  StreamSubscription<MatchmakingMatched>? _matchedSub;

  @override
  MatchmakingState build() {
    final service = ref.read(gameRoomServiceProvider);
    _matchedSub = service.matchmakingMatched.listen((matched) {
      if (!ref.mounted) return;
      state = state.copyWith(
        roomId: matched.roomId,
        roomCode: matched.roomCode,
      );
    });
    ref.onDispose(() {
      unawaited(_matchedSub?.cancel());
    });
    unawaited(_refresh());
    return const MatchmakingState();
  }

  GameRoomService get _service => ref.read(gameRoomServiceProvider);

  Future<void> _refresh() async {
    try {
      final status = await _service.refreshMatchmakingStatus();
      if (!ref.mounted) return;
      state = state.copyWith(
        status: status,
        position: status.position,
        queueSize: status.queueSize,
        groupSize: status.groupSize,
        roomId: status.roomId,
        roomCode: status.roomCode,
      );
    } on ApiException catch (e) {
      if (!ref.mounted) return;
      state = state.copyWith(errorCode: e.code);
    }
  }

  Future<bool> joinQueue() async {
    state = state.copyWith(isBusy: true, clearError: true);
    try {
      // Connect first: the queue join is REST, but the matched event
      // arrives over the socket while this player is waiting.
      await _service.connectSocket();
      final result = await _service.joinMatchmaking();
      final matched = result['matched'] as bool? ?? false;
      final queueSize = (result['queueSize'] as num?)?.toInt() ?? 0;
      final groupSize = (result['groupSize'] as num?)?.toInt() ?? 4;
      if (matched) {
        final room = result['room'];
        final roomMap = room is Map<String, Object?> ? room : null;
        state = state.copyWith(
          isBusy: false,
          status: MatchmakingStatus(
            status: 'matched',
            position: 0,
            queueSize: queueSize,
            groupSize: groupSize,
            roomId: roomMap?['id'] as String?,
            roomCode: roomMap?['code'] as String?,
          ),
          roomId: roomMap?['id'] as String?,
          roomCode: roomMap?['code'] as String?,
        );
      } else {
        // The join response already carries the position — no extra
        // status fetch: a refresh here would race the queue state
        // the server just returned.
        final position = (result['position'] as num?)?.toInt() ?? 0;
        state = state.copyWith(
          isBusy: false,
          status: MatchmakingStatus(
            status: 'queued',
            position: position,
            queueSize: queueSize,
            groupSize: groupSize,
            roomId: null,
            roomCode: null,
          ),
          position: position,
          queueSize: queueSize,
        );
      }
      return true;
    } on ApiException catch (e) {
      state = state.copyWith(isBusy: false, errorCode: e.code);
      return false;
    }
  }

  Future<bool> cancelQueue() async {
    state = state.copyWith(isBusy: true, clearError: true);
    try {
      await _service.leaveMatchmaking();
      state = state.copyWith(
        isBusy: false,
        status: const MatchmakingStatus(
          status: 'idle',
          position: 0,
          queueSize: 0,
          groupSize: 4,
          roomId: null,
          roomCode: null,
        ),
        position: 0,
      );
      return true;
    } on ApiException catch (e) {
      state = state.copyWith(isBusy: false, errorCode: e.code);
      return false;
    }
  }

  void clearError() {
    state = state.copyWith(clearError: true);
  }
}

/// UI-facing matchmaking state.
final matchmakingProvider =
    NotifierProvider<MatchmakingNotifier, MatchmakingState>(
      MatchmakingNotifier.new,
    );

// -- Online game (Phase 5, Stage 7) ----------------------------------------
//
// [OnlineGameController] is the only mirror of the server match
// state: it subscribes to the gameplay streams on [GameRoomService]
// and holds the latest `match:state` snapshot plus the turn and
// presence extras. The server is the authority — the controller
// never predicts a transition: after every `dice:rolled` /
// `token:moved` / `turn:changed` it asks for a fresh snapshot
// (`state:request`) and renders that. The Dart engine is used
// read-only, via [LudoGame.legalMovesFor], to highlight which of
// the local player's tokens may move in the current snapshot; the
// controller never constructs a [LudoGame] and never mutates a
// snapshot (D-20: the engine is not forked, and no offline rule
// changes here).
//
// The screen drives it: it calls [OnlineGameController.start] once
// (route arguments carry the match id) and reads
// [OnlineGameState]; navigation to the results screen on
// `match:ended` and the presence toasts live in the screen, fed by
// `ref.listen` on [OnlineGameState.ended] /
// [OnlineGameState.notice] / [OnlineGameState.errorCode].

/// One presence notice for the game screen to toast: a player
/// disconnected / reconnected / forfeited. [id] rises on every
/// notice so the screen's `ref.listen` fires once per event even
/// when two notices name the same player.
class OnlinePresenceNotice {
  const OnlinePresenceNotice({
    required this.id,
    required this.kind,
    required this.playerId,
    required this.graceEndsAt,
  });

  final int id;

  /// 'disconnected' | 'reconnected' | 'forfeited'.
  final String kind;
  final String playerId;
  final DateTime? graceEndsAt;
}

/// UI-facing online match state, owned by [OnlineGameController].
class OnlineGameState {
  const OnlineGameState({
    required this.matchId,
    this.snapshot,
    this.seq = 0,
    this.seats = const <MatchSeat>[],
    this.turnPlayerId,
    this.turnEndsAt,
    this.players = const <MatchStatePlayer>[],
    this.lastDiceValue,
    this.lastDicePlayerId,
    this.lastMovedTokenId,
    this.errorCode,
    this.ended,
    this.notice,
    this.isBusy = false,
    this.isLoading = true,
    this.snapshotError = false,
    this.connectionState = GameSocketConnectionState.disconnected,
    this.localUserId,
    this.displayNames = const <String, String>{},
    this.firstSnapshotAt,
  });

  final String matchId;

  /// The latest server snapshot, or null until the first
  /// `match:state` arrives.
  final GameState? snapshot;

  /// The `seq` of the snapshot held (0 until the first one).
  final int seq;

  /// Seats of the match (`match:started` / `match:state`).
  final List<MatchSeat> seats;

  /// The player to move (null when the match has ended).
  final String? turnPlayerId;

  /// Deadline of the current turn (null when no turn runs).
  final DateTime? turnEndsAt;

  /// Per-player presence (disconnected / grace / missed turns).
  final List<MatchStatePlayer> players;

  /// The most recent dice value (from `dice:rolled`), if any.
  final int? lastDiceValue;

  /// Who rolled it.
  final String? lastDicePlayerId;

  /// The token moved by the most recent `token:moved`, if any
  /// (`"{seat}:{tokenIndex}"` — the last-moved highlight).
  final String? lastMovedTokenId;

  /// The latest `action:rejected` code (or a local failure code),
  /// for the screen to map to localised copy.
  final String? errorCode;

  /// Set by `match:ended` — the screen navigates to results.
  final MatchEndedView? ended;

  /// The latest presence notice, for the screen to toast.
  final OnlinePresenceNotice? notice;

  /// A roll / move intent is in flight (cleared by the answering
  /// broadcast, a rejection, or a disconnect).
  final bool isBusy;

  /// True until the first snapshot (or a load failure) lands.
  final bool isLoading;

  /// True when the server sent a snapshot the engine cannot parse
  /// — the board keeps the last good snapshot (or nothing) and the
  /// screen offers a retry instead of a stale board.
  final bool snapshotError;

  /// The socket's connection state (the banner reads this).
  final GameSocketConnectionState connectionState;

  /// The signed-in user's id (null until the session is known).
  final String? localUserId;

  /// Display names by user id (room members + the signed-in user);
  /// absent ids render as "Player N" via [nameFor].
  final Map<String, String> displayNames;

  /// Device time the first snapshot arrived (the results-screen
  /// duration fallback when the snapshot's naive `startedAt` is
  /// skewed against the device clock — see the screen).
  final DateTime? firstSnapshotAt;

  /// The local player's seat, or null when unknown.
  int? get localSeat {
    final userId = localUserId;
    if (userId == null) return null;
    for (final seat in seats) {
      if (seat.userId == userId) return seat.seat;
    }
    return null;
  }

  /// The seat of [userId], or null when unknown.
  int? seatOf(String userId) {
    for (final seat in seats) {
      if (seat.userId == userId) return seat.seat;
    }
    return null;
  }

  /// Display name for [userId], or null when the server never named
  /// them — the screen falls back to `l10n.playerName(seat + 1)`.
  String? displayNameOf(String userId) => displayNames[userId];

  /// The local player's presence row, or null when unknown.
  MatchStatePlayer? get myPresence {
    final userId = localUserId;
    if (userId == null) return null;
    for (final player in players) {
      if (player.userId == userId) return player;
    }
    return null;
  }

  /// True when the snapshot says it is the local player's turn in a
  /// live match.
  bool get isMyTurn {
    final snapshot = this.snapshot;
    final seat = localSeat;
    return snapshot != null &&
        ended == null &&
        seat != null &&
        snapshot.currentPlayerIndex == seat;
  }

  /// A roll may be sent right now: my turn, awaiting a roll, live
  /// socket, no intent in flight.
  bool get canRoll =>
      isMyTurn &&
      snapshot?.phase == TurnPhase.awaitingRoll &&
      connectionState == GameSocketConnectionState.connected &&
      !isBusy &&
      !isLoading;

  /// A move may be sent right now: my turn, awaiting a move, live
  /// socket, no intent in flight.
  bool get canMove =>
      isMyTurn &&
      snapshot?.phase == TurnPhase.awaitingMove &&
      connectionState == GameSocketConnectionState.connected &&
      !isBusy &&
      !isLoading;

  /// Tokens the local player may move in the current snapshot
  /// (`"{seat}:{tokenIndex}"`), from the engine's legal-move
  /// computation on the server snapshot — display only; the server
  /// re-validates every intent.
  Set<String> get legalTokenIds {
    final snapshot = this.snapshot;
    if (snapshot == null ||
        !isMyTurn ||
        snapshot.phase != TurnPhase.awaitingMove) {
      return const <String>{};
    }
    return LudoGame.legalMovesFor(
      snapshot,
      snapshot.lastRoll,
      snapshot.ruleset,
      const Board(),
    ).map((m) => '${m.playerIndex}:${m.tokenIndex}').toSet();
  }

  OnlineGameState copyWith({
    GameState? snapshot,
    int? seq,
    List<MatchSeat>? seats,
    String? turnPlayerId,
    DateTime? turnEndsAt,
    bool clearTurnEndsAt = false,
    List<MatchStatePlayer>? players,
    int? lastDiceValue,
    bool clearLastDice = false,
    String? lastDicePlayerId,
    String? lastMovedTokenId,
    String? errorCode,
    bool clearError = false,
    MatchEndedView? ended,
    OnlinePresenceNotice? notice,
    bool? isBusy,
    bool? isLoading,
    bool? snapshotError,
    GameSocketConnectionState? connectionState,
    String? localUserId,
    Map<String, String>? displayNames,
    DateTime? firstSnapshotAt,
  }) => OnlineGameState(
    matchId: matchId,
    snapshot: snapshot ?? this.snapshot,
    seq: seq ?? this.seq,
    seats: seats ?? this.seats,
    turnPlayerId: turnPlayerId ?? this.turnPlayerId,
    turnEndsAt: clearTurnEndsAt ? null : (turnEndsAt ?? this.turnEndsAt),
    players: players ?? this.players,
    lastDiceValue: clearLastDice ? null : (lastDiceValue ?? this.lastDiceValue),
    lastDicePlayerId: lastDicePlayerId ?? this.lastDicePlayerId,
    lastMovedTokenId: lastMovedTokenId ?? this.lastMovedTokenId,
    errorCode: clearError ? null : (errorCode ?? this.errorCode),
    ended: ended ?? this.ended,
    notice: notice ?? this.notice,
    isBusy: isBusy ?? this.isBusy,
    isLoading: isLoading ?? this.isLoading,
    snapshotError: snapshotError ?? this.snapshotError,
    connectionState: connectionState ?? this.connectionState,
    localUserId: localUserId ?? this.localUserId,
    displayNames: displayNames ?? this.displayNames,
    firstSnapshotAt: firstSnapshotAt ?? this.firstSnapshotAt,
  );
}

/// Drives [OnlineGameState] from [GameRoomService].
///
/// Subscriptions start in [start] (the screen calls it once with
/// the route's match id) so constructing the provider is
/// side-effect free; [ref.onDispose] cancels them when the screen
/// leaves. Methods never throw to the UI: intent failures land in
/// [OnlineGameState.errorCode].
class OnlineGameController extends Notifier<OnlineGameState> {
  OnlineGameController(this._matchId);

  /// The match this controller mirrors (Riverpod 3.x families pass
  /// the argument to the constructor; [build] takes none).
  final String _matchId;

  final _subscriptions = <StreamSubscription<Object?>>[];
  var _started = false;
  var _noticeId = 0;

  @override
  OnlineGameState build() {
    final service = ref.read(gameRoomServiceProvider);
    // The session may still be restoring when the screen opens:
    // pick the user id up when it lands (the lobby already needed
    // a signed-in user, so this is a belt-and-braces path).
    ref.listen(authStateProvider, (_, next) {
      final user = next.user;
      if (user == null || !ref.mounted) return;
      if (state.localUserId == user.id) return;
      final names = Map<String, String>.of(state.displayNames)
        ..putIfAbsent(user.id, () => user.displayName);
      state = state.copyWith(localUserId: user.id, displayNames: names);
    });
    ref.onDispose(() {
      for (final sub in _subscriptions) {
        unawaited(sub.cancel());
      }
      _subscriptions.clear();
    });
    return OnlineGameState(
      matchId: _matchId,
      connectionState: service.connectionState,
    );
  }

  GameRoomService get _service => ref.read(gameRoomServiceProvider);

  /// Connect (if needed), remember the match for reconnects, and
  /// fetch the first snapshot. Idempotent — a second call (screen
  /// rebuild, route re-entry) is a no-op.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    final service = _service;
    final auth = ref.read(authStateProvider);
    final names = <String, String>{};
    final room = service.currentRoom;
    if (room != null) {
      for (final member in room.members) {
        names[member.userId] = member.displayName;
      }
    }
    final user = auth.user;
    if (user != null) {
      names.putIfAbsent(user.id, () => user.displayName);
    }
    state = state.copyWith(localUserId: user?.id, displayNames: names);
    _subscriptions.addAll([
      service.matchState.listen(_onMatchState),
      service.diceRolled.listen(_onDiceRolled),
      service.tokenMoved.listen(_onTokenMoved),
      service.turnChanged.listen(_onTurnChanged),
      service.matchEnded.listen(_onMatchEnded),
      service.actionRejected.listen(_onActionRejected),
      service.playerDisconnected.listen(_onPlayerDisconnected),
      service.playerReconnected.listen(_onPlayerReconnected),
      service.playerForfeited.listen(_onPlayerForfeited),
      service.connectionStates.listen(_onConnectionState),
    ]);
    try {
      await service.connectSocket();
    } on ApiException catch (e) {
      if (!ref.mounted) return;
      state = state.copyWith(isLoading: false, errorCode: e.code);
      return;
    }
    service.setActiveMatch(state.matchId);
    _requestState();
  }

  /// Roll the dice (FR-49). Guarded by [OnlineGameState.canRoll];
  /// the server re-validates and answers with `dice:rolled` (or
  /// `action:rejected`), which clears [OnlineGameState.isBusy].
  void rollDice() {
    if (!state.canRoll) return;
    state = state.copyWith(isBusy: true, clearError: true);
    try {
      _service.rollDice(state.matchId);
    } on ApiException catch (e) {
      if (!ref.mounted) return;
      state = state.copyWith(isBusy: false, errorCode: e.code);
    }
  }

  /// Move one token (FR-50). Guarded by [OnlineGameState.canMove]
  /// and the legal-move set; the server re-validates and answers
  /// with `token:moved` (or `action:rejected`).
  void moveToken(String tokenId) {
    if (!state.canMove) return;
    if (!state.legalTokenIds.contains(tokenId)) return;
    state = state.copyWith(isBusy: true, clearError: true);
    try {
      _service.moveToken(state.matchId, tokenId);
    } on ApiException catch (e) {
      if (!ref.mounted) return;
      state = state.copyWith(isBusy: false, errorCode: e.code);
    }
  }

  /// Manual reconnect (the connection banner's retry): reconnect
  /// the socket and re-fetch the snapshot. The socket client
  /// re-subscribes and re-requests state on its own reconnects;
  /// this is only the explicit user action.
  Future<void> retryConnection() async {
    state = state.copyWith(clearError: true);
    try {
      await _service.connectSocket();
      _service.setActiveMatch(state.matchId);
      _requestState();
    } on ApiException catch (e) {
      if (!ref.mounted) return;
      state = state.copyWith(errorCode: e.code);
    }
  }

  void clearError() {
    state = state.copyWith(clearError: true);
  }

  /// Ask for the full snapshot (FR-57). Failures surface as
  /// [OnlineGameState.errorCode]; the board keeps the last good
  /// snapshot either way.
  void _requestState({int? lastSeq}) {
    try {
      _service.requestMatchState(state.matchId, lastSeq ?? state.seq);
    } on ApiException catch (e) {
      if (!ref.mounted) return;
      state = state.copyWith(errorCode: e.code);
    }
  }

  void _onMatchState(Map<String, Object?> data) {
    if (!ref.mounted) return;
    final view = MatchStateView.fromJson(data);
    if (view.matchId != state.matchId) return;
    // Out-of-order snapshot replies (two `state:request`s in
    // flight): only a snapshot at or ahead of the one held replaces
    // it, so a late reply can never rewind the board.
    if (view.seq < state.seq) return;
    GameState snapshot;
    try {
      snapshot = GameState.fromJson(view.snapshot);
    } on FormatException {
      // The server sent a snapshot the engine cannot read — report
      // it and keep the last good snapshot (or nothing), never a
      // silently repaired board.
      state = state.copyWith(isLoading: false, snapshotError: true);
      return;
    }
    state = state.copyWith(
      snapshot: snapshot,
      seq: view.seq,
      seats: view.seats,
      turnPlayerId: view.turnPlayerId,
      turnEndsAt: _parseTime(view.turnEndsAt),
      clearTurnEndsAt: view.turnEndsAt == null,
      players: view.players,
      isLoading: false,
      snapshotError: false,
      firstSnapshotAt: state.firstSnapshotAt ?? DateTime.now(),
      // The snapshot is the dice source of truth: the engine resets
      // `lastRoll` to 0 on every move / turn advance, so a snapshot
      // with no outstanding roll clears the transient value the
      // `dice:rolled` event set (it would otherwise show the
      // previous turn's roll after the turn passed).
      lastDiceValue: snapshot.lastRoll > 0 ? snapshot.lastRoll : null,
      clearLastDice: snapshot.lastRoll <= 0,
    );
  }

  void _onDiceRolled(Map<String, Object?> data) {
    if (!ref.mounted) return;
    if (data['matchId'] != state.matchId) return;
    state = state.copyWith(
      lastDiceValue: (data['value'] as num?)?.toInt(),
      lastDicePlayerId: data['playerId'] as String?,
      isBusy: false,
    );
    _requestState(lastSeq: (data['seq'] as num?)?.toInt() ?? state.seq);
  }

  void _onTokenMoved(Map<String, Object?> data) {
    if (!ref.mounted) return;
    if (data['matchId'] != state.matchId) return;
    final turn = data['turn'];
    String? turnPlayerId;
    DateTime? turnEndsAt;
    if (turn is Map<String, Object?>) {
      turnPlayerId = turn['playerId'] as String?;
      turnEndsAt = _parseTime(turn['turnEndsAt'] as String?);
    }
    state = state.copyWith(
      lastMovedTokenId: data['tokenId'] as String?,
      turnPlayerId: turnPlayerId,
      turnEndsAt: turnEndsAt,
      clearTurnEndsAt:
          turn is Map<String, Object?> && turn['turnEndsAt'] == null,
      isBusy: false,
    );
    _requestState(lastSeq: (data['seq'] as num?)?.toInt() ?? state.seq);
  }

  void _onTurnChanged(Map<String, Object?> data) {
    if (!ref.mounted) return;
    if (data['matchId'] != state.matchId) return;
    final turnEndsAt = _parseTime(data['turnEndsAt'] as String?);
    state = state.copyWith(
      turnPlayerId: data['playerId'] as String?,
      turnEndsAt: turnEndsAt,
      clearTurnEndsAt: data['turnEndsAt'] == null,
      isBusy: false,
    );
    _requestState(lastSeq: (data['seq'] as num?)?.toInt() ?? state.seq);
  }

  void _onMatchEnded(Map<String, Object?> data) {
    if (!ref.mounted) return;
    if (data['matchId'] != state.matchId) return;
    state = state.copyWith(ended: MatchEndedView.fromJson(data), isBusy: false);
  }

  void _onActionRejected(Map<String, Object?> data) {
    if (!ref.mounted) return;
    final matchId = data['matchId'] as String?;
    if (matchId != null && matchId.isNotEmpty && matchId != state.matchId) {
      return;
    }
    state = state.copyWith(
      errorCode: ActionRejectedView.fromJson(data).code,
      isBusy: false,
    );
  }

  void _onPlayerDisconnected(Map<String, Object?> data) {
    if (!ref.mounted) return;
    final view = PlayerPresenceView.fromJson(data);
    if (view.matchId != state.matchId) return;
    final graceEndsAt = _parseTime(view.graceEndsAt);
    state = state.copyWith(
      players: _updatePlayer(
        view.playerId,
        disconnected: true,
        graceEndsAt: view.graceEndsAt,
      ),
      notice: OnlinePresenceNotice(
        id: ++_noticeId,
        kind: 'disconnected',
        playerId: view.playerId,
        graceEndsAt: graceEndsAt,
      ),
    );
  }

  void _onPlayerReconnected(Map<String, Object?> data) {
    if (!ref.mounted) return;
    final view = PlayerPresenceView.fromJson(data);
    if (view.matchId != state.matchId) return;
    state = state.copyWith(
      players: _updatePlayer(
        view.playerId,
        disconnected: false,
        clearGrace: true,
      ),
      notice: OnlinePresenceNotice(
        id: ++_noticeId,
        kind: 'reconnected',
        playerId: view.playerId,
        graceEndsAt: null,
      ),
    );
  }

  void _onPlayerForfeited(Map<String, Object?> data) {
    if (!ref.mounted) return;
    final view = PlayerPresenceView.fromJson(data);
    if (view.matchId != state.matchId) return;
    state = state.copyWith(
      players: _updatePlayer(view.playerId, result: 'forfeit'),
      notice: OnlinePresenceNotice(
        id: ++_noticeId,
        kind: 'forfeited',
        playerId: view.playerId,
        graceEndsAt: null,
      ),
    );
  }

  void _onConnectionState(GameSocketConnectionState next) {
    if (!ref.mounted) return;
    state = state.copyWith(
      connectionState: next,
      // An intent in flight cannot complete on a dead socket.
      isBusy: next == GameSocketConnectionState.connected
          ? state.isBusy
          : false,
    );
  }

  /// The presence row for [playerId] with the given fields updated;
  /// unchanged when the player is not in the snapshot's list.
  List<MatchStatePlayer> _updatePlayer(
    String playerId, {
    bool? disconnected,
    String? graceEndsAt,
    bool clearGrace = false,
    String? result,
  }) => [
    for (final player in state.players)
      if (player.userId == playerId)
        player.copyWith(
          disconnected: disconnected,
          graceEndsAt: graceEndsAt,
          clearGrace: clearGrace,
          result: result,
        )
      else
        player,
  ];

  /// An ISO timestamp (Z-suffixed server time) or null. Never
  /// throws: an unparsable deadline is treated as absent.
  static DateTime? _parseTime(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }
}

/// UI-facing online match state, keyed by match id.
///
/// `autoDispose`: leaving the screen drops the last listener and
/// disposes the controller (subscriptions cancelled) — a later
/// re-entry to the same match starts fresh instead of resuming a
/// stale mirror (notably after leaving mid-match, which forfeits).
final onlineGameControllerProvider = NotifierProvider.autoDispose
    .family<OnlineGameController, OnlineGameState, String>(
      (matchId) => OnlineGameController(matchId),
    );
