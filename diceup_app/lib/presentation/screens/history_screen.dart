import 'package:flutter/material.dart';

import '../../core/design_system/diceup_components.dart';

/// Local match history (SRS UI-09, FR-31).
///
/// Phase 2 shows the honest empty state: no matches have been played yet.
/// Phase 3 backs this screen with the SQLite repository
/// (reverse-chronological list + detail view). No sample or fake matches
/// are ever shown.
class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Match History')),
      body: const EmptyState(
        icon: Icons.history,
        title: 'No matches yet',
        hint: 'Finished offline matches will appear here, newest first.',
      ),
    );
  }
}
