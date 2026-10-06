import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../data/app_data.dart';
import '../models/scoring.dart';
import '../services/app_feel.dart';
import '../services/civic_sync.dart';
import '../services/friend_store.dart';
import '../services/result_store.dart';
import '../services/voteaxis_api.dart';
import '../theme/app_theme.dart';
import '../widgets/ui_kit.dart';
import '../widgets/alignment_venn.dart';
import '../widgets/spectrum_bar.dart';
import 'qr_scan_screen.dart';

class FriendCompareScreen extends StatefulWidget {
  const FriendCompareScreen({
    super.key,
    required this.data,
    this.profile,
    this.initialCode,
  });

  final AppData data;
  final SpectrumProfile? profile;
  final String? initialCode;

  @override
  State<FriendCompareScreen> createState() => _FriendCompareScreenState();
}

class _FriendCompareScreenState extends State<FriendCompareScreen> {
  final _api = VoteaxisApi();
  final _friendStore = FriendStore();
  final _codeController = TextEditingController();

  SpectrumProfile? _mine;
  FriendIdentity? _identity;
  RemoteProfile? _friend;
  String? _error;
  bool _publishing = false;
  bool _lookingUp = false;

  @override
  void initState() {
    super.initState();
    _mine = widget.profile;
    _bootstrap();
  }

  @override
  void dispose() {
    _codeController.dispose();
    _api.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final identity = await _friendStore.load();
    if (_mine == null) {
      final run = await ResultStore().latestRun();
      _mine = run?.toProfile();
    }
    if (!mounted) return;
    setState(() {
      _identity = identity != null && !identity.isExpired ? identity : null;
    });
    final pending = widget.initialCode;
    if (pending != null && pending.isNotEmpty) {
      _codeController.text = pending;
      await _lookup(pending);
    }
  }

  Map<String, String> get _issueLabels => {
    for (final i in widget.data.issues) i.id: i.label,
  };

  Future<void> _publish() async {
    final profile = _mine;
    if (profile == null || _publishing) return;
    setState(() {
      _publishing = true;
      _error = null;
    });
    try {
      final published = await _api.publish(
        profile: profile,
        token: _identity?.token,
      );
      final identity = FriendIdentity(
        code: published.code,
        token: published.token,
        expiresAt: published.expiresAt,
      );
      await _friendStore.save(identity);
      if (!mounted) return;
      setState(() => _identity = identity);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not reach the Voteaxis server.');
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  Future<void> _lookup([String? rawCode]) async {
    final raw = rawCode ?? _codeController.text;
    if (_lookingUp) return;
    setState(() {
      _lookingUp = true;
      _error = null;
    });
    try {
      final code = parseFriendSyncCode(raw);
      if (code == null) {
        if (!mounted) return;
        setState(() => _error = 'That code is not valid.');
        return;
      }
      final friend = await _api.lookup(code);
      if (!mounted) return;
      AppFeel.medium();
      setState(() => _friend = friend);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not reach the Voteaxis server.');
    } finally {
      if (mounted) setState(() => _lookingUp = false);
    }
  }

  Future<void> _scanCode() async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(builder: (_) => const QrScanScreen()),
    );
    if (code == null || !mounted) return;
    _codeController.text = code;
    await _lookup(code);
  }

  Future<void> _shareCode() async {
    final code = _identity?.code;
    if (code == null) return;
    await SharePlus.instance.share(
      ShareParams(
        text:
            'Compare with me on Voteaxis. Code: $code\n'
            '${friendSyncPayload(code)}\n'
            'Open the app → Compare with a friend, or scan the QR.',
      ),
    );
  }

  Future<void> _copyCode() async {
    final code = _identity?.code;
    if (code == null) return;
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Code copied')));
  }

  @override
  Widget build(BuildContext context) {
    final mine = _mine;
    final friend = _friend;
    final comparison = mine != null && friend != null
        ? Scoring.compareProfiles(
            self: mine,
            other: friend.toProfile(),
            issueLabels: _issueLabels,
          )
        : null;

    return Scaffold(
      appBar: AppBar(title: const Text('Compare with a friend')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 36),
        children: [
          Text(
            'Sitting together? Publish a temporary code and show the QR. '
            'They scan or type it. We overlay both dots on the same axis and '
            'draw a Venn of where you align and where you diverge. '
            'The server only holds coordinates — not your answers — and drops them when the code expires.',
            style: GoogleFonts.manrope(height: 1.45, color: AppColors.inkMuted),
          ),
          if (mine == null) ...[
            const SizedBox(height: 20),
            const EmptyState(
              icon: Icons.how_to_reg_outlined,
              title: 'No placement to share yet',
              body:
                  'Take the quiz first — then you can publish a code for a '
                  'friend to scan.',
            ),
          ] else ...[
            const SizedBox(height: 22),
            const SectionHeading('Your code'),
            HeroCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _identity?.code ?? '——————',
                    style: GoogleFonts.ibmPlexMono(
                      fontSize: 32,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 6,
                      color: AppColors.sheet,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _identity == null
                        ? 'Publish this result for 48 hours.'
                        : 'Expires ${_formatExpiry(_identity!.expiresAt)}',
                    style: GoogleFonts.manrope(
                      fontSize: 13,
                      color: AppColors.sheet.withValues(alpha: 0.65),
                    ),
                  ),
                  if (_identity != null) ...[
                    const SizedBox(height: 16),
                    Center(
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.sheet,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: QrImageView(
                          data: friendSyncPayload(_identity!.code),
                          size: 168,
                          backgroundColor: AppColors.sheet,
                          eyeStyle: QrEyeStyle(
                            eyeShape: QrEyeShape.square,
                            color: AppColors.ink,
                          ),
                          dataModuleStyle: QrDataModuleStyle(
                            dataModuleShape: QrDataModuleShape.square,
                            color: AppColors.ink,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Hold this up — they scan from Compare with a friend.',
                      style: GoogleFonts.manrope(
                        fontSize: 12,
                        color: AppColors.sheet.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _publishing ? null : _publish,
                    child: Text(
                      _identity == null
                          ? (_publishing ? 'Publishing…' : 'Publish my code')
                          : (_publishing ? 'Refreshing…' : 'Refresh code'),
                    ),
                  ),
                ),
                if (_identity != null) ...[
                  const SizedBox(width: 8),
                  IconButton.outlined(
                    tooltip: 'Copy',
                    onPressed: _copyCode,
                    icon: const Icon(Icons.copy_rounded),
                  ),
                  IconButton.outlined(
                    tooltip: 'Share',
                    onPressed: _shareCode,
                    icon: const Icon(Icons.ios_share),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 28),
            SectionHeading('Friend’s code'),
            const SizedBox(height: 10),
            TextField(
              controller: _codeController,
              textCapitalization: TextCapitalization.characters,
              maxLength: 8,
              decoration: const InputDecoration(
                hintText: 'A2B3C4',
                counterText: '',
                border: OutlineInputBorder(),
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
              ],
              onSubmitted: (_) => _lookup(),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _lookingUp ? null : () => _lookup(),
                    child: Text(_lookingUp ? 'Looking up…' : 'Plot us'),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _lookingUp ? null : _scanCode,
                  icon: const Icon(Icons.qr_code_scanner_rounded),
                  label: const Text('Scan'),
                ),
              ],
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 14),
            Text(
              _error!,
              style: GoogleFonts.manrope(
                color: AppColors.conservative,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (mine != null && friend != null && comparison != null) ...[
            const SizedBox(height: 28),
            Text(
              '${comparison.closeness}% overlap',
              style: GoogleFonts.manrope(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.6,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              comparison.story,
              style: GoogleFonts.manrope(
                fontSize: 15,
                height: 1.45,
                color: AppColors.inkMuted,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: StatTile(
                    label: 'You',
                    value: Scoring.formatScore(mine.axisScore),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: StatTile(
                    label: friend.label,
                    value: Scoring.formatScore(friend.axisScore),
                    accent: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SectionHeading('Shared axis'),
            const SizedBox(height: 8),
            SpectrumBar(
              userScore: mine.axisScore,
              otherScore: friend.axisScore,
              markers: const [],
              height: 96,
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Text(
                  'You',
                  style: GoogleFonts.manrope(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Text(
                  friend.label,
                  style: GoogleFonts.manrope(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.accent,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            AlignmentVenn(
              venn: Scoring.civicVenn(self: mine, other: friend.toProfile()),
              issueLabels: _issueLabels,
              friendLabel: friend.label,
            ),
            const SizedBox(height: 22),
            SectionHeading('Side by side'),
            const SizedBox(height: 10),
            for (final o in [
              ...comparison.agreements,
              ...comparison.disagreements.where(
                (d) =>
                    !comparison.agreements.any((a) => a.issueId == d.issueId),
              ),
            ])
              _IssueRow(
                label: _issueLabels[o.issueId] ?? o.issueId,
                you: o.userScore,
                them: o.politicianScore,
              ),
          ],
        ],
      ),
    );
  }

  String _formatExpiry(DateTime dt) {
    final local = dt.toLocal();
    return '${local.month}/${local.day} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
}

class _IssueRow extends StatelessWidget {
  const _IssueRow({required this.label, required this.you, required this.them});

  final String label;
  final double you;
  final double them;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: AppColors.sheet,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.ink.withValues(alpha: 0.06)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: GoogleFonts.manrope(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'You  ${Scoring.formatScore(you)}',
                    style: GoogleFonts.manrope(
                      fontSize: 13,
                      color: AppColors.inkMuted,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    'Them  ${Scoring.formatScore(them)}',
                    textAlign: TextAlign.right,
                    style: GoogleFonts.manrope(
                      fontSize: 13,
                      color: AppColors.inkMuted,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
