import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../data/app_data.dart';
import '../models/scoring.dart';
import '../services/result_envelope.dart';
import '../services/result_store.dart';
import '../services/transfer_code.dart';
import '../services/voteaxis_api.dart';
import '../theme/app_theme.dart';
import '../widgets/alignment_venn.dart';
import '../widgets/pillar_bars.dart';
import '../widgets/spectrum_bar.dart';
import '../widgets/ui_kit.dart';
import 'transfer_screen.dart';

/// Opens a `voteaxis.org/result/<id>` link inside the app.
///
/// This is deliberately a *viewer*, not a silent restore: a friend tapping the
/// link wants to see where someone landed and how it compares — writing over
/// their own placement is an explicit second step. For a sealed link the
/// password prompt happens here too; decryption stays on-device exactly like
/// the transfer screen's path.
class SharedResultScreen extends StatefulWidget {
  const SharedResultScreen({
    super.key,
    required this.resultId,
    required this.data,
    this.userProfile,
    this.api,
  });

  final String resultId;
  final AppData data;

  /// The viewer's own placement, when this device has one — powers the
  /// side-by-side bar and the overlap Venn.
  final SpectrumProfile? userProfile;

  final VoteaxisApi? api;

  @override
  State<SharedResultScreen> createState() => _SharedResultScreenState();
}

class _SharedResultScreenState extends State<SharedResultScreen> {
  late final VoteaxisApi _api = widget.api ?? VoteaxisApi();
  final _passwordController = TextEditingController();

  SharedResult? _result;
  SharedResult? _sealed;
  String? _error;
  bool _busy = false;

  String get _theirLabel =>
      _result == null || _result!.label.isEmpty ? 'Them' : _result!.label;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _api.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await _api.fetchResult(widget.resultId);
      if (!mounted) return;
      setState(() {
        if (result.encrypted) {
          _sealed = result.envelope == null ? null : result;
          _error = result.envelope == null
              ? 'That link needs a newer version of the app.'
              : null;
        } else {
          _result = result;
        }
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _error = 'Could not reach Voteaxis. Check your connection.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Decrypts the sealed result locally. A wrong password costs a keystretch,
  /// not a request.
  Future<void> _unlock() async {
    final sealed = _sealed;
    final password = _passwordController.text.trim();
    if (sealed == null || _busy) return;
    if (password.isEmpty) {
      setState(() => _error = 'Enter the password for this link.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final opened = await VoteaxisApi.openResult(sealed, password);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (opened == null) {
        _error = 'That password is not right.';
      } else {
        _result = opened;
        _sealed = null;
      }
    });
  }

  /// The offline transfer code rides on every shared result and restores
  /// settings + dealbreakers exactly; raw issue scores are the fallback.
  TransferPayload? _payloadFrom(SharedResult result) {
    final code = result.transferCode;
    if (code != null && code.isNotEmpty) {
      final decoded = TransferCode.decode(code);
      if (decoded != null) return decoded;
    }
    if (result.issueScores.isEmpty) return null;
    return TransferPayload(
      issueScores: result.issueScores,
      issueWeights: result.issueWeights,
      dealbreakerIssueIds: result.dealbreakerIssueIds,
      homeStateCode: result.homeState,
      handSet: result.label == QuizRun.handSetLabel,
    );
  }

  Future<void> _restoreAsMine() async {
    final result = _result;
    if (result == null) return;
    final payload = _payloadFrom(result);
    if (payload == null) {
      setState(() => _error = 'That link has no placement on it.');
      return;
    }
    final replace = widget.userProfile != null;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Use this as your placement?'),
        content: Text(
          replace
              ? 'This replaces the placement saved on this phone. You can '
                    'retake the quiz any time.'
              : 'This becomes the placement saved on this phone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Use it'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    Navigator.of(
      context,
    ).pop(TransferOutcome(payload: payload, fromLink: true));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Shared result')),
      body: _body(),
    );
  }

  Widget _body() {
    if (_busy && _result == null && _sealed == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_sealed != null) return _passwordPrompt();
    final result = _result;
    if (result == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _error ?? 'Could not open that link.',
                textAlign: TextAlign.center,
                style: GoogleFonts.manrope(
                  fontSize: 15,
                  height: 1.4,
                  color: AppColors.inkMuted,
                ),
              ),
              const SizedBox(height: 16),
              OutlinedButton(onPressed: _load, child: const Text('Try again')),
            ],
          ),
        ),
      );
    }
    return _resultView(result);
  }

  Widget _passwordPrompt() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
      children: [
        Text(
          'This result is sealed. The password never leaves this phone — '
          'decryption happens here.',
          style: GoogleFonts.manrope(
            fontSize: 14,
            height: 1.45,
            color: AppColors.inkMuted,
          ),
        ),
        const SizedBox(height: 18),
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _passwordController,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: 'Password for this link',
                  helperText:
                      'At least ${ResultEnvelope.minPasswordLength} characters.',
                  errorText: _error,
                  errorMaxLines: 3,
                ),
                onSubmitted: (_) => _unlock(),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _busy ? null : _unlock,
                child: Text(_busy ? 'Opening…' : 'Open'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _resultView(SharedResult result) {
    final mine = widget.userProfile;
    final theirProfile = result.issueScores.isEmpty
        ? null
        : Scoring.profileFromIssueScores(
            issueScores: result.issueScores,
            issues: widget.data.issues,
            issueWeights: result.issueWeights,
            dealbreakerIssueIds: result.dealbreakerIssueIds,
          );

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
      children: [
        Text(
          mine == null
              ? 'Someone shared where they landed on Voteaxis.'
              : 'Someone shared where they landed — here it is next to yours.',
          style: GoogleFonts.manrope(
            fontSize: 14,
            height: 1.45,
            color: AppColors.inkMuted,
          ),
        ),
        const SizedBox(height: 18),
        const SectionHeading('THEIR PLACEMENT'),
        const SizedBox(height: 12),
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                Scoring.labelForScore(result.axisScore),
                style: GoogleFonts.manrope(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                [
                  Scoring.formatScore(result.axisScore),
                  if (result.label.isNotEmpty) result.label,
                  if ((result.homeState ?? '').isNotEmpty) result.homeState!,
                ].join(' · '),
                style: GoogleFonts.manrope(
                  fontSize: 12,
                  color: AppColors.inkMuted,
                ),
              ),
              const SizedBox(height: 16),
              SpectrumBar(
                userScore: mine?.axisScore,
                otherScore: result.axisScore,
                markers: const [],
                height: 96,
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  if (mine != null)
                    Text(
                      'You',
                      style: GoogleFonts.manrope(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  const Spacer(),
                  Text(
                    _theirLabel,
                    style: GoogleFonts.manrope(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.accent,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        if (result.pillarScores.isNotEmpty) ...[
          const SizedBox(height: 24),
          const SectionHeading('THEIR PILLARS'),
          const SizedBox(height: 12),
          PillarBars(
            pillarScores: result.pillarScores,
            pillarLabels: {for (final p in widget.data.pillars) p.id: p.label},
            title: 'Pillars',
          ),
        ],

        if (mine != null && theirProfile != null) ...[
          const SizedBox(height: 24),
          AlignmentVenn(
            venn: Scoring.civicVenn(self: mine, other: theirProfile),
            issueLabels: {for (final i in widget.data.issues) i.id: i.label},
            friendLabel: _theirLabel,
          ),
        ],

        const SizedBox(height: 28),
        FilledButton(
          onPressed: _restoreAsMine,
          child: Text(
            mine == null ? 'Use as my placement' : 'Replace mine with this',
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: Text(
            'Viewing changes nothing — restoring is your call.',
            style: GoogleFonts.manrope(fontSize: 12, color: AppColors.inkMuted),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Center(
            child: Text(
              _error!,
              textAlign: TextAlign.center,
              style: GoogleFonts.manrope(
                fontSize: 13,
                color: AppColors.conservative,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
