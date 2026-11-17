import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_buddy_app/services/tab_refresh.dart';
import 'package:gym_buddy_app/widgets/tab_keep_alive.dart';

class _Probe extends StatefulWidget {
  const _Probe({super.key});
  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> with AutomaticKeepAliveClientMixin, TabKeepAlive {
  int refreshes = 0, shows = 0, hides = 0, settles = 0;

  @override
  AppTab get tab => AppTab.shop;

  @override
  void initState() {
    super.initState();
    refreshState.track(() async {}); // the first load
  }

  @override
  void refreshInBackground() {
    refreshes++;
    refreshState.track(() async {});
  }

  @override
  void onTabShown() => shows++;
  @override
  void onTabHidden() => hides++;
  @override
  void onTabSettled() => settles++;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return const SizedBox();
  }
}

void main() {
  final key = GlobalKey<_ProbeState>();
  _ProbeState probe() => key.currentState!;

  Future<void> pumpProbe(WidgetTester t) async {
    for (final r in tabRefresh.values) {
      r
        ..lastLoaded = null
        ..stale = false
        ..dirty = false;
    }
    shownTab.value = AppTab.dashboard; // Shop starts hidden
    await t.pumpWidget(MaterialApp(home: Scaffold(body: _Probe(key: key))));
  }

  tearDown(() => shownTab.value = null);

  testWidgets('a nav tap that only crosses the tab fetches nothing', (t) async {
    await pumpProbe(t);
    markStale({AppTab.shop});
    shownTab.value = AppTab.shop;
    await t.pump(const Duration(milliseconds: 100));
    shownTab.value = AppTab.profile;
    await t.pump(const Duration(seconds: 1));
    expect((probe().shows, probe().hides, probe().settles, probe().refreshes), (1, 1, 0, 0));
  });

  testWidgets('a show refetches 350 ms later only when stale', (t) async {
    await pumpProbe(t);
    shownTab.value = AppTab.shop;
    await t.pump(const Duration(milliseconds: 400));
    expect((probe().settles, probe().refreshes), (1, 0)); // fresh: nothing

    shownTab.value = AppTab.dashboard;
    markStale({AppTab.shop}); // a write made elsewhere
    await t.pump();
    expect(probe().refreshes, 0); // hidden: waits for the show
    shownTab.value = AppTab.shop;
    await t.pump(const Duration(milliseconds: 349));
    expect(probe().refreshes, 0);
    await t.pump(const Duration(milliseconds: 2));
    expect(probe().refreshes, 1);
    expect(tabRefresh[AppTab.shop]!.stale, isFalse);
  });

  testWidgets('a resume refetches a stale tab only while it shows', (t) async {
    await pumpProbe(t);
    void trip() {
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    }

    markStale({AppTab.shop});
    trip();
    expect((probe().settles, probe().refreshes), (0, 0)); // hidden

    shownTab.value = AppTab.shop;
    await t.pump(const Duration(milliseconds: 400));
    expect(probe().refreshes, 1);
    trip(); // a short trip with fresh data
    expect((probe().settles, probe().refreshes), (2, 1));
    markStale({AppTab.shop});
    trip();
    expect(probe().refreshes, 2);
  });

  testWidgets('a hidden tab shows no snackbar', (t) async {
    await pumpProbe(t);
    probe().showTabSnackBar(const SnackBar(content: Text('hidden')));
    await t.pump();
    expect(find.text('hidden'), findsNothing);
    shownTab.value = AppTab.shop;
    probe().showTabSnackBar(const SnackBar(content: Text('shown')));
    await t.pump();
    expect(find.text('shown'), findsOneWidget);
  });
}
