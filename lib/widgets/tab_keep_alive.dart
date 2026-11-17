import 'dart:async';

import 'package:flutter/material.dart';

import '../services/tab_refresh.dart';

/// A home tab kept alive across tab switches (owner decision 2026-11-17,
/// dev/audits/tabs_keepalive_decisions.md). It loads once, then refetches
/// only when its [TabRefresh] says so, and only while it is the tab on
/// screen: 350 ms after a show, or on a resume while it shows.
mixin TabKeepAlive<T extends StatefulWidget> on State<T>, AutomaticKeepAliveClientMixin<T> {
  AppTab get tab;

  /// Refetches without the first-load spinner, through [TabRefresh.track].
  void refreshInBackground();

  /// The tab came on screen or left it (also while a nav tap crosses it).
  /// Not called for the first build: check [tabShown] in initState.
  void onTabShown() {}
  void onTabHidden() {}

  /// The tab is settled on screen: 350 ms after a show, or the app resumed
  /// while it shows. Runs before the refresh check.
  void onTabSettled() {}

  TabRefresh get refreshState => tabRefresh[tab]!;
  bool get tabShown => isShown(tab);

  /// A snackbar from this tab. Dropped while another tab is on screen, as it
  /// was when a tab you left was disposed.
  void showTabSnackBar(SnackBar bar) {
    if (tabShown) ScaffoldMessenger.of(context).showSnackBar(bar);
  }

  static const _settle = Duration(milliseconds: 350);
  late bool _shown;
  DateTime? _away;
  Timer? _settleTimer;
  late final AppLifecycleListener _life;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _shown = tabShown;
    shownTab.addListener(_onShownTab);
    _life = AppLifecycleListener(onHide: () => _away = DateTime.now(), onResume: _onResume);
  }

  @override
  void dispose() {
    _settleTimer?.cancel();
    _life.dispose();
    shownTab.removeListener(_onShownTab);
    super.dispose();
  }

  void _onShownTab() {
    if (!mounted || tabShown == _shown) return;
    _shown = tabShown;
    _settleTimer?.cancel();
    if (!_shown) return onTabHidden();
    onTabShown();
    // After the slide, so a nav tap that only crosses this tab fetches nothing.
    _settleTimer = Timer(_settle, () {
      if (!mounted || !tabShown) return;
      onTabSettled();
      if (refreshState.due(DateTime.now())) refreshInBackground();
    });
  }

  /// More than 5 minutes away, or a new day: stale, refetched now if the tab
  /// shows, else on its next show. A shorter trip refetches nothing.
  void _onResume() {
    final away = _away;
    _away = null;
    if (away != null && refreshState.due(DateTime.now(), resumed: away)) refreshState.stale = true;
    if (!mounted || !tabShown) return;
    onTabSettled();
    if (refreshState.stale) refreshInBackground();
  }
}
