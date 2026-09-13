import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/contribute_links.dart';
import '../theme/app_theme.dart';
import '../widgets/ui_kit.dart';

class ContributeScreen extends StatefulWidget {
  const ContributeScreen({super.key, this.locale, this.onLaunch});

  /// Test seam. Production uses the platform locale.
  final Locale? locale;

  /// Test seam. Production opens voteaxis.org/contribute in the browser.
  final Future<bool> Function(Uri uri)? onLaunch;

  @override
  State<ContributeScreen> createState() => _ContributeScreenState();
}

class _ContributeScreenState extends State<ContributeScreen> {
  String? _error;
  bool _opening = false;

  bool get _canLinkOut =>
      ContributeLinks.canLinkOutToWebCheckout(widget.locale);

  Future<void> _openWeb() async {
    setState(() {
      _opening = true;
      _error = null;
    });
    final ok = await ContributeLinks.openContributePage(
      launch: widget.onLaunch,
    );
    if (!mounted) return;
    setState(() {
      _opening = false;
      if (!ok) {
        _error =
            'Could not open the contribute page. Try voteaxis.org/contribute in a browser.';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Contribute to Voteaxis')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Text(
            'Fund the instrument, not a paywall',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: AppColors.navy,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'The quiz, your axis, and your state’s ballot stay free. A contribution covers hosting and state-level data. It does not unlock fairness, and it never will.',
            style: GoogleFonts.manrope(
              fontSize: 15,
              height: 1.45,
              fontWeight: FontWeight.w500,
              color: AppColors.inkMuted,
            ),
          ),
          const SizedBox(height: 24),
          const SectionHeading('What a contribution is'),
          const InfoRow(
            icon: Icons.lock_open_rounded,
            title: 'Nothing unlocks',
            body:
                'Active Ballot, friend compare, and dealbreakers are part of '
                'the civic loop. A contribution does not buy a closer match.',
          ),
          const SizedBox(height: 10),
          const InfoRow(
            icon: Icons.receipt_long_outlined,
            title: 'What it covers',
            body:
                'Hosting, store fees, and keeping candidate data current. No '
                'ads, no sponsored results.',
          ),
          const SizedBox(height: 28),
          if (_canLinkOut) ...[
            FilledButton(
              onPressed: _opening ? null : _openWeb,
              child: Text(_opening ? 'Opening…' : 'Continue on the web'),
            ),
            const SizedBox(height: 10),
            Text(
              r'Opens voteaxis.org/contribute. Stripe handles the card. $5, $15, $30, or $25/year Sustainer.',
              style: GoogleFonts.manrope(
                fontSize: 13,
                height: 1.4,
                color: AppColors.inkMuted,
              ),
            ),
          ] else ...[
            Text(
              'In-app tipping for this storefront is not available yet. You can contribute to Voteaxis from a browser at:',
              style: GoogleFonts.manrope(
                fontSize: 15,
                height: 1.45,
                fontWeight: FontWeight.w500,
                color: AppColors.inkMuted,
              ),
            ),
            const SizedBox(height: 10),
            SelectableText(
              ContributeLinks.pageUri.host + ContributeLinks.pageUri.path,
              style: GoogleFonts.ibmPlexMono(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.ink,
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: GoogleFonts.manrope(
                fontSize: 13,
                height: 1.4,
                fontWeight: FontWeight.w600,
                color: AppColors.conservative,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
