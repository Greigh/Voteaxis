import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../data/us_states.dart';
import '../theme/app_theme.dart';
import '../widgets/mist_backdrop.dart';
import '../widgets/voteaxis_logo.dart';

/// First-run welcome — brand story + home state.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({
    super.key,
    required this.onContinue,
    this.initialStateCode,
  });

  final Future<void> Function(String stateCode) onContinue;
  final String? initialStateCode;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _enter;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;
  String? _stateCode;

  @override
  void initState() {
    super.initState();
    _stateCode = widget.initialStateCode;
    _enter = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    );
    _fade = CurvedAnimation(parent: _enter, curve: Curves.easeOutCubic);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _enter, curve: Curves.easeOutCubic));
    _enter.forward();
  }

  @override
  void dispose() {
    _enter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canContinue = _stateCode != null;

    return Scaffold(
      backgroundColor: AppColors.ink,
      body: FadeTransition(
        opacity: _fade,
        child: SlideTransition(
          position: _slide,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 9,
                child: MistBackdrop(
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(28, 36, 28, 20),
                      child: Column(
                        children: [
                          const Spacer(flex: 2),
                          const VoteaxisMark(size: 96),
                          const SizedBox(height: 20),
                          const VoteaxisWordmark(fontSize: 40),
                          const SizedBox(height: 12),
                          Text(
                            'Welcome',
                            style: GoogleFonts.ibmPlexMono(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1.6,
                              color: AppColors.inkMuted,
                            ),
                          ),
                          const Spacer(flex: 3),
                          const SpectrumHeroRail(height: 52, markerScore: -28),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Liberal',
                                style: GoogleFonts.manrope(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.liberal,
                                ),
                              ),
                              Text(
                                'Conservative',
                                style: GoogleFonts.manrope(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.conservative,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                flex: 11,
                child: Container(
                  color: AppColors.ink,
                  child: SafeArea(
                    top: false,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(28, 28, 28, 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Where do you vote?',
                            style: GoogleFonts.manrope(
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.7,
                              height: 1.15,
                              color: AppColors.sheet,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'We’ll prioritize candidates from your state when we rank matches. You can change this later.',
                            style: GoogleFonts.manrope(
                              fontSize: 15,
                              height: 1.5,
                              fontWeight: FontWeight.w500,
                              color: AppColors.sheet.withValues(alpha: 0.72),
                            ),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            'Your state',
                            style: GoogleFonts.ibmPlexMono(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1.1,
                              color: AppColors.sheet.withValues(alpha: 0.45),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            decoration: BoxDecoration(
                              color: AppColors.sheet.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: AppColors.sheet.withValues(alpha: 0.16),
                              ),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                isExpanded: true,
                                value: _stateCode,
                                dropdownColor: AppColors.ink,
                                hint: Text(
                                  'Select your state',
                                  style: GoogleFonts.manrope(
                                    color: AppColors.sheet.withValues(
                                      alpha: 0.5,
                                    ),
                                  ),
                                ),
                                iconEnabledColor: AppColors.sheet,
                                style: GoogleFonts.manrope(
                                  color: AppColors.sheet,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 16,
                                ),
                                items: [
                                  for (final s in UsStates.all)
                                    DropdownMenuItem(
                                      value: s.code,
                                      child: Text('${s.name} (${s.code})'),
                                    ),
                                ],
                                onChanged: (value) =>
                                    setState(() => _stateCode = value),
                              ),
                            ),
                          ),
                          const SizedBox(height: 22),
                          const _StepLine(
                            index: '01',
                            title: 'Answer',
                            detail: 'Likert questions on real issues',
                          ),
                          const SizedBox(height: 12),
                          const _StepLine(
                            index: '02',
                            title: 'Land',
                            detail: 'One liberal ↔ conservative placement',
                          ),
                          const SizedBox(height: 12),
                          const _StepLine(
                            index: '03',
                            title: 'Match',
                            detail:
                                'See who on your ballot overlaps your views',
                          ),
                          const SizedBox(height: 28),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: !canContinue
                                  ? null
                                  : () => widget.onContinue(_stateCode!),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.sheet,
                                foregroundColor: AppColors.ink,
                                disabledBackgroundColor: AppColors.sheet
                                    .withValues(alpha: 0.25),
                                disabledForegroundColor: AppColors.sheet
                                    .withValues(alpha: 0.5),
                              ),
                              child: const Text('Get started'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StepLine extends StatelessWidget {
  const _StepLine({
    required this.index,
    required this.title,
    required this.detail,
  });

  final String index;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 36,
          child: Text(
            index,
            style: GoogleFonts.ibmPlexMono(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.sheet.withValues(alpha: 0.4),
            ),
          ),
        ),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: GoogleFonts.manrope(
                fontSize: 14,
                height: 1.35,
                color: AppColors.sheet.withValues(alpha: 0.7),
              ),
              children: [
                TextSpan(
                  text: '$title  ',
                  style: GoogleFonts.manrope(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.sheet,
                  ),
                ),
                TextSpan(text: detail),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
