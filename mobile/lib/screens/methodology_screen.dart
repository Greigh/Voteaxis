import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/politician.dart';
import '../theme/app_theme.dart';
import '../widgets/ui_kit.dart';

/// Named anchors so other screens can open this page straight to the part
/// that explains what the user was just looking at.
class MethodologyTopic {
  MethodologyTopic._();

  static const issues = 'issues';
  static const pillars = 'pillars';
  static const axis = 'axis';
  static const matching = 'matching';
  static const confidence = 'confidence';
  static const receipts = 'receipts';
  static const floor = 'floor';
  static const dailyIssue = 'daily_issue';
}

class MethodologyScreen extends StatefulWidget {
  const MethodologyScreen({super.key, this.initialTopic});

  /// A [MethodologyTopic] to open expanded, scrolled into view.
  final String? initialTopic;

  @override
  State<MethodologyScreen> createState() => _MethodologyScreenState();
}

class _MethodologyScreenState extends State<MethodologyScreen> {
  final _anchors = <String, GlobalKey>{};

  GlobalKey _anchor(String topic) =>
      _anchors.putIfAbsent(topic, () => GlobalKey());

  @override
  void initState() {
    super.initState();
    final topic = widget.initialTopic;
    if (topic == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = _anchors[topic]?.currentContext;
      if (context == null) return;
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
        alignment: 0.1,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Methodology')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          Text(
            'SPECTRUM ISSUE INDEX · V1',
            style: GoogleFonts.ibmPlexMono(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
              color: AppColors.inkMuted,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Spectrum Issue Index (SII) v1',
            style: GoogleFonts.manrope(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.6,
              color: AppColors.navy,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Voteaxis uses our own method — not a third-party ideology score. '
            'We ask you the same issues we score for each figure, and you say '
            'how much each one matters to you.',
            style: GoogleFonts.manrope(
              fontSize: 14,
              height: 1.45,
              fontWeight: FontWeight.w500,
              color: AppColors.inkMuted,
            ),
          ),
          const SizedBox(height: 18),
          const _PipelineCard(),
          const SizedBox(height: 26),
          SectionHeading('How you are scored'),
          _MethodTile(
            key: _anchor(MethodologyTopic.issues),
            topic: MethodologyTopic.issues,
            initialTopic: widget.initialTopic,
            step: '1',
            title: 'Issues & importance',
            gist: 'One public scale, plus how much you care',
            children: const [
              _Body(
                'Every stance — yours and each figure\'s — sits on the same '
                'public scale, with no minus signs.',
              ),
              _Mono('Liberal 100 ← 0 → Conservative 100'),
              _Bullet(
                'Quiz answers use a five-point Likert that maps onto '
                'that scale.',
              ),
              _Bullet(
                'A second control asks how important the issue is to '
                'you, from Low to Essential.',
              ),
              Callout(
                'Land hard on one side and results can flip a Steel Man card — '
                'the strongest case for the opposite view. It does not change '
                'your score.',
              ),
            ],
          ),
          _MethodTile(
            key: _anchor(MethodologyTopic.pillars),
            topic: MethodologyTopic.pillars,
            initialTopic: widget.initialTopic,
            step: '2',
            title: 'Five pillars',
            gist: 'Issues roll up into five themes',
            children: [
              _chipRow(const [
                'Economy & fiscal',
                'Rights & society',
                'Health & entitlements',
                'Justice & homeland',
                'Climate, energy & world',
              ]),
              const SizedBox(height: 12),
              const _Body(
                'A pillar score is the importance-weighted average of its '
                'issue scores.',
              ),
            ],
          ),
          _MethodTile(
            key: _anchor(MethodologyTopic.axis),
            topic: MethodologyTopic.axis,
            initialTopic: widget.initialTopic,
            step: '3',
            title: 'Overall axis',
            gist: 'The one number at the top of your results',
            children: const [
              _Body(
                'Your overall score is an importance-weighted average of the '
                'issues you answered, on the same Liberal 100 ← 0 → '
                'Conservative 100 scale.',
              ),
              Callout(
                'Mark up to three dealbreakers in the quiz. Candidates who '
                'clash hard on those issues are flagged even if the rest of '
                'the match is close.',
              ),
            ],
          ),
          const SizedBox(height: 22),
          SectionHeading('How figures are scored'),
          _MethodTile(
            key: _anchor(MethodologyTopic.matching),
            topic: MethodologyTopic.matching,
            initialTopic: widget.initialTopic,
            step: '4',
            title: 'Matching',
            gist: 'Why someone lands near you',
            children: const [
              _Body(
                'Politicians are ranked by weighted mean absolute difference '
                'across the issues you both have a score on — issues you '
                'marked more important count more.',
              ),
              _Bullet(
                'Each card names your top agreements and disagreements, '
                'so you can see why someone is close.',
              ),
            ],
          ),
          _MethodTile(
            key: _anchor(MethodologyTopic.confidence),
            topic: MethodologyTopic.confidence,
            initialTopic: widget.initialTopic,
            step: '5',
            title: 'Confidence & roll-call votes',
            gist: 'Where each curated stance comes from',
            children: [
              _chipRow(const [
                'documented',
                'inferred',
                'contested',
                'rollcall',
              ]),
              const SizedBox(height: 12),
              const _Body(
                'Every issue in a profile carries one of those four tags. Older '
                'presidents often rest on inferred historical judgments.',
              ),
              _Bullet(
                'Each profile also shows a one-line rollup — documented, mixed, '
                'or inferred — so you can see at a glance how much of the '
                'vector is a public record versus a party-alignment estimate. '
                'A statewide official may be documented in their own lane and '
                'inferred on foreign policy.',
              ),
              _Bullet(
                'For members of Congress with a bioguide id, issue '
                'scores blend the curated vector with coded floor votes '
                '(VoteView, 117th Congress on) once an issue has at least '
                'three mapped votes.',
              ),
              _Bullet(
                'We map bills to SII issues by title; the VoteView '
                'cutting line says which side is conservative.',
              ),
              _Bullet(
                'A profile\'s vote-record slider shows those floor votes '
                'by Congress. Dragging it does not change the lifetime blend '
                'used for matching.',
              ),
              _Bullet('Governors, presidents, and nominees stay curated.'),
              Callout('We do not import DW-NOMINATE member scores.'),
            ],
          ),
          _MethodTile(
            key: _anchor(MethodologyTopic.receipts),
            topic: MethodologyTopic.receipts,
            initialTopic: widget.initialTopic,
            step: '6',
            title: 'Congress receipts',
            gist: 'The bill lists on a profile',
            children: const [
              _Body(
                'ProPublica retired their Congress API, so we run our own '
                'Congress REST API on the VPS, indexed from BICAM (bicam.net), '
                'and show recent sponsored and cosponsored bills.',
              ),
              _Bullet(
                'Congress.gov can freshen the latest action and official '
                'summaries on the cards already on screen.',
              ),
              Callout(
                'Those bill lists are receipts, not the roll-call blend above. '
                'A fresher "Became Public Law No. 117-169" line does not change '
                'Spectrum Issue Index scores.',
              ),
            ],
          ),
          const SizedBox(height: 22),
          SectionHeading('Settings that change this'),
          _MethodTile(
            key: _anchor(MethodologyTopic.floor),
            topic: MethodologyTopic.floor,
            initialTopic: widget.initialTopic,
            step: '7',
            title: 'How far back',
            gist: 'Which figures you are matched against',
            children: [
              for (final year in FigureFloor.allowed)
                _DefinitionRow(
                  term: FigureFloor.labels[year]!,
                  detail: FigureFloor.blurbs[year]!,
                ),
              const SizedBox(height: 6),
              const _Bullet(
                'Sitting members always appear, whatever the '
                'floor.',
              ),
              const _Bullet(
                'Progressive Era quiz wording is only in the '
                '1960s plus bank.',
              ),
              const _Bullet(
                'Time-blind matching and political ancestry unlock '
                'on 1980s plus and 1960s plus.',
              ),
            ],
          ),
          _MethodTile(
            key: _anchor(MethodologyTopic.dailyIssue),
            topic: MethodologyTopic.dailyIssue,
            initialTopic: widget.initialTopic,
            step: '8',
            title: 'Issue of the Day widget',
            gist: 'One prompt a day, nudging one issue',
            children: const [
              _Body(
                'The Issue of the Day widget — home screen on Android, home or '
                'lock screen on iOS — shows a single prompt. Agree or Disagree '
                'nudges that one issue with a small blend.',
              ),
              _Bullet('One calibration per calendar day.'),
              _Bullet(
                'If you have not taken the quiz, the widget asks you to '
                'open Voteaxis first.',
              ),
              Callout('It does not replace the quiz.'),
            ],
          ),
        ],
      ),
    );
  }
}

/// Answers in, one axis out — the four hops the prose below spells out.
class _PipelineCard extends StatelessWidget {
  const _PipelineCard();

  static const _steps = [
    ('Your answers', 'Five-point Likert, plus how much it matters'),
    ('Issues', 'One shared scale for you and every figure'),
    ('Five pillars', 'Importance-weighted average per theme'),
    ('Your axis', 'One score, then everyone ranked against it'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        color: AppColors.ink,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < _steps.length; i++) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(top: 5),
                  decoration: BoxDecoration(
                    color: AppColors.accent,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _steps[i].$1,
                        style: GoogleFonts.manrope(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: AppColors.sheet,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _steps[i].$2,
                        style: GoogleFonts.manrope(
                          fontSize: 12,
                          height: 1.35,
                          fontWeight: FontWeight.w500,
                          color: AppColors.sheet.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (i != _steps.length - 1)
              Container(
                width: 1,
                height: 16,
                margin: const EdgeInsets.only(left: 3.5),
                color: AppColors.sheet.withValues(alpha: 0.25),
              ),
          ],
        ],
      ),
    );
  }
}

/// One collapsible chapter. Collapsed it shows a numbered step and a one-line
/// gist, so the whole method reads as a table of contents before you open it.
class _MethodTile extends StatelessWidget {
  const _MethodTile({
    super.key,
    required this.topic,
    required this.step,
    required this.title,
    required this.gist,
    required this.children,
    this.initialTopic,
  });

  final String topic;
  final String? initialTopic;
  final String step;
  final String title;
  final String gist;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: AppColors.sheet,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: AppColors.ink.withValues(alpha: 0.06)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            initiallyExpanded: initialTopic == topic,
            tilePadding: const EdgeInsets.symmetric(horizontal: 14),
            childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 16),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            leading: Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.parchment,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Text(
                step,
                style: GoogleFonts.ibmPlexMono(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
            ),
            title: Text(
              title,
              style: GoogleFonts.manrope(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
              ),
            ),
            subtitle: Text(
              gist,
              style: GoogleFonts.manrope(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppColors.inkMuted,
              ),
            ),
            children: children,
          ),
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text,
        style: GoogleFonts.manrope(
          fontSize: 13.5,
          height: 1.45,
          fontWeight: FontWeight.w500,
          color: AppColors.ink,
        ),
      ),
    );
  }
}

class _Mono extends StatelessWidget {
  const _Mono(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.parchment,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          text,
          style: GoogleFonts.ibmPlexMono(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.ink,
          ),
        ),
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 4,
            height: 4,
            margin: const EdgeInsets.only(top: 8, left: 2, right: 10),
            decoration: BoxDecoration(
              color: AppColors.inkMuted.withValues(alpha: 0.6),
              shape: BoxShape.circle,
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.manrope(
                fontSize: 13.5,
                height: 1.45,
                fontWeight: FontWeight.w500,
                color: AppColors.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A row of static labels — the pillars, the confidence tags.
Widget _chipRow(List<String> labels) {
  return Wrap(
    spacing: 6,
    runSpacing: 6,
    children: [for (final label in labels) PillChip(label)],
  );
}

class _DefinitionRow extends StatelessWidget {
  const _DefinitionRow({required this.term, required this.detail});

  final String term;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            term,
            style: GoogleFonts.manrope(
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            detail,
            style: GoogleFonts.manrope(
              fontSize: 13,
              height: 1.4,
              fontWeight: FontWeight.w500,
              color: AppColors.inkMuted,
            ),
          ),
        ],
      ),
    );
  }
}
