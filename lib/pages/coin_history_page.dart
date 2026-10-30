import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/coin_service.dart';
import '../theme/app_theme.dart';
import '../utils/run_once.dart';

// ── Pure helpers ────────────────────────────────────────────────

/// Emoji, variation selectors and joiners out, then trimmed. Stored
/// descriptions carry emojis; the app shows none.
final _emojiRun = RegExp(
  '[\u{1F000}-\u{1FAFF}\u{2190}-\u{21FF}\u{2300}-\u{23FF}\u{2600}-\u{27BF}'
  '\u{2B00}-\u{2BFF}\u{FE0E}\u{FE0F}\u{200D}\u{20E3}]',
  unicode: true,
);
String _clean(String s) => s.replaceAll(_emojiRun, '').trim();

/// What a row shows, from transaction_type and never the stored text.
/// [subtitle] is null when there is nothing to draw.
@visibleForTesting
({String title, String? subtitle}) coinEntryLabel(CoinTransaction t) {
  final d = _clean(t.description);
  String? sub(String? s) => (s == null || s.isEmpty) ? null : s;
  switch (t.transactionType) {
    case 'daily_checkin':
      return (title: 'Daily check-in', subtitle: null);
    case 'partner_bonus':
      return (title: 'Buddy bonus', subtitle: 'Your buddy checked in too');
    case 'earn':
      const prefix = 'Achievement: ';
      if (d.startsWith(prefix)) {
        return (
          title: 'Achievement',
          subtitle: sub(d.substring(prefix.length).trim()),
        );
      }
      return (title: 'Bonus coins', subtitle: sub(d));
    case 'shop_purchase':
      const bought = 'Purchased: ';
      return (
        title: 'Shop purchase',
        subtitle: sub(
          d.startsWith(bought) ? d.substring(bought.length).trim() : d,
        ),
      );
    case 'invite_bonus':
      return (title: 'Invite bonus', subtitle: 'Joined via buddy invite');
    case 'invite_reward':
      return (
        title: 'Invite reward',
        subtitle: 'A friend you invited got going',
      );
    default:
      return (title: 'Coins', subtitle: sub(d));
  }
}

IconData _entryIcon(String type) => switch (type) {
  'daily_checkin' => Icons.local_fire_department_outlined,
  'partner_bonus' => Icons.people_outline,
  'earn' => Icons.emoji_events_outlined,
  'shop_purchase' => Icons.shopping_bag_outlined,
  'invite_bonus' || 'invite_reward' => Icons.card_giftcard_outlined,
  _ => Icons.monetization_on_outlined,
};

/// "+12", "\u221212" (a real minus sign), or "0" with no sign.
@visibleForTesting
String coinAmountText(int amount) => amount > 0
    ? '+$amount'
    : amount < 0
    ? '\u2212${-amount}'
    : '0';

/// "TODAY", "YESTERDAY", else like "WED 28 OCT". [day] and [now] are local.
@visibleForTesting
String coinDayLabel(DateTime day, DateTime now) {
  final d = DateTime(day.year, day.month, day.day);
  if (d == DateTime(now.year, now.month, now.day)) return 'TODAY';
  if (d == DateTime(now.year, now.month, now.day - 1)) return 'YESTERDAY';
  return DateFormat('EEE d MMM').format(d).toUpperCase();
}

class CoinDayGroup {
  final String label;
  final List<CoinTransaction> rows;
  CoinDayGroup(this.label, this.rows);
}

/// Rows (already newest first) bucketed by local calendar day, in order.
@visibleForTesting
List<CoinDayGroup> groupCoinsByDay(List<CoinTransaction> rows, DateTime now) {
  final groups = <CoinDayGroup>[];
  DateTime? current;
  for (final t in rows) {
    final l = t.createdAt.toLocal();
    final day = DateTime(l.year, l.month, l.day);
    if (current != day) {
      current = day;
      groups.add(CoinDayGroup(coinDayLabel(day, now), []));
    }
    groups.last.rows.add(t);
  }
  return groups;
}

// ── Page ────────────────────────────────────────────────────────

/// The three loaders the page needs, so tests can hand it fakes.
class CoinHistoryDeps {
  final Future<List<CoinTransaction>> Function(int offset, CoinFilter filter)
  loadPage;
  final Future<CoinWeekTotals> Function() loadWeekTotals;
  final Future<int> Function() loadBalance;

  const CoinHistoryDeps({
    required this.loadPage,
    required this.loadWeekTotals,
    required this.loadBalance,
  });

  factory CoinHistoryDeps.live() => CoinHistoryDeps(
    loadPage: (offset, filter) =>
        CoinService().getTransactionPage(offset: offset, filter: filter),
    loadWeekTotals: () => CoinService().getWeekTotals(),
    loadBalance: () => CoinService().getBalance(),
  );
}

/// Pops `true` when the user taps Go to Shop.
class CoinHistoryPage extends StatefulWidget {
  final int initialBalance;
  final CoinHistoryDeps? deps;
  const CoinHistoryPage({super.key, required this.initialBalance, this.deps});

  @override
  State<CoinHistoryPage> createState() => _CoinHistoryPageState();
}

class _CoinHistoryPageState extends State<CoinHistoryPage> {
  late final CoinHistoryDeps _deps = widget.deps ?? CoinHistoryDeps.live();
  final _once = RunOnce();

  late int _balance = widget.initialBalance;
  CoinWeekTotals? _totals; // null while loading or if it failed
  CoinFilter _filter = CoinFilter.all;
  List<CoinTransaction> _rows = [];
  bool _loading = true;
  bool _failed = false;
  bool _hasMore = false;
  bool _loadingMore = false;
  int _gen = 0; // a reply from an older filter or reload is dropped

  @override
  void initState() {
    super.initState();
    _reload();
    _refreshBalance();
  }

  @override
  void dispose() {
    _once.dispose();
    super.dispose();
  }

  Future<void> _refreshBalance() async {
    final b = await _deps.loadBalance();
    // getBalance answers 0 for a failed read too; a real drop to 0 between
    // the header and this page can't happen, so a 0 over a balance is noise.
    if (!mounted || (b == 0 && widget.initialBalance > 0)) return;
    setState(() => _balance = b);
  }

  Future<void> _loadTotals() async {
    try {
      final t = await _deps.loadWeekTotals();
      if (mounted) setState(() => _totals = t);
    } catch (_) {
      if (mounted) setState(() => _totals = null);
    }
  }

  Future<void> _loadList() async {
    final gen = ++_gen;
    setState(() {
      _loading = true;
      _failed = false;
      _loadingMore = false;
    });
    try {
      final page = await _deps.loadPage(0, _filter);
      if (!mounted || gen != _gen) return;
      setState(() {
        _rows = page;
        _hasMore = page.length == kCoinPageSize;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || gen != _gen) return;
      setState(() {
        _failed = true;
        _loading = false;
      });
    }
  }

  void _reload() {
    _loadTotals();
    _loadList();
  }

  void _pickFilter(CoinFilter f) {
    if (f == _filter) return;
    _filter = f;
    _loadList();
  }

  Future<void> _showMore() async {
    if (_loadingMore) return;
    final gen = _gen;
    setState(() => _loadingMore = true);
    try {
      final page = await _deps.loadPage(_rows.length, _filter);
      if (!mounted || gen != _gen) return;
      setState(() {
        _rows = [..._rows, ...page];
        _hasMore = page.length == kCoinPageSize;
        _loadingMore = false;
      });
    } catch (_) {
      // The button stays, so tapping it again is the retry.
      if (mounted && gen == _gen) setState(() => _loadingMore = false);
    }
  }

  // One pop only: a double tap would otherwise pop the home screen too.
  void _leave([bool? result]) =>
      _once.latch(() async => Navigator.pop(context, result));

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        toolbarHeight: 72,
        leadingWidth: 72,
        leading: Padding(
          padding: const EdgeInsets.only(left: 16),
          child: Center(
            child: Semantics(
              button: true,
              label: 'Back',
              excludeSemantics: true,
              child: Material(
                color: c.claySurface,
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: _leave,
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: Icon(
                      Icons.chevron_left_rounded,
                      size: 28,
                      color: cs.onSurface,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        title: const Text(
          'Coin history',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  children: [
                    _balanceCard(c, cs),
                    const SizedBox(height: 12),
                    _tiles(c, cs),
                    const SizedBox(height: 16),
                    _chips(c, cs),
                    const SizedBox(height: 20),
                    ..._listArea(c, cs),
                  ],
                ),
                // Short fade so rows don't look cut off above the button.
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: 24,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Theme.of(
                              context,
                            ).scaffoldBackgroundColor.withValues(alpha: 0),
                            Theme.of(context).scaffoldBackgroundColor,
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => _leave(true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: c.streakOrange,
                    foregroundColor: c.readableForeground(c.streakOrange),
                    elevation: 0,
                    minimumSize: const Size.fromHeight(52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text(
                    'Go to Shop',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  BoxDecoration _slab(AppColors c, double radius) => BoxDecoration(
    color: c.claySurface,
    borderRadius: BorderRadius.circular(radius),
    boxShadow: [
      BoxShadow(
        color: c.clayShadowDark,
        blurRadius: 12,
        offset: const Offset(0, 4),
      ),
    ],
  );

  Widget _balanceCard(AppColors c, ColorScheme cs) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: _slab(c, 20),
      child: Row(
        children: [
          _CoinDot(c, 20),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$_balance',
                  style: TextStyle(
                    color: cs.onSurface,
                    fontSize: 34,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  'coins',
                  style: TextStyle(color: c.subtleText, fontSize: 14),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tiles(AppColors c, ColorScheme cs) {
    final t = _totals;
    Widget tile(String label, String value, Color color) => Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: _slab(c, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                color: c.subtleText,
                fontSize: 12,
                letterSpacing: 0.8,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          tile(
            'EARNED, 7 DAYS',
            t == null ? '\u2013' : coinAmountText(t.earned),
            cs.primary,
          ),
          const SizedBox(width: 12),
          tile(
            'SPENT, 7 DAYS',
            t == null ? '\u2013' : coinAmountText(-t.spent),
            cs.onSurface,
          ),
        ],
      ),
    );
  }

  Widget _chips(AppColors c, ColorScheme cs) {
    Widget chip(String label, CoinFilter f) {
      final on = _filter == f;
      final fg = on ? c.readableForeground(cs.primary) : cs.onSurface;
      return Expanded(
        child: Semantics(
          button: true,
          selected: on,
          excludeSemantics: true,
          label: label,
          child: Material(
            color: on ? cs.primary : c.claySurface,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => _pickFilter(f),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: fg,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        chip('All', CoinFilter.all),
        const SizedBox(width: 8),
        chip('Earned', CoinFilter.earned),
        const SizedBox(width: 8),
        chip('Spent', CoinFilter.spent),
      ],
    );
  }

  List<Widget> _listArea(AppColors c, ColorScheme cs) {
    if (_loading) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 32),
          child: Center(child: CircularProgressIndicator(color: cs.primary)),
        ),
      ];
    }
    if (_failed) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Column(
            children: [
              Text(
                'Could not load your coins',
                textAlign: TextAlign.center,
                style: TextStyle(color: cs.onSurface, fontSize: 16),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _reload,
                child: const Text(
                  'Try again',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      ];
    }
    if (_rows.isEmpty && _filter == CoinFilter.all) {
      return [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: _slab(c, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'No coins yet',
                style: TextStyle(
                  color: cs.onSurface,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Check in with your buddy to earn your first coins. '
                'They show up here.',
                style: TextStyle(color: c.subtleText, fontSize: 14),
              ),
            ],
          ),
        ),
      ];
    }
    final now = DateTime.now();
    return [
      for (final g in groupCoinsByDay(_rows, now)) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
          child: Text(
            g.label,
            style: TextStyle(
              color: c.subtleText,
              fontSize: 13,
              letterSpacing: 0.8,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Container(
          decoration: _slab(c, 20),
          child: Column(
            children: [
              for (var i = 0; i < g.rows.length; i++) ...[
                if (i > 0)
                  Divider(
                    height: 1,
                    color: c.divider,
                    indent: 16,
                    endIndent: 16,
                  ),
                _CoinRow(g.rows[i]),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
      ],
      if (_hasMore)
        Center(
          child: TextButton(
            onPressed: _loadingMore ? null : _showMore,
            child: _loadingMore
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: cs.primary,
                    ),
                  )
                : const Text(
                    'Show more',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
          ),
        ),
    ];
  }
}

/// The header pill's gold dot (AppColors.warn), at a bigger size: the pill
/// draws it inline, so there is no widget to reuse.
class _CoinDot extends StatelessWidget {
  final AppColors c;
  final double size;
  const _CoinDot(this.c, this.size);

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(shape: BoxShape.circle, color: c.warn),
  );
}

class _CoinRow extends StatelessWidget {
  final CoinTransaction t;
  const _CoinRow(this.t);

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final cs = Theme.of(context).colorScheme;
    final label = coinEntryLabel(t);
    final local = t.createdAt.toLocal();
    final time = MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.fromDateTime(local),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: c.claySurfaceLight,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              _entryIcon(t.transactionType),
              size: 22,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.title,
                  style: TextStyle(
                    color: cs.onSurface,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (label.subtitle != null)
                  Text(
                    label.subtitle!,
                    style: TextStyle(color: c.subtleText, fontSize: 13),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    coinAmountText(t.amount),
                    style: TextStyle(
                      color: t.amount > 0 ? cs.primary : cs.onSurface,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 6),
                  _CoinDot(c, 8),
                ],
              ),
              Text(time, style: TextStyle(color: c.subtleText, fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }
}
