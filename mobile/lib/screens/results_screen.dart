import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../data/app_data.dart';
import '../data/us_states.dart';
import '../models/politician.dart';
import '../models/scoring.dart';
import '../services/result_store.dart';
import '../theme/app_theme.dart';
import '../widgets/pillar_bars.dart';
import '../widgets/rank_list.dart';
import '../widgets/spectrum_bar.dart';
import '../widgets/ui_kit.dart';
import '../widgets/voteaxis_logo.dart';
import 'compare_screen.dart';
import 'friend_compare_screen.dart';
import 'methodology_screen.dart';
import 'politician_detail_screen.dart';

class ResultsScreen extends StatefulWidget {
  const ResultsScreen({
    super.key,
    required this.userProfile,
    required this.data,
    required this.onRetake,
    required this.onHome,
    this.homeStateCode,
    this.figureFloor = FigureFloor.year2000,
    this.timeBlind = false,
    this.handSet = false,
  });

  final SpectrumProfile userProfile;
  final AppData data;
  final VoidCallback onRetake;
  final VoidCallback onHome;
  final String? homeStateCode;
  final int figureFloor;
  final bool timeBlind;

  /// The placement was set by hand on the level screen, not scored from a
  /// quiz run. Says so above everything else.
  final bool handSet;

  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen>
    with SingleTickerProviderStateMixin {
  final _shareKey = GlobalKey();
  late final TabController _tabs;
  String _officeFilter = 'all';
  String? _partyFilter;
  String? _stateFilter;
  (int, int)? _era;
  bool _ballotMode = true;
  bool _furthest = false;
  static const _matchPageSize = 20;

  int _matchLimit = _matchPageSize;

  /// True = only their state's ballot, false = nationwide. Their own state is
  /// the default because the whole point is who they can actually vote for.
  bool _stateScope = true;

  /// Office chips, per tab. The value is what [_officeFilter] holds.
  static const _ballotOffices = [
    ('governor', 'Governor'),
    ('senator', 'U.S. Senate'),
    ('representative', 'U.S. House'),
    ('state_senator', 'State Senate'),
    ('state_representative', 'State House'),
  ];

  static const _historicalOffices = [('presidents', 'Presidents')];

  static const _eras = <String, (int, int)>{
    '1960s': (1960, 1969),
    '1980s': (1980, 1989),
    '2000s': (2000, 2009),
    '2010s': (2010, 2019),
    '2020s': (2020, 2026),
  };

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this)
      // The score strip shrinks on the Matches tab, so it has to rebuild as
      // the tab moves, not only when the body finishes animating.
      ..addListener(() {
        if (mounted) setState(() {});
      });
    _stateScope = widget.homeStateCode != null;
    _stateFilter = _stateScope ? widget.homeStateCode : null;
    _ballotMode = true;
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  /// Halfway through the swipe is close enough to commit to the small strip.
  bool get _compactStrip =>
      (_tabs.animation?.value ?? _tabs.index.toDouble()) > 0.5;

  int get _activeFilterCount =>
      (_officeFilter == 'all' ? 0 : 1) +
      (_partyFilter == null ? 0 : 1) +
      (_era == null ? 0 : 1);

  @override
  void didUpdateWidget(covariant ResultsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.homeStateCode != widget.homeStateCode && _stateScope) {
      _stateFilter = widget.homeStateCode;
    }
  }

  SpectrumProfile get _profile => widget.userProfile;

  bool get _showsPastUi => FigureFloor.showsPastUi(widget.figureFloor);

  bool get _scopedToState => _stateScope && widget.homeStateCode != null;

  String get _scopeName =>
      UsStates.nameFor(widget.homeStateCode) ?? widget.homeStateCode ?? 'state';

  List<Politician> get _filteredPoliticians {
    return widget.data.politicians.where((p) {
      if (!p.servedSince(widget.figureFloor)) return false;
      if (_showsPastUi) {
        if (_ballotMode) {
          if (!p.isElectoralOffice) return false;
        } else if (p.isElectoralOffice) {
          return false;
        }
      }
      if (_officeFilter == 'presidents' && !p.isPresident) return false;
      if (_officeFilter == 'current' && !p.current) return false;
      if (_officeFilter == 'governor' && p.officeType != 'governor') {
        return false;
      }
      if (_officeFilter == 'senator' && p.officeType != 'senator') return false;
      if (_officeFilter == 'representative' &&
          p.officeType != 'representative') {
        return false;
      }
      if (_officeFilter == 'state_senator' && p.officeType != 'state_senator') {
        return false;
      }
      if (_officeFilter == 'state_representative' &&
          p.officeType != 'state_representative') {
        return false;
      }
      if (_partyFilter != null && p.party != _partyFilter) return false;
      if (_stateFilter != null && p.state != _stateFilter) {
        final stateTied =
            p.officeType == 'governor' ||
            p.officeType == 'senator' ||
            p.officeType == 'representative' ||
            p.officeType == 'state_senator' ||
            p.officeType == 'state_representative';
        if (stateTied && (_ballotMode || !_showsPastUi)) return false;
      }
      if (_showsPastUi && _era != null && !p.servedDuring(_era!.$1, _era!.$2)) {
        return false;
      }
      return true;
    }).toList();
  }

  static const _officeNotes = {
    'presidents': 'Presidents',
    'current': 'In office',
    'governor': 'Governor',
    'senator': 'U.S. Senate',
    'representative': 'U.S. House',
    'state_senator': 'State Senate',
    'state_representative': 'State House',
  };

  /// Spells out the slice of the roster the headline match came from, since
  /// the filters that pick it sit far below the card.
  String get _matchScopeNote {
    final office = _officeNotes[_officeFilter];
    return [
      if (_showsPastUi) _ballotMode ? 'ACTIVE BALLOT' : 'HISTORICAL',
      if (!_showsPastUi || _ballotMode)
        _scopedToState ? _scopeName.toUpperCase() : 'NATIONWIDE',
      ?office?.toUpperCase(),
      ?_partyFilter?.toUpperCase(),
      if (_showsPastUi && _era != null) '${_era!.$1}s',
    ].join(' · ');
  }

  Map<String, String> get _pillarLabels => {
    for (final p in widget.data.pillars) p.id: p.label,
  };

  Map<String, String> get _issueLabels => {
    for (final i in widget.data.issues) i.id: i.label,
  };

  Future<void> _shareCard({required MatchResult closest}) async {
    final boundary =
        _shareKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return;
    final image = await boundary.toImage(pixelRatio: 3);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) return;
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/spectrum_share.png');
    await file.writeAsBytes(bytes.buffer.asUint8List());
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        text:
            "I'm ${Scoring.formatScore(_profile.axisScore)} on Voteaxis. "
            'Closest: ${closest.politician.name}. '
            'voteaxis.org',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rankedFiltered = Scoring.rankPoliticians(
      user: _profile,
      politicians: _filteredPoliticians,
      issues: widget.data.issues,
    );
    // The list can be flipped to lead with the furthest; the closest match
    // under these same filters stays the head of the unflipped ranking.
    final matches = _furthest
        ? ([...rankedFiltered]
            ..sort((a, b) => b.distance.compareTo(a.distance)))
        : rankedFiltered;
    final inRoster = [
      for (final p in widget.data.politicians)
        if (p.servedSince(widget.figureFloor)) p,
    ];
    final ballotMatches = Scoring.rankPoliticians(
      user: _profile,
      politicians: [
        for (final p in inRoster)
          if (p.isElectoralOffice) p,
      ],
      issues: widget.data.issues,
    );
    final historicalMatches = Scoring.rankPoliticians(
      user: _profile,
      politicians: [
        for (final p in inRoster)
          if (!p.isElectoralOffice) p,
      ],
      issues: widget.data.issues,
    );
    final topBallot = ballotMatches.isNotEmpty ? ballotMatches.first : null;
    final topHistorical = _showsPastUi && historicalMatches.isNotEmpty
        ? historicalMatches.first
        : null;
    // Both the headline strip and the axis highlight track the filters and the
    // scope the match list is set to, not the whole roster.
    final topMatch = rankedFiltered.isNotEmpty ? rankedFiltered.first : null;
    final leadMatch = matches.isNotEmpty ? matches.first : null;

    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        title: Text(
          'Your spectrum',
          style: GoogleFonts.manrope(fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            tooltip: 'Share my result',
            onPressed: topMatch == null
                ? null
                : () => _shareCard(closest: topMatch),
            icon: const Icon(Icons.ios_share),
          ),
          IconButton(
            tooltip: 'Methodology',
            onPressed: () => _openMethodology(),
            icon: const Icon(Icons.info_outline),
          ),
          TextButton(
            onPressed: widget.onHome,
            child: Text(
              'Home',
              style: GoogleFonts.manrope(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Column(
                  children: [
                    if (widget.handSet) ...[
                      const _HandSetBanner(),
                      const SizedBox(height: 10),
                    ],
                    _scoreStrip(leadMatch),
                    const SizedBox(height: 10),
                    _tabSwitcher(matches.length),
                  ],
                ),
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabs,
                  children: [
                    _youTab(matches: matches, leadMatch: leadMatch),
                    _matchesTab(matches),
                  ],
                ),
              ),
            ],
          ),
          // Kept mounted whichever tab is up, so the app-bar share always has
          // a laid-out card to rasterise.
          if (topMatch != null)
            Positioned(
              left: 0,
              top: 0,
              width: 360,
              height: 640,
              child: Offstage(
                offstage: true,
                child: RepaintBoundary(
                  key: _shareKey,
                  child: _ShareCard(
                    axisLabel:
                        '${Scoring.labelForScore(_profile.axisScore)} · '
                        '${Scoring.formatScore(_profile.axisScore)}',
                    closestName: topMatch.politician.name,
                    ballotName:
                        _showsPastUi &&
                            topBallot != null &&
                            topBallot.politician.id != topMatch.politician.id
                        ? topBallot.politician.name
                        : null,
                    historicalName:
                        topHistorical != null &&
                            topHistorical.politician.id !=
                                topMatch.politician.id
                        ? topHistorical.politician.name
                        : null,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _openMethodology({String? topic}) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MethodologyScreen(initialTopic: topic),
      ),
    );
  }

  /// The one thing that stays on screen across both tabs: the score, and who
  /// currently leads under the filters the Matches tab is set to. It shrinks
  /// to a single row there, where the list needs the height more than the
  /// breakdown does.
  Widget _scoreStrip(MatchResult? leadMatch) {
    final formatted = Scoring.formatScore(_profile.axisScore);
    final label = Scoring.labelForScore(_profile.axisScore);
    final scoreColor = _profile.axisScore < -4
        ? AppColors.liberal
        : _profile.axisScore > 4
        ? AppColors.conservative
        : AppColors.center;
    final labelColor = scoreColor == AppColors.center
        ? AppColors.sheet.withValues(alpha: 0.7)
        : scoreColor.withValues(alpha: 0.95);
    final leadLine = leadMatch == null
        ? null
        : '${_furthest ? 'Furthest' : 'Closest'}: '
              '${leadMatch.politician.name}';

    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: Container(
        width: double.infinity,
        padding: _compactStrip
            ? const EdgeInsets.fromLTRB(14, 10, 16, 10)
            : const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: AppColors.ink,
          borderRadius: BorderRadius.circular(18),
        ),
        child: _compactStrip
            ? Row(
                children: [
                  const VoteaxisMark(size: 26),
                  const SizedBox(width: 10),
                  Text(
                    formatted,
                    style: GoogleFonts.manrope(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4,
                      color: AppColors.sheet,
                    ),
                  ),
                  // No label here. "Conservative 19" already carries the side,
                  // and "Slightly conservative" beside it only competed with
                  // the lead match for room — it lost, and truncated to
                  // "Slightl…". The full label is a tab away.
                  if (leadLine != null) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        leadLine,
                        textAlign: TextAlign.right,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.manrope(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: AppColors.sheet.withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                  ],
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const VoteaxisMark(size: 30),
                      const SizedBox(width: 10),
                      Text(
                        'Overall place',
                        style: GoogleFonts.ibmPlexMono(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.1,
                          color: AppColors.sheet.withValues(alpha: 0.55),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    formatted,
                    style: GoogleFonts.manrope(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.8,
                      color: AppColors.sheet,
                    ),
                  ),
                  const SizedBox(height: 2),
                  // Its own line. Beside a 28px score there was never room for
                  // "Moderately conservative", and it truncated to
                  // "Moderately conser…" on a normal-width phone.
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.manrope(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: labelColor,
                    ),
                  ),
                  if (leadLine != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      leadLine,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.manrope(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AppColors.sheet.withValues(alpha: 0.65),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _matchScopeNote,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.ibmPlexMono(
                        fontSize: 10,
                        letterSpacing: 0.8,
                        color: AppColors.sheet.withValues(alpha: 0.4),
                      ),
                    ),
                  ],
                ],
              ),
      ),
    );
  }

  Widget _tabSwitcher(int matchCount) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.sheet,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.ink.withValues(alpha: 0.06)),
      ),
      child: TabBar(
        controller: _tabs,
        indicatorSize: TabBarIndicatorSize.tab,
        indicator: BoxDecoration(
          color: AppColors.ink,
          borderRadius: BorderRadius.circular(11),
        ),
        splashBorderRadius: BorderRadius.circular(11),
        dividerColor: Colors.transparent,
        labelColor: AppColors.sheet,
        unselectedLabelColor: AppColors.inkMuted,
        labelStyle: GoogleFonts.manrope(
          fontSize: 14,
          fontWeight: FontWeight.w800,
        ),
        unselectedLabelStyle: GoogleFonts.manrope(
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
        tabs: [
          const Tab(height: 48, text: 'You'),
          Tab(height: 48, text: 'Matches · $matchCount'),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- You tab

  Widget _youTab({
    required List<MatchResult> matches,
    required MatchResult? leadMatch,
  }) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
      children: [
        const SectionHeading('Where you landed'),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
          decoration: BoxDecoration(
            color: AppColors.sheet,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.ink.withValues(alpha: 0.06)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'On the axis',
                style: GoogleFonts.manrope(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Liberal 100 ← 0 → Conservative 100',
                style: GoogleFonts.ibmPlexMono(
                  fontSize: 11,
                  color: AppColors.inkMuted,
                ),
              ),
              const SizedBox(height: 14),
              SpectrumBar(
                userScore: _profile.axisScore,
                markers: [
                  for (final m in matches.take(12))
                    SpectrumMarker(
                      id: m.politician.id,
                      score: m.axisScore,
                      distance: m.distance,
                    ),
                ],
                highlightId: leadMatch?.politician.id,
                height: 84,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        PillarBars(
          pillarScores: _profile.pillarScores,
          pillarLabels: _pillarLabels,
        ),
        const SizedBox(height: 12),
        IssueScoreBreakdown(
          issueScores: _profile.issueScores,
          issueLabels: _issueLabels,
          issueWeights: _profile.issueWeights,
          questions: widget.data.questions,
        ),
        const SizedBox(height: 26),
        const SectionHeading('Next'),
        Row(
          children: [
            Expanded(
              child: ActionTile(
                icon: Icons.group_outlined,
                label: 'Compare with\na friend',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => FriendCompareScreen(
                        data: widget.data,
                        profile: _profile,
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ActionTile(
                icon: Icons.history_toggle_off_rounded,
                label: 'Compare\nsaved runs',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => CompareScreen(
                        baseProfile: _profile,
                        data: widget.data,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: ActionTile(
                icon: Icons.replay_rounded,
                label: 'Retake\nthe quiz',
                onTap: widget.onRetake,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ActionTile(
                icon: Icons.calculate_outlined,
                label: 'How this\nwas scored',
                onTap: () => _openMethodology(topic: MethodologyTopic.axis),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ------------------------------------------------------------ Matches tab

  Widget _matchesTab(List<MatchResult> matches) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
          child: Column(
            children: [
              if (_showsPastUi) ...[
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: true, label: Text('Active ballot')),
                      ButtonSegment(value: false, label: Text('Historical')),
                    ],
                    selected: {_ballotMode},
                    showSelectedIcon: false,
                    onSelectionChanged: (value) {
                      final ballot = value.first;
                      setState(() {
                        _ballotMode = ballot;
                        _officeFilter = 'all';
                        _stateScope = ballot && widget.homeStateCode != null;
                        _stateFilter = _stateScope
                            ? widget.homeStateCode
                            : null;
                        _era = ballot ? null : _era;
                        _matchLimit = _matchPageSize;
                      });
                    },
                  ),
                ),
                const SizedBox(height: 10),
              ],
              if (_ballotMode && widget.homeStateCode != null) ...[
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<bool>(
                    segments: [
                      ButtonSegment(
                        value: true,
                        icon: const Icon(Icons.how_to_vote_outlined, size: 18),
                        label: Text(
                          UsStates.nameFor(widget.homeStateCode) ??
                              widget.homeStateCode!,
                        ),
                      ),
                      const ButtonSegment(
                        value: false,
                        icon: Icon(Icons.public_rounded, size: 18),
                        label: Text('National'),
                      ),
                    ],
                    selected: {_stateScope},
                    showSelectedIcon: false,
                    onSelectionChanged: (value) => setState(() {
                      _stateScope = value.first;
                      _stateFilter = _stateScope ? widget.homeStateCode : null;
                      _matchLimit = _matchPageSize;
                    }),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              Row(
                children: [
                  Expanded(
                    child: ControlButton(
                      icon: Icons.swap_vert_rounded,
                      label: _furthest ? 'Furthest first' : 'Closest first',
                      selected: _furthest,
                      onTap: () => setState(() {
                        _furthest = !_furthest;
                        _matchLimit = _matchPageSize;
                      }),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ControlButton(
                      icon: Icons.tune_rounded,
                      label: 'Filters',
                      badge: _activeFilterCount,
                      selected: _activeFilterCount > 0,
                      onTap: _openFilters,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: Text(
                  _matchScopeNote,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.ibmPlexMono(
                    fontSize: 10,
                    letterSpacing: 0.8,
                    color: AppColors.inkMuted,
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 2, 20, 32),
            children: [
              if (matches.isEmpty)
                EmptyState(
                  icon: Icons.filter_alt_off_outlined,
                  title: 'No one is left',
                  body: 'These filters rule out everyone in the roster.',
                  action: OutlinedButton(
                    onPressed: _resetFilters,
                    child: const Text('Clear filters'),
                  ),
                )
              else
                RankList(
                  matches: matches.take(_matchLimit).toList(),
                  data: widget.data,
                  userAxisScore: _profile.axisScore,
                  furthest: _furthest,
                  timeBlind: widget.timeBlind,
                  onTap: (p) {
                    MatchResult? match;
                    for (final m in matches) {
                      if (m.politician.id == p.id) {
                        match = m;
                        break;
                      }
                    }
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => PoliticianDetailScreen(
                          politician: p,
                          userProfile: _profile,
                          data: widget.data,
                          match: match,
                          figureFloor: widget.figureFloor,
                        ),
                      ),
                    );
                  },
                ),
              if (matches.length > _matchLimit) ...[
                const SizedBox(height: 10),
                Center(
                  child: OutlinedButton(
                    onPressed: () =>
                        setState(() => _matchLimit += _matchPageSize),
                    child: Text(
                      'Show more (${matches.length - _matchLimit} left)',
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              Text(
                _rosterNote,
                style: GoogleFonts.manrope(
                  fontSize: 12,
                  height: 1.45,
                  fontWeight: FontWeight.w500,
                  color: AppColors.inkMuted,
                ),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () =>
                      _openMethodology(topic: MethodologyTopic.matching),
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 48),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                  icon: const Icon(Icons.info_outline, size: 16),
                  label: const Text('How matching works'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// What the roster on this tab is drawn from — the fine print that used to
  /// sit above the list and push it off the first screen.
  String get _rosterNote {
    if (!_showsPastUi) {
      final scope = _scopedToState
          ? 'Your $_scopeName ballot'
          : 'Everyone nationwide';
      return '$scope — anyone last in office in 2000 or later. '
          'Open Settings for 1980s plus or 1960s plus.';
    }
    if (_ballotMode) {
      return _scopedToState
          ? 'Your $_scopeName ballot, ranked by the issues you weighted.'
          : 'Candidates and officeholders nationwide, ranked by the issues '
                'you weighted.';
    }
    return 'Presidents and historical figures on the same issue scale '
        '(${FigureFloor.labels[widget.figureFloor]}). Era filters use years in '
        'their office history.';
  }

  void _resetFilters() {
    setState(() {
      _officeFilter = 'all';
      _partyFilter = null;
      _era = null;
      _matchLimit = _matchPageSize;
    });
  }

  Future<void> _openFilters() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.paper,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            // One tap has to move the list behind the sheet and the chips in
            // it, so both setStates fire together.
            void change(VoidCallback apply) {
              setState(() {
                apply();
                _matchLimit = _matchPageSize;
              });
              setSheetState(() {});
            }

            final shown = _filteredPoliticians.length;
            return SafeArea(
              top: false,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(sheetContext).size.height * 0.8,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 12, 4),
                      child: Row(
                        children: [
                          Text(
                            'Filters',
                            style: GoogleFonts.manrope(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.4,
                            ),
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: _activeFilterCount == 0
                                ? null
                                : () => change(() {
                                    _officeFilter = 'all';
                                    _partyFilter = null;
                                    _era = null;
                                  }),
                            child: const Text('Reset'),
                          ),
                        ],
                      ),
                    ),
                    Flexible(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(20, 6, 20, 12),
                        shrinkWrap: true,
                        children: [
                          _FilterGroup(
                            label: 'Office',
                            children: [
                              _FilterChip(
                                label: 'All offices',
                                selected: _officeFilter == 'all',
                                onSelected: () =>
                                    change(() => _officeFilter = 'all'),
                              ),
                              for (final office
                                  in _ballotMode
                                      ? _ballotOffices
                                      : _historicalOffices)
                                _FilterChip(
                                  label: office.$2,
                                  selected: _officeFilter == office.$1,
                                  onSelected: () => change(
                                    () => _officeFilter =
                                        _officeFilter == office.$1
                                        ? 'all'
                                        : office.$1,
                                  ),
                                ),
                            ],
                          ),
                          _FilterGroup(
                            label: 'Party',
                            children: [
                              for (final party in const [
                                'Democratic',
                                'Republican',
                              ])
                                _FilterChip(
                                  label: party,
                                  selected: _partyFilter == party,
                                  onSelected: () => change(
                                    () => _partyFilter = _partyFilter == party
                                        ? null
                                        : party,
                                  ),
                                ),
                            ],
                          ),
                          if (_showsPastUi && !_ballotMode)
                            _FilterGroup(
                              label: 'Era in office',
                              children: [
                                for (final era in _eras.entries)
                                  if (era.value.$2 >= widget.figureFloor)
                                    _FilterChip(
                                      label: era.key,
                                      selected: _era == era.value,
                                      onSelected: () => change(
                                        () => _era = _era == era.value
                                            ? null
                                            : era.value,
                                      ),
                                    ),
                              ],
                            ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 6, 20, 12),
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () => Navigator.of(sheetContext).pop(),
                          child: Text(
                            shown == 1
                                ? 'Show 1 figure'
                                : 'Show $shown figures',
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// A labelled row of chips inside the filter sheet.
class _FilterGroup extends StatelessWidget {
  const _FilterGroup({required this.label, required this.children});

  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: GoogleFonts.ibmPlexMono(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
              color: AppColors.inkMuted,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: children),
        ],
      ),
    );
  }
}

/// Marks a placement the user set by hand so nothing below reads as a measured
/// quiz score.
class _HandSetBanner extends StatelessWidget {
  const _HandSetBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.parchment,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.ink.withValues(alpha: 0.08)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.tune_rounded, size: 20, color: AppColors.ink),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  QuizRun.handSetLabel,
                  style: GoogleFonts.ibmPlexMono(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.1,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'You placed yourself on the axis instead of taking the quiz. '
                  'Matching uses the same scale, but nothing here is weighted '
                  'by how much each issue matters to you.',
                  style: GoogleFonts.manrope(
                    fontSize: 13,
                    height: 1.4,
                    fontWeight: FontWeight.w500,
                    color: AppColors.inkMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(),
      showCheckmark: false,
      selectedColor: AppColors.ink,
      backgroundColor: AppColors.sheet,
      side: BorderSide(
        color: selected ? AppColors.ink : AppColors.ink.withValues(alpha: 0.1),
      ),
      labelStyle: GoogleFonts.manrope(
        color: selected ? AppColors.sheet : AppColors.ink,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
        fontSize: 13,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4),
    );
  }
}

class _ShareCard extends StatelessWidget {
  const _ShareCard({
    required this.axisLabel,
    this.closestName,
    this.ballotName,
    this.historicalName,
  });

  final String axisLabel;
  final String? closestName;
  final String? ballotName;
  final String? historicalName;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 360,
      height: 640,
      padding: const EdgeInsets.fromLTRB(28, 36, 28, 28),
      color: AppColors.paper,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const VoteaxisBrandLockup(markSize: 48, fontSize: 24, compact: true),
          const Spacer(),
          Text(
            "I'm $axisLabel",
            style: GoogleFonts.manrope(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.6,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 20),
          if (closestName != null) ...[
            Text(
              'CLOSEST MATCH',
              style: GoogleFonts.ibmPlexMono(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.1,
                color: AppColors.inkMuted,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              closestName!,
              style: GoogleFonts.manrope(
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (ballotName != null) ...[
            Text(
              'BALLOT MATCH',
              style: GoogleFonts.ibmPlexMono(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.1,
                color: AppColors.inkMuted,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              ballotName!,
              style: GoogleFonts.manrope(
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (historicalName != null) ...[
            Text(
              'HISTORICAL MATCH',
              style: GoogleFonts.ibmPlexMono(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.1,
                color: AppColors.inkMuted,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              historicalName!,
              style: GoogleFonts.manrope(
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
          const Spacer(),
          Container(
            height: 12,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              gradient: const LinearGradient(
                colors: [
                  AppColors.liberal,
                  Color(0xFFE8EEF6),
                  AppColors.conservative,
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Liberal 100 ← 0 → Conservative 100',
            style: GoogleFonts.ibmPlexMono(
              fontSize: 11,
              color: AppColors.inkMuted,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'voteaxis.org',
            style: GoogleFonts.manrope(
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
