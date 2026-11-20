import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/coin_service.dart';
import '../../services/level_service.dart';
import '../../services/saved_copy.dart';
import '../../services/tab_refresh.dart' show profileZone;
import '../../utils/crash_report.dart';
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
  WardrobeParts _parts = noWardrobeParts;
  WardrobeSelectionState? _state;
  bool _loading = true;

  /// A load this session answered every part, so the seeds are fresh and a
  /// selection may be saved. False while only the saved copy is known.
  bool _fresh = false;

  @override
  void initState() {
    super.initState();
    _restoreSaved();
    _load();
  }

  /// Builds the screen's state once every part is known. A state that is
  /// already editable stays as it is.
  void _rebuildState() {
    if (!wardrobeReady(_parts) || (_state?.editable ?? false)) return;
    _state = WardrobeSelectionState.fromParts(_parts, editable: _fresh);
  }

  /// First paint from the saved copy, view only. A load that already answered
  /// everything wins; one that answered only some leaves the rest to the copy.
  Future<void> _restoreSaved() async {
    final saved = await SavedCopy.read<WardrobeParts>(
      SavedCopy.uid,
      'wardrobe',
      maxAge: kSavedMaxAgeWardrobe,
      parse: wardrobeFromSaved,
    );
    if (saved == null || !mounted || wardrobeReady(_parts)) return;
    setState(() {
      _parts = wardrobeAfterLoad(saved, _parts);
      _rebuildState();
      _loading = false;
    });
  }

  void _retry() {
    setState(() => _loading = true);
    _load();
  }

  Future<void> _load() async {
    // Each read answers null when it fails: one failing part never blocks the
    // others, and no error is left unobserved. Offline is expected; anything
    // else is sent to Crashlytics as a non-fatal.
    Future<T?> part<T>(String label, Future<T> read) =>
        read.then<T?>((v) => v, onError: (Object e, StackTrace st) {
          reportNonFatal(e, st, label);
          return null;
        });

    try {
      final client = Supabase.instance.client;
      final uid = client.auth.currentUser?.id;
      if (uid == null) {
        if (mounted) setState(() => _loading = false);
        return;
      }

      final (profile, items, unlocks, level) = await (
        part(
            'wardrobe_profile',
            client
                .from('user_profiles')
                .select('avatar_id, avatar_border')
                .eq('id', uid)
                .single()
                .then(wardrobeProfileFromRow)),
        part('wardrobe_shop', CoinService().getShopItems(strict: true)),
        part('wardrobe_cosmetics', LevelService().getUnlockedCosmetics(strict: true)),
        part('wardrobe_level', LevelService().getLevelInfo()),
      ).wait;
      if (!mounted) return;

      // The shop is never empty (36 items live), so an empty list is a failed read too.
      final answered = (
        profile: profile,
        ringItems: items == null || items.isEmpty
            ? null
            : [for (final i in items) if (i.category == 'ring_color') i],
        unlocks: unlocks,
        level: level?.level,
      );
      setState(() {
        _parts = wardrobeAfterLoad(_parts, answered);
        if (wardrobeReady(answered)) _fresh = true;
        _rebuildState();
        _loading = false;
      });

      final payload = wardrobeSavedPayload(answered);
      if (payload != null) {
        unawaited(SavedCopy.write(SavedCopy.uid, 'wardrobe', payload, zone: profileZone));
      }
    } catch (e, st) {
      reportNonFatal(e, st, 'wardrobe_load');
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final state = _state;
    // Nothing known yet and the load failed: a retry, never an empty grid or defaults.
    if (state == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Wardrobe')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Could not load your wardrobe',
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 16),
              ),
              TextButton(
                onPressed: _retry,
                child: const Text(
                  'Try again',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return ChangeNotifierProvider.value(
      value: state,
      child: Navigator(
        onGenerateRoute: (settings) => MaterialPageRoute(
          builder: (_) => const WardrobeHubScreen(),
        ),
      ),
    );
  }
}
