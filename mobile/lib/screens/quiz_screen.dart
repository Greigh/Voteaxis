import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/issue.dart';
import '../models/question.dart';
import '../models/scoring.dart';
import '../services/app_feel.dart';
import '../services/result_store.dart';
import '../theme/app_theme.dart';
import '../widgets/ui_kit.dart';

class QuizResult {
  const QuizResult({
    required this.likertIndexes,
    required this.importanceIndexes,
    required this.dealbreakerIssueIds,
  });

  final List<int> likertIndexes;
  final List<int> importanceIndexes;
  final List<String> dealbreakerIssueIds;
}

class QuizScreen extends StatefulWidget {
  const QuizScreen({
    super.key,
    required this.questions,
    required this.issuesById,
    required this.onComplete,
    required this.onExit,
    this.initialAnswers,
    this.initialImportance,
    this.initialDealbreakers,
    this.initialIndex = 0,
    this.showDealbreakers = true,
  });

  final List<Question> questions;
  final Map<String, Issue> issuesById;
  final Future<void> Function(QuizResult result) onComplete;
  final Future<void> Function() onExit;
  final List<int?>? initialAnswers;
  final List<int>? initialImportance;
  final List<String>? initialDealbreakers;
  final int initialIndex;

  /// Settings can hide the dealbreaker flag for a simpler run.
  final bool showDealbreakers;

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  final _store = ResultStore();
  late int _index;
  late List<int?> _answers;
  late List<int> _importance;
  late Set<String> _dealbreakers;
  Future<void> _persistQueue = Future<void>.value();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.questions.length - 1);
    _answers = widget.initialAnswers != null
        ? List<int?>.from(widget.initialAnswers!)
        : List<int?>.filled(widget.questions.length, null);
    _importance = widget.initialImportance != null
        ? List<int>.from(widget.initialImportance!)
        : List<int>.filled(
            widget.questions.length,
            Scoring.defaultImportanceIndex,
          );
    _dealbreakers = {...?widget.initialDealbreakers};
    if (_answers.length != widget.questions.length) {
      _answers = List<int?>.filled(widget.questions.length, null);
      _importance = List<int>.filled(
        widget.questions.length,
        Scoring.defaultImportanceIndex,
      );
      _index = 0;
    }
    if (_importance.length != widget.questions.length) {
      _importance = List<int>.filled(
        widget.questions.length,
        Scoring.defaultImportanceIndex,
      );
    }
  }

  Question get _question => widget.questions[_index];

  Future<void> _persist() {
    final answers = List<int?>.from(_answers);
    final importance = List<int>.from(_importance);
    final dealbreakers = _dealbreakers.toList();
    final index = _index;
    final questionIds = widget.questions.map((q) => q.id).toList();
    _persistQueue = _persistQueue.then(
      (_) => _store.saveProgress(
        answers,
        index,
        questionIds: questionIds,
        importanceIndexes: importance,
        dealbreakerIssueIds: dealbreakers,
      ),
    );
    return _persistQueue;
  }

  Future<void> _select(int likertIndex) async {
    AppFeel.selection();
    setState(() => _answers[_index] = likertIndex);
    await _persist();
  }

  Future<void> _setImportance(int value) async {
    AppFeel.light();
    setState(() => _importance[_index] = value);
    await _persist();
  }

  Future<void> _toggleDealbreaker() async {
    final id = _question.issueId;
    final isOn = _dealbreakers.contains(id);
    if (!isOn && _dealbreakers.length >= Scoring.maxDealbreakers) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'You can mark up to ${Scoring.maxDealbreakers} dealbreakers.',
          ),
        ),
      );
      return;
    }
    AppFeel.medium();
    setState(() {
      if (isOn) {
        _dealbreakers.remove(id);
      } else {
        _dealbreakers.add(id);
      }
    });
    await _persist();
  }

  Future<void> _next() async {
    if (_busy || _answers[_index] == null) return;
    if (_index < widget.questions.length - 1) {
      setState(() => _index++);
      await _persist();
      return;
    }
    setState(() => _busy = true);
    try {
      await _persist();
      await widget.onComplete(
        QuizResult(
          likertIndexes: _answers.cast<int>(),
          importanceIndexes: List<int>.from(_importance),
          dealbreakerIssueIds: _dealbreakers.toList(),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _back() async {
    if (_busy) return;
    if (_index == 0) {
      await _exit();
      return;
    }
    setState(() => _index--);
    await _persist();
  }

  Future<void> _exit() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _persist();
      await widget.onExit();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String? get _issueLabel => widget.issuesById[_question.issueId]?.label;

  void _showContext() {
    final issue = widget.issuesById[_question.issueId];
    final body = issue?.context;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                issue?.label ?? 'Context',
                style: GoogleFonts.manrope(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                body ??
                    'This question is scored on the same liberal–conservative issue scale as the rest of the quiz.',
                style: GoogleFonts.manrope(
                  fontSize: 15,
                  height: 1.45,
                  fontWeight: FontWeight.w500,
                  color: AppColors.inkMuted,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String get _encouragement {
    final progress = (_index + 1) / widget.questions.length;
    if (progress < 0.35) return 'Off to a solid start';
    if (progress < 0.65) return 'Halfway there — keep going';
    if (progress < 1) return 'Almost done';
    return 'Last one';
  }

  @override
  Widget build(BuildContext context) {
    final progress = (_index + 1) / widget.questions.length;
    final selected = _answers[_index];
    final importance = _importance[_index];
    final isDealbreaker = _dealbreakers.contains(_question.issueId);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _busy ? null : _back,
        ),
        title: Text('Question ${_index + 1} of ${widget.questions.length}'),
        actions: [
          TextButton(
            onPressed: _busy ? null : _exit,
            child: const Text('Save & exit'),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                backgroundColor: AppColors.parchment,
                color: AppColors.navy,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _encouragement,
              style: TextStyle(
                color: AppColors.ink.withValues(alpha: 0.55),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (_issueLabel != null) ...[
                              MonoNote(_issueLabel!.toUpperCase(), size: 11),
                              const SizedBox(height: 8),
                            ],
                            Text(
                              _question.text,
                              style: GoogleFonts.manrope(
                                fontWeight: FontWeight.w800,
                                height: 1.3,
                                fontSize: 22,
                                letterSpacing: -0.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'What this means',
                        onPressed: _showContext,
                        icon: const Icon(Icons.help_outline_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  ...List.generate(Scoring.likertLabels.length, (i) {
                    final isSelected = selected == i;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Material(
                        color: isSelected
                            ? AppColors.navy
                            : AppColors.parchment.withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: _busy ? null : () => _select(i),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            child: Text(
                              Scoring.likertLabels[i],
                              style: TextStyle(
                                color: isSelected
                                    ? AppColors.cream
                                    : AppColors.ink,
                                fontWeight: isSelected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 18),
                  SurfaceCard(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                    title: 'How much does this matter to you?',
                    subtitle: Scoring.importanceLabels[importance],
                    child: Column(
                      children: [
                        Slider(
                          value: importance.toDouble(),
                          min: 0,
                          max: 4,
                          divisions: 4,
                          label: Scoring.importanceLabels[importance],
                          activeColor: AppColors.ink,
                          onChanged: _busy
                              ? null
                              : (v) => _setImportance(v.round()),
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const MonoNote('LOW'),
                            const MonoNote('ESSENTIAL'),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (widget.showDealbreakers)
                    Material(
                      color: isDealbreaker
                          ? AppColors.conservative.withValues(alpha: 0.08)
                          : AppColors.sheet,
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: _busy ? null : _toggleDealbreaker,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                isDealbreaker
                                    ? Icons.flag_rounded
                                    : Icons.outlined_flag_rounded,
                                color: isDealbreaker
                                    ? AppColors.conservative
                                    : AppColors.inkMuted,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  isDealbreaker
                                      ? 'Dealbreaker — opposite views will be flagged'
                                      : 'Mark as a dealbreaker (${_dealbreakers.length}/${Scoring.maxDealbreakers})',
                                  style: GoogleFonts.manrope(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: selected == null || _busy ? null : _next,
              child: Text(
                _index == widget.questions.length - 1
                    ? 'See my results'
                    : 'Next',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
