import 'package:duo_fold/duo_fold.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../data/us_states.dart';
import '../duo/duo_scope.dart';
import '../services/civic_links.dart';
import '../models/app_settings.dart';
import '../models/politician.dart';
import '../models/quiz_bank.dart';
import '../models/scoring.dart';
import '../theme/app_theme.dart';
import '../widgets/ui_kit.dart';
import 'contribute_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.settings,
    required this.onSettings,
    this.homeStateCode,
    this.homeDistrict,
    this.onHomeState,
    this.onHomeDistrict,
    this.onTransfer,
    this.onClearProgress,
    this.onDeleteEverything,
    this.onMethodology,
    this.hasInProgress = false,
    this.hasSavedResult = false,
  });

  final AppSettings settings;
  final Future<void> Function(AppSettings next) onSettings;
  final String? homeStateCode;
  final int? homeDistrict;
  final Future<void> Function(String stateCode)? onHomeState;
  final Future<void> Function(int? district)? onHomeDistrict;

  /// Opens device-to-device transfer.
  final VoidCallback? onTransfer;
  final Future<void> Function()? onClearProgress;
  final Future<void> Function()? onDeleteEverything;
  final VoidCallback? onMethodology;
  final bool hasInProgress;
  final bool hasSavedResult;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late AppSettings _settings = widget.settings.normalized;
  late String? _homeState = widget.homeStateCode;
  late int? _homeDistrict = widget.homeDistrict;
  late bool _hasInProgress = widget.hasInProgress;
  late bool _hasSavedResult = widget.hasSavedResult;

  bool get _showsPastUi => _settings.showsPastUi;

  Future<void> _update(AppSettings next) async {
    final normalized = next.normalized;
    setState(() => _settings = normalized);
    await widget.onSettings(normalized);
  }

  Future<void> _pickState() async {
    final onHomeState = widget.onHomeState;
    if (onHomeState == null) return;
    final selected = await showFoldAwareSheet<String>(
      context: context,
      showDragHandle: true,
      backgroundColor: AppColors.sheet,
      builder: (context) {
        return SafeArea(
          child: ListView.builder(
            itemCount: UsStates.all.length,
            itemBuilder: (context, index) {
              final s = UsStates.all[index];
              final active = s.code == _homeState;
              return ListTile(
                title: Text(
                  s.name,
                  style: GoogleFonts.manrope(
                    fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
                trailing: active
                    ? Icon(Icons.check_rounded, color: AppColors.ink)
                    : Text(
                        s.code,
                        style: GoogleFonts.ibmPlexMono(
                          color: AppColors.inkMuted,
                        ),
                      ),
                onTap: () => Navigator.pop(context, s.code),
              );
            },
          ),
        );
      },
    );
    if (selected == null) return;
    await onHomeState(selected);
    await widget.onHomeDistrict?.call(null);
    if (!mounted) return;
    setState(() {
      _homeState = selected;
      _homeDistrict = null;
    });
  }

  Future<void> _pickDistrict() async {
    final onHomeDistrict = widget.onHomeDistrict;
    final seats = UsStates.districtCount(_homeState);
    if (onHomeDistrict == null || seats == 0) return;
    final selected = await showFoldAwareSheet<int>(
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
                  'Statewide',
                  style: GoogleFonts.manrope(fontWeight: FontWeight.w600),
                ),
                subtitle: const Text('Show every House district'),
                trailing: _homeDistrict == null
                    ? Icon(Icons.check_rounded, color: AppColors.ink)
                    : null,
                onTap: () => Navigator.pop(context, -1),
              ),
              for (var n = 1; n <= seats; n++)
                ListTile(
                  title: Text(
                    seats == 1 ? 'At-large' : 'District $n',
                    style: GoogleFonts.manrope(
                      fontWeight: _homeDistrict == n
                          ? FontWeight.w800
                          : FontWeight.w600,
                    ),
                  ),
                  trailing: _homeDistrict == n
                      ? Icon(Icons.check_rounded, color: AppColors.ink)
                      : null,
                  onTap: () => Navigator.pop(context, n),
                ),
            ],
          ),
        );
      },
    );
    if (selected == null) return;
    final district = selected < 1 ? null : selected;
    await onHomeDistrict(district);
    if (!mounted) return;
    setState(() => _homeDistrict = district);
  }

  /// vote.gov is the official federal voter-information site — the URL only
  /// carries a state name, so opening it sends nothing personal anywhere.
  Future<void> _openRegistration() async {
    await CivicLinks.openVoterRegistration(_homeState);
  }

  Future<void> _clearProgress() async {
    final onClear = widget.onClearProgress;
    if (onClear == null) return;
    await onClear();
    if (!mounted) return;
    setState(() => _hasInProgress = false);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('In-progress quiz discarded')));
  }

  Future<void> _deleteEverything() async {
    final onDelete = widget.onDeleteEverything;
    if (onDelete == null) return;
    final confirmed = await showFoldAwareDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete everything?'),
        content: const Text(
          'Your saved runs, your placement, and every setting are erased from '
          'this phone. This cannot be undone — if you want to keep them, move '
          'them to another phone first.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.conservative,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await onDelete();
    if (!mounted) return;
    setState(() {
      _settings = const AppSettings();
      _homeState = null;
      _homeDistrict = null;
      _hasInProgress = false;
      _hasSavedResult = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          // ── The quiz ───────────────────────────────────────────────────
          const _Section(
            title: 'The quiz',
            blurb: 'How you get placed on the axis, and how long it takes.',
          ),
          _Group(
            children: [
              SwitchListTile(
                contentPadding: _rowPadding,
                title: _title('Skip the quiz'),
                subtitle: _subtitle(
                  _settings.skipQuiz
                      ? 'The hub leads with hand-set placement. The quiz is still '
                            'there if you change your mind.'
                      : 'Lead with hand-set placement instead — drag yourself onto '
                            'the axis and fine-tune by pillar.',
                ),
                value: _settings.skipQuiz,
                onChanged: (value) =>
                    _update(_settings.copyWith(skipQuiz: value)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _title('Quiz length'),
                    const SizedBox(height: 6),
                    _subtitle(
                      'Every length covers all 22 issues. Longer runs add '
                      'alternate wordings so one odd question pulls less weight.',
                    ),
                    const SizedBox(height: 12),
                    _Segmented<int>(
                      value: QuizBank.coerceLength(_settings.quizLength),
                      options: QuizBank.lengthOptions,
                      labelFor: (length) => QuizBank.lengthLabels[length]!,
                      onChanged: (length) =>
                          _update(_settings.copyWith(quizLength: length)),
                    ),
                    const SizedBox(height: 10),
                    _subtitle(
                      QuizBank.lengthBlurbs[QuizBank.coerceLength(
                        _settings.quizLength,
                      )]!,
                    ),
                  ],
                ),
              ),
              SwitchListTile(
                contentPadding: _rowPadding,
                title: _title('Dealbreaker prompts'),
                subtitle: _subtitle(
                  'Show the flag control during the quiz so you can mark up to '
                  '${Scoring.maxDealbreakers} issues you will not compromise on.',
                ),
                value: _settings.dealbreakerPrompts,
                onChanged: (value) =>
                    _update(_settings.copyWith(dealbreakerPrompts: value)),
              ),
            ],
          ),

          // ── Matching ───────────────────────────────────────────────────
          const _Section(
            title: 'How far back',
            blurb:
                '2000s plus is the modern-day default. Step earlier for '
                'Reagan-era or Kennedy-era figures. Progressive Era quiz '
                'wording only unlocks at 1960s plus.',
          ),
          _Group(
            children: [
              RadioGroup<int>(
                groupValue: _settings.figureFloor,
                onChanged: (value) {
                  if (value == null) return;
                  _update(_settings.copyWith(figureFloor: value));
                },
                child: Column(
                  children: [
                    for (final year in FigureFloor.allowed)
                      RadioListTile<int>(
                        contentPadding: _rowPadding,
                        value: year,
                        title: Text(
                          FigureFloor.labels[year]!,
                          style: GoogleFonts.manrope(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        subtitle: _subtitle(FigureFloor.blurbs[year]!),
                      ),
                  ],
                ),
              ),
              SwitchListTile(
                contentPadding: _rowPadding,
                title: _title('Time-blind matching'),
                subtitle: _subtitle(
                  _showsPastUi
                      ? 'Hide years and ordinals on the match list so recency does '
                            'not steer you. Profiles still show the full bio.'
                      : 'Available on 1980s plus and 1960s plus.',
                ),
                value: _settings.timeBlind,
                onChanged: _showsPastUi
                    ? (value) => _update(_settings.copyWith(timeBlind: value))
                    : null,
              ),
            ],
          ),

          // ── Ballot ─────────────────────────────────────────────────────
          if (widget.onHomeState != null) ...[
            const _Section(
              title: 'Your ballot',
              blurb:
                  'Matches put candidates you can actually vote for at the top.',
            ),
            _Group(
              children: [
                ListTile(
                  contentPadding: _rowPadding,
                  title: _title('Home state'),
                  subtitle: _subtitle(
                    UsStates.nameFor(_homeState) ?? 'Not set',
                  ),
                  trailing: Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.ink.withValues(alpha: 0.35),
                  ),
                  onTap: _pickState,
                ),
                ListTile(
                  contentPadding: _rowPadding,
                  title: _title('Congressional district'),
                  subtitle: _subtitle(
                    _homeState == null
                        ? 'Set a home state first'
                        : _homeDistrict == null
                        ? 'Statewide — every House district'
                        : UsStates.districtCount(_homeState) == 1
                        ? 'At-large'
                        : 'District $_homeDistrict — House matches narrow to it',
                  ),
                  trailing: Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.ink.withValues(alpha: 0.35),
                  ),
                  enabled: _homeState != null,
                  onTap: _pickDistrict,
                ),
                ListTile(
                  contentPadding: _rowPadding,
                  title: _title('Register or check registration'),
                  subtitle: _subtitle(
                    _homeState == null
                        ? 'vote.gov — pick your state there'
                        : 'vote.gov for ${UsStates.nameFor(_homeState)}',
                  ),
                  trailing: Icon(
                    Icons.open_in_new_rounded,
                    size: 18,
                    color: AppColors.ink.withValues(alpha: 0.35),
                  ),
                  onTap: _openRegistration,
                ),
              ],
            ),
          ],

          // ── Feel ───────────────────────────────────────────────────────
          const _Section(
            title: 'Feel',
            blurb: 'Sound, motion, and what shows up outside the app.',
          ),
          _Group(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _title('Theme'),
                    const SizedBox(height: 6),
                    _subtitle('Light, dark, or matching your device.'),
                    const SizedBox(height: 12),
                    _Segmented<AppThemeMode>(
                      value: _settings.theme,
                      options: AppThemeMode.values,
                      labelFor: (theme) => switch (theme) {
                        AppThemeMode.system => 'System',
                        AppThemeMode.light => 'Light',
                        AppThemeMode.dark => 'Dark',
                      },
                      onChanged: (theme) =>
                          _update(_settings.copyWith(theme: theme)),
                    ),
                  ],
                ),
              ),
              SwitchListTile(
                contentPadding: _rowPadding,
                title: _title('Haptics'),
                subtitle: _subtitle(
                  'A small tap when you pick an answer or land a scan.',
                ),
                value: _settings.haptics,
                onChanged: (value) =>
                    _update(_settings.copyWith(haptics: value)),
              ),
              SwitchListTile(
                contentPadding: _rowPadding,
                title: _title('Reduce motion'),
                subtitle: _subtitle(
                  'Drop the fades and the drifting spectrum rail.',
                ),
                value: _settings.reduceMotion,
                onChanged: (value) =>
                    _update(_settings.copyWith(reduceMotion: value)),
              ),
              SwitchListTile(
                contentPadding: _rowPadding,
                title: _title('Issue of the Day widget'),
                subtitle: _subtitle(
                  'Keep the home-screen widget fed with a fresh issue. Turn it off '
                  'and the widget stops updating.',
                ),
                value: _settings.issueWidget,
                onChanged: (value) =>
                    _update(_settings.copyWith(issueWidget: value)),
              ),
              SwitchListTile(
                contentPadding: _rowPadding,
                title: _title('Daily reminder'),
                subtitle: _subtitle(
                  'A 9am nudge when a new Issue of the Day is up. Scheduled on '
                  'this phone — nothing is sent anywhere.',
                ),
                value: _settings.dailyReminder,
                onChanged: (value) =>
                    _update(_settings.copyWith(dailyReminder: value)),
              ),
            ],
          ),

          // ── Transfer ───────────────────────────────────────────────────
          if (widget.onTransfer != null) ...[
            const _Section(
              title: 'Your data',
              blurb:
                  'Quiz answers never leave this phone. Sharing a result is a '
                  'separate, revocable step you take on purpose.',
            ),
            _Group(
              children: [
                ListTile(
                  contentPadding: _rowPadding,
                  leading: const Icon(Icons.link_rounded),
                  title: _title('Share & transfer'),
                  subtitle: _subtitle(
                    'One link moves you to a new phone or shows a friend where '
                    'you landed — password optional',
                  ),
                  trailing: Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.ink.withValues(alpha: 0.35),
                  ),
                  onTap: widget.onTransfer,
                ),
              ],
            ),
          ],
          if (widget.onClearProgress != null ||
              widget.onDeleteEverything != null)
            const SizedBox(height: 12),
          if (widget.onClearProgress != null ||
              widget.onDeleteEverything != null)
            _Group(
              danger: true,
              children: [
                if (widget.onClearProgress != null)
                  ListTile(
                    contentPadding: _rowPadding,
                    leading: const Icon(Icons.restart_alt_rounded),
                    title: _title('Discard in-progress quiz'),
                    subtitle: _subtitle(
                      _hasInProgress
                          ? 'Throw away the run you have partway through'
                          : 'Nothing in progress',
                    ),
                    enabled: _hasInProgress,
                    onTap: _hasInProgress ? _clearProgress : null,
                  ),
                if (widget.onDeleteEverything != null)
                  ListTile(
                    contentPadding: _rowPadding,
                    leading: Icon(
                      Icons.delete_outline_rounded,
                      color: AppColors.conservative,
                    ),
                    title: Text(
                      'Delete everything',
                      style: GoogleFonts.manrope(
                        fontWeight: FontWeight.w800,
                        color: AppColors.conservative,
                      ),
                    ),
                    subtitle: _subtitle(
                      _hasSavedResult || _hasInProgress
                          ? 'Erase saved runs and reset every setting'
                          : 'Reset every setting on this phone',
                    ),
                    onTap: _deleteEverything,
                  ),
              ],
            ),

          // ── iPhone Duo ─────────────────────────────────────────────────
          // Only exists on foldable hardware; everywhere else the stream is
          // the constant unsupported state and this section collapses.
          DuoFoldBuilder(
            builder: (context, fold, mode) {
              if (!fold.isDuo) return const SizedBox.shrink();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _Section(
                    title: 'iPhone Duo',
                    blurb:
                        'How the app uses the two halves of the display when '
                        'the phone is half open.',
                  ),
                  _Group(
                    children: [
                      Consumer(
                        builder: (context, ref, _) => SwitchListTile(
                          contentPadding: _rowPadding,
                          title: _title('Book split'),
                          subtitle: _subtitle(
                            'Half-open like a book: the roster stays on one '
                            'side and the record opens on the other.',
                          ),
                          value: ref.watch(duoBookSplitProvider),
                          onChanged: (value) => ref
                              .read(duoBookSplitProvider.notifier)
                              .set(value),
                        ),
                      ),
                      Consumer(
                        builder: (context, ref, _) => SwitchListTile(
                          contentPadding: _rowPadding,
                          title: _title('Glance card'),
                          subtitle: _subtitle(
                            'Propped like a tent: the Issue of the Week fills '
                            'the top pane.',
                          ),
                          value: ref.watch(duoGlanceEnabledProvider),
                          onChanged: (value) => ref
                              .read(duoGlanceEnabledProvider.notifier)
                              .set(value),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),

          // ── About ──────────────────────────────────────────────────────
          const _Section(
            title: 'About',
            blurb:
                'The civic loop stays free. Optional contributions fund '
                'independent scoring and state-level data.',
          ),
          _Group(
            children: [
              if (widget.onMethodology != null)
                ListTile(
                  contentPadding: _rowPadding,
                  title: _title('How scoring works'),
                  subtitle: _subtitle(
                    'Pillars, roll-call blending, and the axis',
                  ),
                  trailing: Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.ink.withValues(alpha: 0.35),
                  ),
                  onTap: widget.onMethodology,
                ),
              ListTile(
                contentPadding: _rowPadding,
                title: _title('Contribute to Voteaxis'),
                subtitle: _subtitle('Open the contribution page'),
                trailing: Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.ink.withValues(alpha: 0.35),
                ),
                onTap: () {
                  Navigator.of(context).push(
                    foldAwareRoute<void>(
                      context,
                      builder: (_) => const ContributeScreen(),
                    ),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  static const _rowPadding = EdgeInsets.symmetric(horizontal: 16);

  Widget _title(String text) =>
      Text(text, style: GoogleFonts.manrope(fontWeight: FontWeight.w800));

  Widget _subtitle(String text) => Text(
    text,
    style: GoogleFonts.manrope(
      fontSize: 13,
      height: 1.35,
      color: AppColors.inkMuted,
    ),
  );
}

/// One card per settings section. Loose rows on the page background read as
/// an unfinished form; a card says "these belong together".
class _Group extends StatelessWidget {
  const _Group({required this.children, this.danger = false});

  final List<Widget> children;

  /// Destructive rows get their own card so a mis-tap needs its own trip.
  final bool danger;

  @override
  Widget build(BuildContext context) {
    // Material, not a decorated box: ListTile paints its ink on the nearest
    // Material ancestor, and a coloured box in between swallows the splash.
    return Material(
      color: AppColors.sheet,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        side: BorderSide(
          color: danger
              ? AppColors.conservative.withValues(alpha: 0.22)
              : AppColors.ink.withValues(alpha: 0.06),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                thickness: 1,
                indent: 16,
                color: AppColors.ink.withValues(alpha: 0.05),
              ),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.blurb});

  final String title;
  final String blurb;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 26, bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeading(title),
          Text(
            blurb,
            style: GoogleFonts.manrope(
              fontSize: 13,
              height: 1.45,
              fontWeight: FontWeight.w500,
              color: AppColors.inkMuted,
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

class _Segmented<T> extends StatelessWidget {
  const _Segmented({
    required this.value,
    required this.options,
    required this.labelFor,
    required this.onChanged,
  });

  final T value;
  final List<T> options;
  final String Function(T option) labelFor;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.parchment.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          for (final option in options)
            Expanded(
              child: Semantics(
                button: true,
                selected: option == value,
                label: labelFor(option),
                onTap: () => onChanged(option),
                excludeSemantics: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onChanged(option),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    constraints: const BoxConstraints(minHeight: 48),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: option == value
                          ? AppColors.ink
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Text(
                      labelFor(option),
                      textAlign: TextAlign.center,
                      style: GoogleFonts.manrope(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: option == value
                            ? AppColors.sheet
                            : AppColors.inkMuted,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
