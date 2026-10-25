import 'package:duo_fold/duo_fold.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';

import '../models/scoring.dart';
import '../services/app_feel.dart';
import '../services/result_envelope.dart';
import '../services/result_store.dart';
import '../services/share_link.dart';
import '../services/transfer_code.dart';
import '../services/voteaxis_api.dart';
import '../theme/app_theme.dart';
import '../widgets/ui_kit.dart';

/// Result of leaving the transfer screen: either a placement to write over
/// this device, or nothing.
class TransferOutcome {
  const TransferOutcome({required this.payload, this.fromLink = false});

  final TransferPayload payload;
  final bool fromLink;
}

/// Move a placement between phones, or hand it to a friend.
///
/// The primary path is a link — `voteaxis.org/result/<id>` — because a QR is
/// useless when the old phone is the only phone you have. Setting a password
/// seals the result on this device before it is uploaded, so the server stores
/// bytes it cannot read. The offline code underneath still works with no
/// network at all.
class TransferScreen extends StatefulWidget {
  const TransferScreen({
    super.key,
    this.payload,
    this.profile,
    this.homeStateCode,
    this.label,
    this.takenAt,
    this.existingLink,
    this.api,
    this.onLinkChanged,
  });

  /// What this device would hand over. Null when nothing is saved yet.
  final TransferPayload? payload;

  /// The same placement in scored form, for the shared page.
  final SpectrumProfile? profile;
  final String? homeStateCode;
  final String? label;
  final DateTime? takenAt;

  /// A link this device published before, so re-sharing reuses the URL.
  final StoredShareLink? existingLink;
  final VoteaxisApi? api;

  /// Called whenever the published link is created, replaced, or revoked.
  final Future<void> Function(StoredShareLink? link)? onLinkChanged;

  @override
  State<TransferScreen> createState() => _TransferScreenState();
}

class _TransferScreenState extends State<TransferScreen> {
  late final VoteaxisApi _api = widget.api ?? VoteaxisApi();
  final _openController = TextEditingController();
  final _passwordController = TextEditingController();
  final _unlockController = TextEditingController();

  StoredShareLink? _link;
  bool _usePassword = false;
  bool _sharing = false;
  bool _opening = false;
  bool _showOfflineCode = false;

  /// A fetched-but-still-sealed result, held while they enter the password.
  SharedResult? _sealed;
  String? _shareError;
  String? _openError;

  String? get _code {
    final payload = widget.payload;
    return payload == null ? null : TransferCode.encode(payload);
  }

  @override
  void initState() {
    super.initState();
    _link = widget.existingLink;
    _usePassword = widget.existingLink?.encrypted ?? false;
    _sniffClipboard();
  }

  @override
  void dispose() {
    _openController.dispose();
    _passwordController.dispose();
    _unlockController.dispose();
    // A no-op when widget.api was injected (tests own that client).
    _api.dispose();
    super.dispose();
  }

  /// If they already copied a link on the other phone, it is waiting in the
  /// field before they type anything.
  Future<void> _sniffClipboard() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text?.trim();
      if (text == null || text.isEmpty) return;
      final usable =
          ShareLink.idFrom(text) != null || TransferCode.looksLikeCode(text);
      if (!usable || text == _link?.url || text == _code) return;
      if (!mounted) return;
      setState(() => _openController.text = text);
    } catch (_) {
      // Clipboard access is best effort.
    }
  }

  Future<void> _createOrUpdateLink() async {
    final profile = widget.profile;
    if (profile == null || _sharing) return;
    final password = _passwordController.text.trim();
    // Guessing happens offline against the ciphertext, so a short password is
    // not a speed bump — it is the whole security of the link.
    if (_usePassword && password.length < ResultEnvelope.minPasswordLength) {
      setState(
        () => _shareError =
            'Use at least ${ResultEnvelope.minPasswordLength} characters — '
            'the link is only as strong as this.',
      );
      return;
    }
    setState(() {
      _sharing = true;
      _shareError = null;
    });
    try {
      final published = await _api.shareResult(
        profile: profile,
        token: _link?.token,
        password: _usePassword ? password : null,
        transferCode: _code,
        homeState: widget.homeStateCode,
        label: widget.label,
        takenAt: widget.takenAt,
      );
      final stored = StoredShareLink(
        id: published.id,
        token: published.token,
        url: published.url,
        encrypted: published.encrypted,
        expiresAt: published.expiresAt,
      );
      await widget.onLinkChanged?.call(stored);
      AppFeel.medium();
      if (!mounted) return;
      setState(() {
        _link = stored;
        _passwordController.clear();
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _shareError = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _shareError = 'Could not reach Voteaxis. Check your connection.',
      );
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  Future<void> _revokeLink() async {
    final link = _link;
    if (link == null || _sharing) return;
    final confirmed = await showFoldAwareDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Take the link down?'),
        content: const Text(
          'Anyone holding it stops being able to open your result. Your '
          'placement stays on this phone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep it'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.conservative,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Take it down'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() {
      _sharing = true;
      _shareError = null;
    });
    try {
      await _api.revokeResult(link.id, link.token);
      await widget.onLinkChanged?.call(null);
      if (!mounted) return;
      setState(() {
        _link = null;
        _usePassword = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _shareError = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _shareError = 'Could not reach Voteaxis.');
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  Future<void> _copyLink() async {
    final link = _link;
    if (link == null) return;
    await Clipboard.setData(ClipboardData(text: link.url));
    AppFeel.light();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Link copied')));
  }

  Future<void> _sendLink() async {
    final link = _link;
    if (link == null) return;
    await SharePlus.instance.share(
      ShareParams(
        text: link.encrypted
            ? 'Where I landed on Voteaxis: ${link.url}\n'
                  '(I will send you the password separately.)'
            : 'Where I landed on Voteaxis: ${link.url}',
      ),
    );
  }

  Future<void> _copyOfflineCode() async {
    final code = _code;
    if (code == null) return;
    await Clipboard.setData(ClipboardData(text: code));
    AppFeel.light();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Offline code copied')));
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text == null || text.isEmpty || !mounted) return;
    setState(() {
      _openController.text = text;
      _openError = null;
      _sealed = null;
    });
  }

  /// One button for every shape of input: a URL, a bare id, or an offline code.
  Future<void> _open() async {
    if (_opening) return;

    // Already fetched and waiting on a password: decrypt without going back
    // to the network. Nothing about the attempt leaves this device.
    final sealed = _sealed;
    if (sealed != null) {
      final password = _unlockController.text.trim();
      if (password.isEmpty) {
        setState(() => _openError = 'Enter the password for this link.');
        return;
      }
      setState(() {
        _opening = true;
        _openError = null;
      });
      final opened = await VoteaxisApi.openResult(sealed, password);
      if (!mounted) return;
      setState(() => _opening = false);
      if (opened == null) {
        AppFeel.light();
        setState(() => _openError = 'That password is not right.');
        return;
      }
      _finish(opened);
      return;
    }

    final raw = _openController.text.trim();
    if (raw.isEmpty) {
      setState(() => _openError = 'Paste a link or a code first.');
      return;
    }

    final offline = TransferCode.decode(raw);
    if (offline != null) {
      AppFeel.medium();
      Navigator.of(context).pop(TransferOutcome(payload: offline));
      return;
    }

    final id = ShareLink.idFrom(raw);
    if (id == null) {
      setState(() {
        _openError = TransferCode.looksLikeCode(raw)
            ? "That code isn't complete. Copy the whole thing, including the "
                  'VX1 at the front.'
            : "That doesn't look like a Voteaxis link or code.";
      });
      return;
    }

    setState(() {
      _opening = true;
      _openError = null;
    });
    try {
      final result = await _api.fetchResult(id);
      if (!mounted) return;
      if (result.encrypted) {
        if (result.envelope == null) {
          setState(
            () => _openError = 'That link needs a newer version of the app.',
          );
          return;
        }
        setState(() {
          _sealed = result;
          _openError = 'This one is password protected.';
        });
        return;
      }
      _finish(result);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _openError = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _openError = 'Could not reach Voteaxis. Check your connection.',
      );
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  void _finish(SharedResult result) {
    final payload = _payloadFrom(result);
    if (payload == null) {
      setState(() => _openError = 'That link has no placement on it.');
      return;
    }
    AppFeel.medium();
    Navigator.of(
      context,
    ).pop(TransferOutcome(payload: payload, fromLink: true));
  }

  /// The offline code rides along on every shared result, so a restore keeps
  /// settings and dealbreakers exactly. Scores alone are the fallback.
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

  @override
  Widget build(BuildContext context) {
    final link = _link;
    final canShare = widget.profile != null;

    return Scaffold(
      appBar: AppBar(title: const Text('Share & transfer')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          Text(
            'One link moves your placement to a new phone and shows a friend '
            'where you landed. Add a password and it is encrypted on this '
            'phone first — not even we can read it.',
            style: GoogleFonts.manrope(
              fontSize: 14,
              height: 1.45,
              color: AppColors.inkMuted,
            ),
          ),
          const SizedBox(height: 24),
          const SectionHeading('YOUR LINK'),
          const SizedBox(height: 12),
          if (!canShare)
            const SurfaceCard(
              child: Text('Take the quiz or set your level first.'),
            )
          else if (link == null)
            SurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      'Protect with a password',
                      style: GoogleFonts.manrope(fontWeight: FontWeight.w800),
                    ),
                    subtitle: Text(
                      'Without one, anyone holding the link can open it.',
                      style: GoogleFonts.manrope(
                        fontSize: 12,
                        color: AppColors.inkMuted,
                      ),
                    ),
                    value: _usePassword,
                    onChanged: _sharing
                        ? null
                        : (value) => setState(() => _usePassword = value),
                  ),
                  if (_usePassword) ...[
                    const SizedBox(height: 4),
                    TextField(
                      controller: _passwordController,
                      obscureText: true,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        helperText:
                            'At least ${ResultEnvelope.minPasswordLength} '
                            'characters. We cannot recover it — nothing on our '
                            'side can read the link without it.',
                        helperMaxLines: 3,
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (_shareError != null) ...[
                    _ErrorText(_shareError!),
                    const SizedBox(height: 10),
                  ],
                  FilledButton.icon(
                    onPressed: _sharing ? null : _createOrUpdateLink,
                    icon: _sharing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.link_rounded, size: 18),
                    label: Text(_sharing ? 'Creating…' : 'Create my link'),
                  ),
                ],
              ),
            )
          else
            SurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SelectableText(
                    link.url,
                    style: GoogleFonts.ibmPlexMono(
                      fontSize: 13,
                      height: 1.5,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    link.encrypted
                        ? 'Encrypted · expires ${_formatDate(link.expiresAt)}'
                        : 'Anyone with the link · expires ${_formatDate(link.expiresAt)}',
                    style: GoogleFonts.manrope(
                      fontSize: 12,
                      color: AppColors.inkMuted,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _copyLink,
                          icon: const Icon(Icons.copy_rounded, size: 18),
                          label: const Text('Copy'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _sendLink,
                          icon: const Icon(Icons.ios_share_rounded, size: 18),
                          label: const Text('Send'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (_shareError != null) ...[
                    _ErrorText(_shareError!),
                    const SizedBox(height: 10),
                  ],
                  TextButton(
                    onPressed: _sharing ? null : _createOrUpdateLink,
                    child: const Text('Update with my latest result'),
                  ),
                  TextButton(
                    onPressed: _sharing ? null : _revokeLink,
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.conservative,
                    ),
                    child: const Text('Take the link down'),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 32),
          const SectionHeading('OPEN A LINK'),
          const SizedBox(height: 12),
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _openController,
                  minLines: 2,
                  maxLines: 4,
                  autocorrect: false,
                  enableSuggestions: false,
                  style: GoogleFonts.ibmPlexMono(fontSize: 12, height: 1.5),
                  decoration: InputDecoration(
                    labelText: 'Paste a link or code',
                    hintText: 'voteaxis.org/result/…',
                    errorText: _openError,
                    errorMaxLines: 3,
                    suffixIcon: IconButton(
                      tooltip: 'Paste',
                      icon: const Icon(Icons.content_paste_rounded, size: 18),
                      onPressed: _paste,
                    ),
                  ),
                  onChanged: (_) {
                    if (_openError != null) setState(() => _openError = null);
                  },
                ),
                if (_sealed != null) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _unlockController,
                    obscureText: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: const InputDecoration(
                      labelText: 'Password for this link',
                    ),
                    onSubmitted: (_) => _open(),
                  ),
                ],
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _opening ? null : _open,
                  child: Text(_opening ? 'Opening…' : 'Open and restore'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Restoring replaces the placement and settings on this phone.',
            style: GoogleFonts.manrope(
              fontSize: 12,
              height: 1.4,
              color: AppColors.inkMuted,
            ),
          ),

          if (_code != null) ...[
            const SizedBox(height: 24),
            TextButton(
              onPressed: () =>
                  setState(() => _showOfflineCode = !_showOfflineCode),
              child: Text(
                _showOfflineCode ? 'Hide offline code' : 'No internet?',
              ),
            ),
            if (_showOfflineCode)
              SurfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'This code carries the same placement with nothing sent '
                      'anywhere. Paste it into the box above on the other '
                      'phone.',
                      style: GoogleFonts.manrope(
                        fontSize: 12,
                        height: 1.45,
                        color: AppColors.inkMuted,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SelectableText(
                      _code!,
                      style: GoogleFonts.ibmPlexMono(
                        fontSize: 11,
                        height: 1.6,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _copyOfflineCode,
                      icon: const Icon(Icons.copy_rounded, size: 18),
                      label: const Text('Copy offline code'),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  static String _formatDate(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final local = date.toLocal();
    return '${months[local.month - 1]} ${local.day}, ${local.year}';
  }
}

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Text(
      message,
      style: GoogleFonts.manrope(
        fontSize: 12,
        height: 1.4,
        fontWeight: FontWeight.w600,
        color: AppColors.conservative,
      ),
    );
  }
}
