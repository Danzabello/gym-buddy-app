import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'wardrobe_hub_screen.dart';
import 'wardrobe_selection_state.dart';

/// Entry point for the Wardrobe flow (Avatar / Border / Ring colour).
/// Owns a nested Navigator so the hub + all three sub-screens share one
/// [WardrobeSelectionState] instance without registering it app-wide.
/// Pops with `true` if changes were saved, `false`/null otherwise.
class WardrobePage extends StatefulWidget {
  const WardrobePage({super.key});

  @override
  State<WardrobePage> createState() => _WardrobePageState();
}

class _WardrobePageState extends State<WardrobePage> {
  late final Future<WardrobeSelectionState> _stateFuture = WardrobeSelectionState.load();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<WardrobeSelectionState>(
      future: _stateFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        return ChangeNotifierProvider.value(
          value: snapshot.data!,
          child: Navigator(
            onGenerateRoute: (settings) => MaterialPageRoute(
              builder: (_) => const WardrobeHubScreen(),
            ),
          ),
        );
      },
    );
  }
}
