import 'package:duo_fold/duo_fold.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../data/app_data.dart';
import '../data/us_states.dart';
import '../duo/duo_scope.dart';
import '../models/politician.dart';
import '../models/scoring.dart';
import '../theme/app_theme.dart';
import '../widgets/ui_kit.dart';
import 'politician_detail_screen.dart';

/// Browse the whole roster without a placement. Filters and search work the
/// same way as the match list, but nothing here needs a quiz — a card opens
/// the same profile page, just without a "you" side.
class ExploreScreen extends StatefulWidget {
  const ExploreScreen({
    super.key,
    required this.data,
    this.userProfile,
    this.figureFloor = FigureFloor.year2000,
  });

  final AppData data;
  final SpectrumProfile? userProfile;
  final int figureFloor;

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  String _officeFilter = 'all';
  String? _partyFilter;
  String? _stateFilter;

  /// The figure showing in the split's secondary pane. Taps never leave
  /// the screen while a fold split is in effect — the detail is the pane.
  Politician? _selected;

  static const _offices = [
    ('governor', 'Governor'),
    ('senator', 'U.S. Senate'),
    ('representative', 'U.S. House'),
    ('state_senator', 'State Senate'),
    ('state_representative', 'State House'),
    ('presidents', 'Presidents'),
  ];

  static const _parties = ['Democratic', 'Republican', 'Independent'];

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<Politician> get _filtered {
    return widget.data.politicians.where((p) {
      if (_officeFilter == 'presidents' && !p.isPresident) return false;
      if (_officeFilter != 'all' &&
          _officeFilter != 'presidents' &&
          p.officeType != _officeFilter) {
        return false;
      }
      if (_partyFilter != null && p.party != _partyFilter) return false;
      if (_stateFilter != null && p.state != _stateFilter) return false;
      if (_query.isNotEmpty) {
        final haystack =
            '${p.name} ${p.role} ${p.state} '
                    '${UsStates.nameFor(p.state) ?? ''}'
                .toLowerCase();
        if (!haystack.contains(_query)) return false;
      }
      return true;
    }).toList()..sort((a, b) {
      // Sitting officeholders first — the people you can vote for — then by
      // name so the list stays scannable.
      if (a.current != b.current) return a.current ? -1 : 1;
      return a.name.compareTo(b.name);
    });
  }

  int get _activeFilterCount =>
      (_officeFilter == 'all' ? 0 : 1) +
      (_partyFilter == null ? 0 : 1) +
      (_stateFilter == null ? 0 : 1);

  Future<void> _pickState() async {
    final selected = await showFoldAwareSheet<String>(
      context: context,
      showDragHandle: true,
      backgroundColor: AppColors.sheet,
      builder: (context) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(
                title: Text(
                  'Everywhere',
                  style: GoogleFonts.manrope(fontWeight: FontWeight.w600),
                ),
                trailing: _stateFilter == null
                    ? Icon(Icons.check_rounded, color: AppColors.ink)
                    : null,
                onTap: () => Navigator.pop(context, ''),
              ),
              for (final s in UsStates.all)
                ListTile(
                  title: Text(
                    s.name,
                    style: GoogleFonts.manrope(
                      fontWeight: _stateFilter == s.code
                          ? FontWeight.w800
                          : FontWeight.w600,
                    ),
                  ),
                  trailing: _stateFilter == s.code
                      ? Icon(Icons.check_rounded, color: AppColors.ink)
                      : Text(
                          s.code,
                          style: GoogleFonts.ibmPlexMono(
                            color: AppColors.inkMuted,
                          ),
                        ),
                  onTap: () => Navigator.pop(context, s.code),
                ),
            ],
          ),
        );
      },
    );
    if (selected == null) return;
    setState(() => _stateFilter = selected.isEmpty ? null : selected);
  }

  void _openFilters() {
    showFoldAwareSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: AppColors.sheet,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            void change(VoidCallback apply) {
              setState(apply);
              setSheetState(() {});
            }

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
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
                                  _stateFilter = null;
                                }),
                          child: const Text('Reset'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _groupLabel('OFFICE'),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _chip(
                          'All offices',
                          _officeFilter == 'all',
                          () => change(() => _officeFilter = 'all'),
                        ),
                        for (final office in _offices)
                          _chip(
                            office.$2,
                            _officeFilter == office.$1,
                            () => change(
                              () => _officeFilter = _officeFilter == office.$1
                                  ? 'all'
                                  : office.$1,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _groupLabel('PARTY'),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final party in _parties)
                          _chip(
                            party,
                            _partyFilter == party,
                            () => change(
                              () => _partyFilter = _partyFilter == party
                                  ? null
                                  : party,
                            ),
                          ),
                      ],
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

  Widget _groupLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text,
        style: GoogleFonts.ibmPlexMono(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.2,
          color: AppColors.inkMuted,
        ),
      ),
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? AppColors.navy : AppColors.parchment,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            label,
            style: GoogleFonts.manrope(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: selected ? AppColors.cream : AppColors.ink,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final shown = _filtered;
    final closenessById = <String, MatchResult>{
      if (widget.userProfile != null)
        for (final m in Scoring.rankPoliticians(
          user: widget.userProfile!,
          politicians: shown,
          issues: widget.data.issues,
        ))
          m.politician.id: m,
    };

    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(title: const Text('Explore the roster')),
      body: DuoFoldBuilder(
        builder: (context, fold, mode) {
          final list = _listPane(context, shown, closenessById, mode);
          final split =
              mode == FoldMode.splitVertical ||
              mode == FoldMode.splitHorizontal;
          if (!split) return list;
          final selected = _selected;
          return FoldSplitView(
            fold: fold,
            mode: mode,
            primary: list,
            secondary: selected == null
                ? const _SplitDetailPlaceholder()
                : PoliticianDetailScreen(
                    // Keyed to the person so a new pick resets the pane's
                    // own scroll position.
                    key: ValueKey(selected.id),
                    politician: selected,
                    userProfile: widget.userProfile,
                    data: widget.data,
                    match: closenessById[selected.id],
                    figureFloor: widget.figureFloor,
                    embedded: true,
                    onOpenPolitician: (next) =>
                        setState(() => _selected = next),
                  ),
          );
        },
      ),
    );
  }

  /// The roster column. It must be the same widget tree in single and
  /// split modes so search text, scroll position, and filters survive a
  /// fold transition without remounting.
  Widget _listPane(
    BuildContext context,
    List<Politician> shown,
    Map<String, MatchResult> closenessById,
    FoldMode mode,
  ) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
          child: Column(
            children: [
              TextField(
                controller: _searchCtrl,
                textInputAction: TextInputAction.search,
                autocorrect: false,
                onChanged: (value) =>
                    setState(() => _query = value.trim().toLowerCase()),
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: AppColors.sheet,
                  hintText: 'Search name, office, or state',
                  hintStyle: GoogleFonts.manrope(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.inkMuted,
                  ),
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear search',
                          icon: const Icon(Icons.close_rounded, size: 18),
                          onPressed: () => setState(() {
                            _searchCtrl.clear();
                            _query = '';
                          }),
                        ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                      color: AppColors.ink.withValues(alpha: 0.08),
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                      color: AppColors.ink.withValues(alpha: 0.08),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: AppColors.navy),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: ControlButton(
                      icon: Icons.place_outlined,
                      label: _stateFilter == null
                          ? 'Everywhere'
                          : UsStates.nameFor(_stateFilter) ?? _stateFilter!,
                      selected: _stateFilter != null,
                      onTap: _pickState,
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
                  '${shown.length} of ${widget.data.politicians.length} figures'
                  '${widget.userProfile == null ? ' — no match scores until you take the quiz' : ''}',
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
          child: shown.isEmpty
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(20, 2, 20, 32),
                  child: EmptyState(
                    icon: _query.isNotEmpty
                        ? Icons.search_off_rounded
                        : Icons.filter_alt_off_outlined,
                    title: 'No one is left',
                    body: _query.isNotEmpty
                        ? 'No one in the roster matches “${_searchCtrl.text}”.'
                        : 'These filters rule out everyone in the roster.',
                    action: OutlinedButton(
                      onPressed: () => setState(() {
                        _searchCtrl.clear();
                        _query = '';
                        _officeFilter = 'all';
                        _partyFilter = null;
                        _stateFilter = null;
                      }),
                      child: const Text('Clear all'),
                    ),
                  ),
                )
              : ListView.separated(
                  // Shared storage keeps the scroll offset when the list
                  // migrates between single canvas and a fold pane.
                  key: const PageStorageKey('explore-roster'),
                  padding: const EdgeInsets.fromLTRB(20, 2, 20, 32),
                  itemCount: shown.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final p = shown[index];
                    final match = closenessById[p.id];
                    return _RosterCard(
                      politician: p,
                      match: match,
                      axisScore: widget.data.profileFor(p).axisScore,
                      selected: _selected == p,
                      onTap: () => _open(p, match, mode),
                    );
                  },
                ),
        ),
      ],
    );
  }

  /// Open [p]'s detail. In a fold split the detail is the secondary pane —
  /// select in place instead of pushing; the push is for the one-canvas
  /// layout and stays crease-confined via [foldAwareRoute].
  void _open(Politician p, MatchResult? match, FoldMode mode) {
    final split =
        mode == FoldMode.splitVertical || mode == FoldMode.splitHorizontal;
    if (split) {
      setState(() => _selected = p);
      return;
    }
    Navigator.of(context).push(
      foldAwareRoute<void>(
        context,
        builder: (_) => PoliticianDetailScreen(
          politician: p,
          userProfile: widget.userProfile,
          data: widget.data,
          match: match,
          figureFloor: widget.figureFloor,
        ),
      ),
    );
  }
}

/// One roster row in browse mode — identity, seat, and either the match
/// score (when a placement exists) or their own axis reading.
class _RosterCard extends StatelessWidget {
  const _RosterCard({
    required this.politician,
    required this.axisScore,
    required this.onTap,
    this.match,
    this.selected = false,
  });

  final Politician politician;
  final MatchResult? match;

  /// Their own axis reading — shown when there's no viewer profile to
  /// compare against.
  final double axisScore;
  final VoidCallback onTap;

  /// Split-mode selection highlight — which figure's record is in the
  /// secondary pane.
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final detail = [
      politician.role,
      [
        politician.party,
        if (politician.state.isNotEmpty) politician.state,
        if (politician.current) 'Current' else 'Former',
      ].join(' · '),
    ].join('\n');

    return Material(
      color: AppColors.sheet,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: selected ? AppColors.accent.withValues(alpha: 0.10) : null,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected
                  ? AppColors.accent.withValues(alpha: 0.55)
                  : AppColors.ink.withValues(alpha: 0.07),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      politician.name,
                      style: GoogleFonts.manrope(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      detail,
                      style: GoogleFonts.manrope(
                        fontSize: 12,
                        height: 1.35,
                        fontWeight: FontWeight.w500,
                        color: AppColors.inkMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              if (match != null)
                PillChip(
                  '${match!.closeness}%',
                  color: match!.hasDealbreaker
                      ? AppColors.conservative
                      : AppColors.navy,
                )
              else
                PillChip(
                  Scoring.formatScore(axisScore),
                  color: axisScore < 0
                      ? AppColors.liberal
                      : AppColors.conservative,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// What the secondary pane shows before a figure is picked in a split.
class _SplitDetailPlaceholder extends StatelessWidget {
  const _SplitDetailPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.person_search_rounded,
              size: 34,
              color: AppColors.inkMuted,
            ),
            const SizedBox(height: 12),
            Text(
              'Pick a figure to see their record',
              textAlign: TextAlign.center,
              style: GoogleFonts.manrope(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.inkMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
