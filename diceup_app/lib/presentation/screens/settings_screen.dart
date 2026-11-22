import 'package:flutter/material.dart';

import '../../core/design_system/diceup_components.dart';
import '../../core/design_system/diceup_spacing.dart';
import '../../domain/repositories/settings_repository.dart';
import '../../l10n/app_strings.dart';
import '../app_dependencies_scope.dart';

/// Application settings (SRS FR-08, FR-32).
///
/// Persisted via [SettingsRepository] (SDD §9.1 `local_settings`,
/// M1.7): the screen loads the stored values on entry — a loading
/// state is shown until they arrive, so the defaults are never
/// flashed first — and every change persists immediately.
///
/// Vibration is real (D-32): the toggle persists `vibration_enabled`
/// and gates the haptic feedback on moves (see
/// `lib/presentation/feedback/feedback_service.dart`).
///
/// Sound is a named follow-up, not part of this work: the toggle is
/// shown DISABLED with an honest note that sound is coming soon and
/// does not play anything yet — it never implies playback exists. No
/// audio dependency and no sound assets exist. The volume slider
/// persists `sound_volume` (default 100, D-25) for when sound
/// arrives; moving it plays nothing.
///
/// Reset restores the D-25 defaults and clears the `last_*`
/// last-used options (the repository's [SettingsRepository.
/// resetToDefaults] contract); those keys stay absent until a match
/// sets them again.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  /// Stored values with [kDefaultSettings] applied for unset keys;
  /// null while loading.
  Map<String, String>? _settings;
  bool _loadFailed = false;
  bool _unavailable = false;
  bool _loadStarted = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loadStarted) return;
    _loadStarted = true;
    _load();
  }

  Future<void> _load() async {
    final dependencies = AppDependenciesScope.maybeOf(context)?.dependencies;
    if (dependencies == null) {
      if (mounted) setState(() => _unavailable = true);
      return;
    }
    try {
      final stored = await dependencies.settings.getAllSettings();
      if (mounted) {
        setState(() => _settings = {...kDefaultSettings, ...stored});
      }
    } catch (_) {
      if (mounted) setState(() => _loadFailed = true);
    }
  }

  void _retry() {
    setState(() {
      _settings = null;
      _loadFailed = false;
    });
    _load();
  }

  bool get _soundOn => _settings!['sound_enabled'] == '1';

  bool get _vibrationOn => _settings!['vibration_enabled'] == '1';

  /// The stored volume, clamped to 0–100; a corrupt stored value
  /// falls back to the D-25 default of 100, never throws.
  int get _volume {
    final parsed = int.tryParse(_settings!['sound_volume'] ?? '');
    if (parsed == null) return 100;
    return parsed.clamp(0, 100);
  }

  /// Persists one setting immediately and updates the UI. On a
  /// failed write the displayed values are re-read from storage so
  /// the screen never shows a value that did not persist.
  Future<void> _updateSetting(String key, String value) async {
    final dependencies = AppDependenciesScope.maybeOf(context)?.dependencies;
    if (dependencies == null) return;
    final l10n = stringsOf(context);
    setState(() => _settings = {..._settings!, key: value});
    try {
      await dependencies.settings.setSetting(key, value);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.settingsSaveFailed)));
      _retry();
    }
  }

  Future<void> _resetToDefaults() async {
    final l10n = stringsOf(context);
    final confirmed = await ConfirmationDialog.show(
      context,
      title: l10n.settingsResetTitle,
      message: l10n.settingsResetMessage,
      confirmLabel: l10n.settingsResetConfirm,
    );
    if (!confirmed || !mounted) return;
    final dependencies = AppDependenciesScope.maybeOf(context)?.dependencies;
    if (dependencies == null) return;
    setState(() {
      _settings = null;
      _loadFailed = false;
    });
    try {
      await dependencies.settings.resetToDefaults();
    } catch (_) {
      if (mounted) setState(() => _loadFailed = true);
      return;
    }
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(stringsOf(context).settingsTitle)),
      body: _body(),
    );
  }

  Widget _body() {
    final l10n = stringsOf(context);
    if (_unavailable) {
      return EmptyState(
        icon: Icons.settings_outlined,
        title: l10n.settingsUnavailableTitle,
        hint: l10n.settingsUnavailableHint,
      );
    }
    if (_loadFailed) {
      return ErrorView(message: l10n.settingsLoadFailed, onRetry: _retry);
    }
    final settings = _settings;
    if (settings == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return ListView(
      padding: DiceUpSpacing.screenPadding,
      children: [
        SwitchListTile(
          title: Text(l10n.settingsSound),
          subtitle: Text(l10n.settingsSoundComingSoon),
          value: _soundOn,
          // Disabled on purpose (D-32): no sound code exists, so
          // the toggle must not imply playback can be turned on.
          onChanged: null,
        ),
        SwitchListTile(
          title: Text(l10n.settingsVibration),
          subtitle: Text(l10n.settingsVibrationDescription),
          value: _vibrationOn,
          onChanged: (value) =>
              _updateSetting('vibration_enabled', value ? '1' : '0'),
        ),
        const SizedBox(height: DiceUpSpacing.sm),
        Text(
          l10n.settingsVolume(_volume),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        Slider(
          value: _volume.toDouble(),
          min: 0,
          max: 100,
          divisions: 100,
          label: _volume.toString(),
          onChanged: (value) =>
              _updateSetting('sound_volume', value.round().toString()),
        ),
        Text(
          l10n.settingsVolumeStored,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: DiceUpSpacing.lg),
        SecondaryButton(
          label: l10n.settingsResetDefaults,
          onPressed: _resetToDefaults,
        ),
        const SizedBox(height: DiceUpSpacing.lg),
        Text(
          // M2.10 (M-13): the version matches pubspec.yaml (0.1.0+1).
          // Sourcing it from the pubspec at runtime (package_info_plus)
          // is a later step — until then this literal is kept in sync
          // with the pubspec by the M2.10 footer test.
          l10n.settingsFooter('0.1.0+1'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}
