import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../data/us_states.dart';
import '../screens/contribute_screen.dart';
import '../services/app_feel.dart';
import '../services/voteaxis_api.dart';
import '../theme/app_theme.dart';
import '../widgets/ui_kit.dart';
import '../widgets/voteaxis_logo.dart';

/// App hub — actions only. Distinct from first-run onboarding.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.hasSavedResult,
    required this.hasInProgress,
    required this.homeStateCode,
    required this.onHomeStateChanged,
    required this.onStartQuiz,
    required this.onResumeQuiz,
    required this.onViewResults,
    required this.onMethodology,
    this.onFriendCompare,
    this.onSetLevel,
    this.onExplore,
    this.onSettings,
    this.week,
    this.skipQuiz = false,
    this.reduceMotion = false,
  });

  final bool hasSavedResult;
  final bool hasInProgress;
  final String? homeStateCode;
  final Future<void> Function(String stateCode) onHomeStateChanged;
  final VoidCallback onStartQuiz;
  final VoidCallback onResumeQuiz;
  final VoidCallback onViewResults;
  final VoidCallback onMethodology;
  final VoidCallback? onFriendCompare;

  /// Bypass the quiz and hand-set a placement.
  final VoidCallback? onSetLevel;

  /// Browse the roster without a placement — explore mode.
  final VoidCallback? onExplore;
  final VoidCallback? onSettings;
  final IssueOfTheWeek? week;

  /// Lead with hand-set placement instead of the quiz.
  final bool skipQuiz;
  final bool reduceMotion;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _enter;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _enter = AnimationController(
      vsync: this,
      duration: widget.reduceMotion
          ? Duration.zero
          : AppFeel.duration(const Duration(milliseconds: 500)),
    )..forward();
    _fade = CurvedAnimation(parent: _enter, curve: Curves.easeOutCubic);
  }

  @override
  void dispose() {
    _enter.dispose();
    super.dispose();
  }

  String get _stateName =>
      UsStates.nameFor(widget.homeStateCode) ?? 'your state';

  String get _statusTitle {
    if (widget.hasInProgress) return 'Quiz in progress';
    if (widget.hasSavedResult) return 'Welcome back';
    return 'Ready when you are';
  }

  String get _statusBody {
    if (widget.hasInProgress) {
      return 'Pick up where you left off, or start fresh.';
    }
    if (widget.hasSavedResult) {
      return widget.skipQuiz
          ? 'Review who matches your issues in $_stateName — or adjust your level.'
          : 'Review who matches your issues in $_stateName — or retake the quiz.';
    }
    if (widget.skipQuiz) {
      return 'Place yourself on the axis in about thirty seconds. Then see which $_stateName candidates stand closest to your views.';
    }
    return 'About three minutes. Then see which $_stateName candidates stand closest to your views.';
  }

  Future<void> _pickState() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      backgroundColor: AppColors.sheet,
      builder: (context) {
        return SafeArea(
          child: ListView.builder(
            itemCount: UsStates.all.length,
            itemBuilder: (context, index) {
              final s = UsStates.all[index];
              final active = s.code == widget.homeStateCode;
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
    if (selected != null) {
      await widget.onHomeStateChanged(selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    final primaryLabel = widget.hasSavedResult || widget.hasInProgress
        ? 'Start a new quiz'
        : 'Start the quiz';
    const quizSubtitle = 'Questions drawn fresh — wording varies each run';
    final leadWithLevel = widget.skipQuiz && widget.onSetLevel != null;

    return Scaffold(
      backgroundColor: AppColors.paper,
      body: FadeTransition(
        opacity: _fade,
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 12, 0),
                child: Row(
                  children: [
                    const VoteaxisMark(size: 40),
                    const SizedBox(width: 12),
                    const VoteaxisWordmark(fontSize: 22),
                    const Spacer(),
                    _StatePill(code: widget.homeStateCode, onTap: _pickState),
                    if (widget.onSettings != null)
                      IconButton(
                        tooltip: 'Settings',
                        onPressed: widget.onSettings,
                        icon: const Icon(Icons.settings_outlined, size: 22),
                        color: AppColors.inkMuted,
                      ),
                    IconButton(
                      tooltip: 'Methodology',
                      onPressed: widget.onMethodology,
                      icon: const Icon(Icons.info_outline, size: 22),
                      color: AppColors.inkMuted,
                    ),
                  ],
                ),
              ),
              Container(
                height: 3,
                margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(99),
                  gradient: LinearGradient(
                    colors: [
                      AppColors.liberal,
                      AppColors.parchment,
                      AppColors.conservative,
                    ],
                  ),
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
                  children: [
                    Text(
                      _statusTitle,
                      style: GoogleFonts.manrope(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.8,
                        height: 1.15,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _statusBody,
                      style: GoogleFonts.manrope(
                        fontSize: 15,
                        height: 1.45,
                        fontWeight: FontWeight.w500,
                        color: AppColors.inkMuted,
                      ),
                    ),
                    const SizedBox(height: 26),
                    if (widget.week != null) ...[
                      _WeekCard(week: widget.week!),
                      const SizedBox(height: 16),
                    ],
                    if (widget.hasSavedResult) ...[
                      const _WidgetHint(),
                      const SizedBox(height: 16),
                    ],
                    const SectionHeading('Start here'),
                    if (leadWithLevel) ...[
                      PrimaryAction(
                        label: widget.hasSavedResult
                            ? 'Adjust your level'
                            : 'Set your level',
                        subtitle:
                            'Place yourself on the axis, then fine-tune by pillar',
                        onTap: widget.onSetLevel!,
                      ),
                      const SizedBox(height: 12),
                      ActionRow(
                        icon: Icons.quiz_outlined,
                        title: primaryLabel,
                        subtitle: quizSubtitle,
                        onTap: widget.onStartQuiz,
                      ),
                    ] else ...[
                      PrimaryAction(
                        label: primaryLabel,
                        subtitle: quizSubtitle,
                        onTap: widget.onStartQuiz,
                      ),
                      if (widget.onSetLevel != null) ...[
                        const SizedBox(height: 12),
                        ActionRow(
                          icon: Icons.tune_rounded,
                          title: widget.hasSavedResult
                              ? 'Set your level by hand'
                              : 'Skip the quiz — set your level',
                          subtitle:
                              'Place yourself on the axis, then fine-tune by pillar',
                          onTap: widget.onSetLevel!,
                        ),
                      ],
                    ],
                    if (widget.onExplore != null) ...[
                      const SizedBox(height: 12),
                      ActionRow(
                        icon: Icons.manage_search_rounded,
                        title: 'Explore the roster',
                        subtitle:
                            'Browse every figure and their record — no quiz needed',
                        onTap: widget.onExplore!,
                      ),
                    ],
                    if (widget.hasInProgress) ...[
                      const SizedBox(height: 12),
                      ActionRow(
                        icon: Icons.play_circle_outline_rounded,
                        title: 'Resume quiz',
                        subtitle: 'Continue your saved answers',
                        onTap: widget.onResumeQuiz,
                        emphasize: true,
                      ),
                    ],
                    if (widget.hasSavedResult) ...[
                      const SizedBox(height: 12),
                      ActionRow(
                        icon: Icons.insights_outlined,
                        title: 'Last results',
                        subtitle: 'Your placement and closest matches',
                        onTap: widget.onViewResults,
                      ),
                      if (widget.onFriendCompare != null) ...[
                        const SizedBox(height: 12),
                        ActionRow(
                          icon: Icons.group_outlined,
                          title: 'Compare with a friend',
                          subtitle:
                              'QR or a 6-digit code — both dots on one axis',
                          onTap: widget.onFriendCompare!,
                        ),
                      ],
                    ],
                    if (!widget.hasSavedResult) ...[
                      const SizedBox(height: 32),
                      const SectionHeading('What you get'),
                      const InfoRow(
                        icon: Icons.how_to_vote_outlined,
                        title: 'Your ballot',
                        body: 'Matches prioritize candidates from your state',
                      ),
                      const SizedBox(height: 10),
                      const InfoRow(
                        icon: Icons.compare_arrows_rounded,
                        title: 'Issue overlap',
                        body: 'Ranked by how close they are to your answers',
                      ),
                      const SizedBox(height: 10),
                      const InfoRow(
                        icon: Icons.bar_chart_rounded,
                        title: 'Five pillars',
                        body:
                            'Economy, rights, health, justice, and the world — '
                            'each scored on its own',
                      ),
                      const SizedBox(height: 10),
                      const InfoRow(
                        icon: Icons.gavel_rounded,
                        title: 'Receipts',
                        body:
                            'Roll-call votes blend into curated scores wherever '
                            'the record exists',
                      ),
                      const SizedBox(height: 10),
                      const InfoRow(
                        icon: Icons.balance_rounded,
                        title: 'Steel man',
                        body:
                            'The strongest case against your own strongest '
                            'leans, not just agreement',
                      ),
                      const SizedBox(height: 10),
                      const InfoRow(
                        icon: Icons.lock_outline_rounded,
                        title: 'Stays yours',
                        body:
                            'Answers are stored encrypted on this device — no '
                            'account, no profile sold',
                      ),
                    ],
                    const SizedBox(height: 32),
                    const SectionHeading('Keep it independent'),
                    ActionRow(
                      icon: Icons.volunteer_activism_outlined,
                      title: 'Contribute to Voteaxis',
                      subtitle:
                          'Keep scoring independent — the civic loop stays free',
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const ContributeScreen(),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The state is the one bit of chrome that changes what results say, so it
/// reads as a control rather than another text link.
class _StatePill extends StatelessWidget {
  const _StatePill({required this.code, required this.onTap});

  final String? code;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.sheet,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.pill),
        onTap: onTap,
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(color: AppColors.ink.withValues(alpha: 0.12)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.place_outlined,
                size: 16,
                color: AppColors.inkMuted,
              ),
              const SizedBox(width: 6),
              Text(
                code ?? 'State',
                style: GoogleFonts.manrope(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  color: AppColors.ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WidgetHint extends StatelessWidget {
  const _WidgetHint();

  @override
  Widget build(BuildContext context) {
    return Text(
      'Add the Issue of the Day widget to agree or disagree from your Home Screen. '
      'One tap nudges that issue — it does not replace the quiz.',
      style: GoogleFonts.manrope(
        fontSize: 13,
        height: 1.4,
        fontWeight: FontWeight.w500,
        color: AppColors.inkMuted,
      ),
    );
  }
}

class _WeekCard extends StatelessWidget {
  const _WeekCard({required this.week});

  final IssueOfTheWeek week;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: AppColors.sheet,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.ink.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ISSUE OF THE WEEK',
            style: GoogleFonts.ibmPlexMono(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.1,
              color: AppColors.inkMuted,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            week.headline,
            style: GoogleFonts.manrope(
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            week.question,
            style: GoogleFonts.manrope(
              fontSize: 14,
              height: 1.4,
              color: AppColors.inkMuted,
            ),
          ),
          if (week.context != null && week.context!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              week.context!,
              style: GoogleFonts.manrope(
                fontSize: 12,
                height: 1.4,
                color: AppColors.inkMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
