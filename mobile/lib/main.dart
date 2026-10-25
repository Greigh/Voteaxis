import 'dart:async';
import 'dart:math' as math;

import 'package:duo_fold/duo_fold.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'data/app_data.dart';
import 'duo/duo_scope.dart';
import 'models/app_settings.dart';
import 'models/issue_of_the_day.dart';
import 'models/politician.dart';
import 'models/question.dart';
import 'models/quiz_bank.dart';
import 'models/scoring.dart';
import 'screens/explore_screen.dart';
import 'screens/friend_compare_screen.dart';
import 'screens/home_screen.dart';
import 'screens/manual_profile_screen.dart';
import 'screens/methodology_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/quiz_screen.dart';
import 'screens/results_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/shared_result_screen.dart';
import 'screens/duo_glance_screen.dart';
import 'screens/transfer_screen.dart';
import 'services/app_feel.dart';
import 'services/civic_sync.dart';
import 'services/issue_reminder.dart';
import 'services/result_store.dart';
import 'services/transfer_code.dart';
import 'services/voteaxis_api.dart';
import 'services/widget_bridge.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Every font face the app uses is bundled under assets/fonts/. Blocking
  // runtime fetches keeps "your answers never leave this phone" honest — no
  // text render ever phones fonts.gstatic.com. If a bundled face is missing
  // the call fails loudly in debug builds and falls back to the system face.
  GoogleFonts.config.allowRuntimeFetching = false;
  SystemChrome.setSystemUIOverlayStyle(_overlayStyleFor(Brightness.light));
  await initIssueWidget();
  // ProviderScope carries the iPhone Duo fold stream and its settings
  // toggles. The rest of the app stays setState-based; fold-aware widgets
  // read it through duo_scope.dart and degrade to single-pane without it.
  runApp(const ProviderScope(child: VoteaxisApp()));
}

SystemUiOverlayStyle _overlayStyleFor(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  return SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
    statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarIconBrightness: isDark
        ? Brightness.light
        : Brightness.dark,
    systemNavigationBarDividerColor: Colors.transparent,
  );
}

class VoteaxisApp extends StatelessWidget {
  const VoteaxisApp({super.key});

  @override
  Widget build(BuildContext context) {
    // AppShell builds the MaterialApp itself — theme mode is a user setting
    // that lives in shell state, and the shell also owns the navigator so
    // deep links can push screens after bootstrap.
    return const AppShell();
  }
}

/// Android 15+ draws edge-to-edge. MediaQuery.padding can be 0 even though
/// the status bar still covers the top of the screen. Rebuild padding from
/// the FlutterView insets so SafeArea actually clears the system bars.
class _RestoreSystemInsets extends StatelessWidget {
  const _RestoreSystemInsets({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final view = View.maybeOf(context);
    final dpr = view?.devicePixelRatio ?? 1;
    final rawTop = view == null
        ? 0.0
        : math.max(view.padding.top, view.viewPadding.top) / dpr;
    final rawBottom = view == null
        ? 0.0
        : math.max(view.padding.bottom, view.viewPadding.bottom) / dpr;
    final top = math.max(
      math.max(media.padding.top, media.viewPadding.top),
      rawTop,
    );
    final bottom = math.max(
      math.max(media.padding.bottom, media.viewPadding.bottom),
      rawBottom,
    );
    if (top == media.padding.top && bottom == media.padding.bottom) {
      return child;
    }
    return MediaQuery(
      data: media.copyWith(
        padding: media.padding.copyWith(top: top, bottom: bottom),
        viewPadding: media.viewPadding.copyWith(top: top, bottom: bottom),
      ),
      child: child,
    );
  }
}

enum _View { loading, onboarding, home, quiz, results }

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  final _store = ResultStore();
  final _navKey = GlobalKey<NavigatorState>();
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();
  _View _view = _View.loading;
  AppData? _data;
  SpectrumProfile? _profile;

  /// The showing profile was hand-set on the level screen, not scored from a
  /// quiz run. Results says so at the top.
  bool _handSet = false;
  Object? _error;
  bool _hasInProgress = false;
  List<int?>? _resumeAnswers;
  List<int>? _resumeImportance;
  List<String> _resumeDealbreakers = const [];
  int _resumeIndex = 0;
  bool _resuming = false;
  List<Question> _quizQuestions = const [];
  String? _homeState;
  int? _homeDistrict;
  AppSettings _settings = const AppSettings();
  IssueOfTheWeek? _week;
  String? _pendingSyncCode;
  String? _pendingRestoreCode;
  String? _pendingResultId;
  StreamSubscription<Uri>? _syncLinks;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _syncLinks = listenDeepLinks(
      onSyncCode: _onSyncCode,
      onRestoreCode: _onRestoreCode,
      onResultLink: _onResultLink,
    );
    _bootstrap();
  }

  @override
  void dispose() {
    _syncLinks?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _onSyncCode(String code) {
    if (!mounted) return;
    if (_data == null || _view == _View.loading || _view == _View.onboarding) {
      _pendingSyncCode = code;
      return;
    }
    _openFriendCompare(code);
  }

  void _onRestoreCode(String raw) {
    if (!mounted) return;
    if (_data == null || _view == _View.loading) {
      _pendingRestoreCode = raw;
      return;
    }
    final payload = TransferCode.decode(raw);
    if (payload == null) return;
    _applyTransfer(payload);
  }

  /// A universal `voteaxis.org/result/<id>` link (or the voteaxis://result
  /// form) opens the viewer — it never restores over this device's placement
  /// without an explicit confirm inside the screen.
  void _onResultLink(String id) {
    if (!mounted) return;
    if (_data == null || _view == _View.loading) {
      _pendingResultId = id;
      return;
    }
    _openSharedResult(id);
  }

  Future<void> _openSharedResult(String id) async {
    final data = _data;
    final nav = _navKey.currentState;
    if (data == null || nav == null) return;
    final outcome = await nav.push<TransferOutcome>(
      foldAwareRoute<TransferOutcome>(
        nav.context,
        builder: (_) =>
            SharedResultScreen(resultId: id, data: data, userProfile: _profile),
      ),
    );
    if (outcome == null || !mounted) return;
    await _applyTransfer(outcome.payload);
  }

  void _openFriendCompare([String? code]) {
    final data = _data;
    final nav = _navKey.currentState;
    if (data == null || nav == null) return;
    nav.push(
      foldAwareRoute<void>(
        nav.context,
        builder: (_) => FriendCompareScreen(
          data: data,
          profile: _profile,
          initialCode: code,
        ),
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _reloadProfileFromStore();
    }
  }

  Future<void> _syncWidget() async {
    final data = _data;
    if (data == null || !_settings.issueWidget) return;
    await syncIssueWidget(
      questions: data.questions,
      week: _week,
      hasProfile: _profile != null,
      axisLabel: _profile == null
          ? null
          : Scoring.formatScore(_profile!.axisScore),
    );
  }

  Future<void> _reloadProfileFromStore() async {
    final latest = await _store.latestRun();
    if (!mounted) return;
    setState(() {
      _profile = latest?.toProfile();
      _handSet = latest?.isHandSet ?? false;
    });
    await _syncWidget();
  }

  List<Question> _orderedQuestions(List<String> questionIds) {
    final byId = {for (final q in _data!.questions) q.id: q};
    final ordered = <Question>[];
    for (final id in questionIds) {
      final q = byId[id];
      if (q != null) ordered.add(q);
    }
    return ordered;
  }

  Future<void> _bootstrap() async {
    try {
      final data = await AppData.load();
      final onboarded = await _store.hasOnboarded();
      final homeState = await _store.loadHomeState();
      final homeDistrict = await _store.loadHomeDistrict();
      final settings = await _store.loadSettings();
      AppFeel.apply(settings);
      IssueOfTheWeek? week;
      final api = VoteaxisApi();
      try {
        week = await api.week();
      } catch (_) {
        week = null;
      } finally {
        api.dispose();
      }
      final latest = await _store.latestRun();
      final progress = await _store.loadProgress();
      // Keep the pending reminder's copy in step with the live issue. This is
      // a no-op unless the user enabled the daily nudge — nothing is scheduled
      // just because the app launched.
      unawaited(IssueReminder.refreshContent(week));
      if (!mounted) return;
      setState(() {
        _data = data;
        _homeState = homeState;
        _homeDistrict = homeDistrict;
        _settings = settings;
        _week = week;
        _profile = latest?.toProfile();
        _handSet = latest?.isHandSet ?? false;
        _hasInProgress = progress != null;
        if (progress != null) {
          _resumeAnswers = progress.answers;
          _resumeIndex = progress.index;
          _resumeImportance = progress.importanceIndexes;
          _resumeDealbreakers = progress.dealbreakerIssueIds;
          if (progress.questionIds.isNotEmpty) {
            final byId = {for (final q in data.questions) q.id: q};
            final ordered = <Question>[];
            for (final id in progress.questionIds) {
              final q = byId[id];
              if (q != null) ordered.add(q);
            }
            if (ordered.length == progress.answers.length) {
              _quizQuestions = ordered;
            } else {
              _hasInProgress = false;
              _resumeAnswers = null;
              _resumeIndex = 0;
              _resumeImportance = null;
              _resumeDealbreakers = const [];
            }
          }
        }
        // Need a home state before the hub — even for returning users.
        _view = (!onboarded || homeState == null)
            ? _View.onboarding
            : _View.home;
      });
      await _syncWidget();
      // Best-effort and non-blocking: bootstrap already has a full roster
      // from the bundled asset (or a prior refresh's cache), so this can
      // finish whenever the network gets around to it. A quiz taken before
      // it resolves scores against whatever politicians are already loaded.
      unawaited(_refreshPoliticiansInBackground());
      final pendingRestore = _pendingRestoreCode;
      if (pendingRestore != null && mounted) {
        _pendingRestoreCode = null;
        final payload = TransferCode.decode(pendingRestore);
        if (payload != null) await _applyTransfer(payload);
      }
      final pending = _pendingSyncCode;
      if (pending != null && _view == _View.home && mounted) {
        _pendingSyncCode = null;
        _openFriendCompare(pending);
      }
      final pendingResult = _pendingResultId;
      if (pendingResult != null && mounted) {
        _pendingResultId = null;
        await _openSharedResult(pendingResult);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _view = _View.home;
      });
    }
  }

  /// Refreshes the roster from `/v1/politicians` and, on an actual change,
  /// swaps it into [_data] for this session. See
  /// [AppData.refreshPoliticians] — a timeout, offline device, or unchanged
  /// roster (304) all resolve to null here and leave [_data] untouched.
  Future<void> _refreshPoliticiansInBackground() async {
    final updated = await AppData.refreshPoliticians();
    if (updated == null || !mounted || _data == null) return;
    setState(() => _data = _data!.withPoliticians(updated));
  }

  Future<void> _finishOnboarding(String stateCode) async {
    await _store.saveHomeState(stateCode);
    await _store.setOnboarded();
    if (!mounted) return;
    setState(() {
      _homeState = stateCode;
      _view = _View.home;
    });
    final pending = _pendingSyncCode;
    if (pending != null) {
      _pendingSyncCode = null;
      _openFriendCompare(pending);
    }
  }

  Future<void> _changeHomeState(String stateCode) async {
    await _store.saveHomeState(stateCode);
    // Districts are drawn per state — a stored number from the old state
    // would silently filter the wrong House seat.
    await _store.saveHomeDistrict(null);
    if (!mounted) return;
    setState(() {
      _homeState = stateCode;
      _homeDistrict = null;
    });
  }

  Future<void> _changeHomeDistrict(int? district) async {
    await _store.saveHomeDistrict(district);
    if (!mounted) return;
    setState(() => _homeDistrict = district);
  }

  Future<void> _onQuizComplete(QuizResult result) async {
    final profile = Scoring.profileFromAnswers(
      questions: _quizQuestions,
      likertIndexes: result.likertIndexes,
      issues: _data!.issues,
      importanceIndexes: result.importanceIndexes,
      dealbreakerIssueIds: result.dealbreakerIssueIds,
    );
    await _store.saveRun(QuizRun.fromProfile(profile));
    if (!mounted) return;
    setState(() {
      _profile = profile;
      _handSet = false;
      _hasInProgress = false;
      _resumeAnswers = null;
      _resumeIndex = 0;
      _resumeImportance = null;
      _resumeDealbreakers = const [];
      _resuming = false;
      _quizQuestions = const [];
      _view = _View.results;
    });
    await _syncWidget();
  }

  Future<void> _openQuiz({bool resume = false}) async {
    if (resume) {
      final progress = await _store.loadProgress();
      if (!mounted) return;
      if (progress == null) {
        setState(() {
          _hasInProgress = false;
          _resumeAnswers = null;
          _resumeIndex = 0;
          _resumeImportance = null;
          _resumeDealbreakers = const [];
          _resuming = false;
        });
        return;
      }
      final ordered = progress.questionIds.isEmpty
          ? const <Question>[]
          : _orderedQuestions(progress.questionIds);
      if (ordered.length != progress.answers.length || ordered.isEmpty) {
        await _store.clearProgress();
        if (!mounted) return;
        setState(() {
          _hasInProgress = false;
          _resumeAnswers = null;
          _resumeIndex = 0;
          _resumeImportance = null;
          _resumeDealbreakers = const [];
          _resuming = false;
        });
        return;
      }
      setState(() {
        _quizQuestions = ordered;
        _resumeAnswers = progress.answers;
        _resumeIndex = progress.index;
        _resumeImportance = progress.importanceIndexes;
        _resumeDealbreakers = progress.dealbreakerIssueIds;
        _resuming = true;
        _view = _View.quiz;
      });
      return;
    }

    // Fresh start: draw from the bank (variants differ each run).
    await _store.clearProgress();
    final shuffled = QuizBank.draw(
      pool: _data!.questions,
      length: _settings.quizLength,
      includeHistorical: FigureFloor.showsHistoricalQuiz(_settings.figureFloor),
    );
    if (!mounted) return;
    setState(() {
      _quizQuestions = shuffled;
      _hasInProgress = false;
      _resumeAnswers = null;
      _resumeIndex = 0;
      _resumeImportance = null;
      _resumeDealbreakers = const [];
      _resuming = false;
      _view = _View.quiz;
    });
  }

  Future<void> _exitQuiz() async {
    final progress = await _store.loadProgress();
    if (!mounted) return;
    setState(() {
      _hasInProgress = progress != null;
      _resumeAnswers = progress?.answers;
      _resumeIndex = progress?.index ?? 0;
      _resumeImportance = progress?.importanceIndexes;
      _resumeDealbreakers = progress?.dealbreakerIssueIds ?? const [];
      if (progress != null && progress.questionIds.isNotEmpty) {
        _quizQuestions = _orderedQuestions(progress.questionIds);
      }
      _resuming = false;
      _view = _View.home;
    });
  }

  /// Browse mode — the roster with whatever placement exists, or none.
  void _openExplore() {
    final data = _data;
    final nav = _navKey.currentState;
    if (data == null || nav == null) return;
    // Plain route on purpose: Explore owns the fold split itself
    // (roster/detail FoldSplitView), which needs the full window. A
    // FoldConfinedRoute would squeeze it into the secondary pane.
    nav.push(
      MaterialPageRoute<void>(
        builder: (_) => ExploreScreen(
          data: data,
          userProfile: _profile,
          figureFloor: _settings.figureFloor,
        ),
      ),
    );
  }

  /// Hand-set placement: skips the quiz but saves the same profile shape.
  Future<void> _openManualLevel() async {
    final data = _data;
    if (data == null) return;
    final profile = await _navKey.currentState?.push<SpectrumProfile>(
      foldAwareRoute<SpectrumProfile>(
        _navKey.currentContext!,
        builder: (_) =>
            ManualProfileScreen(data: data, initialProfile: _profile),
      ),
    );
    if (profile == null || !mounted) return;
    await _store.saveRun(
      QuizRun.fromProfile(profile, label: QuizRun.handSetLabel),
    );
    if (!mounted) return;
    setState(() {
      _profile = profile;
      _handSet = true;
      _hasInProgress = false;
      _resumeAnswers = null;
      _resumeIndex = 0;
      _resumeImportance = null;
      _resumeDealbreakers = const [];
      _resuming = false;
      _view = _View.results;
    });
    await _syncWidget();
  }

  Future<void> _applySettings(AppSettings next) async {
    final wasHistorical = FigureFloor.showsHistoricalQuiz(
      _settings.figureFloor,
    );
    final nowHistorical = FigureFloor.showsHistoricalQuiz(next.figureFloor);
    final lengthChanged = next.quizLength != _settings.quizLength;
    // A draft is a fixed list of questions. Changing the era or the length
    // makes it the wrong list, so it cannot be resumed.
    final dropDraft = wasHistorical != nowHistorical || lengthChanged;

    // Permission lives with the OS: if the user declines the prompt, store
    // the honest state rather than a toggle that does nothing.
    if (next.dailyReminder != _settings.dailyReminder) {
      final armed = await IssueReminder.setEnabled(
        next.dailyReminder,
        week: _week,
      );
      if (armed != next.dailyReminder) {
        next = next.copyWith(dailyReminder: armed);
      }
    }

    await _store.saveSettings(next);
    if (dropDraft) await _store.clearProgress();
    AppFeel.apply(next);
    if (!mounted) return;
    setState(() {
      _settings = next;
      if (dropDraft) {
        _hasInProgress = false;
        _resumeAnswers = null;
        _resumeIndex = 0;
        _resumeImportance = null;
        _resumeDealbreakers = const [];
      }
    });
    await _syncWidget();
  }

  Future<void> _deleteEverything() async {
    await _store.clearEverything();
    AppFeel.apply(const AppSettings());
    unawaited(IssueReminder.setEnabled(false));
    if (!mounted) return;
    setState(() {
      _settings = const AppSettings();
      _profile = null;
      _handSet = false;
      _homeState = null;
      _homeDistrict = null;
      _hasInProgress = false;
      _resumeAnswers = null;
      _resumeIndex = 0;
      _resumeImportance = null;
      _resumeDealbreakers = const [];
      _quizQuestions = const [];
    });
  }

  /// Writes a restored placement over whatever is on this device.
  Future<void> _applyTransfer(TransferPayload payload) async {
    final data = _data;
    if (data == null) return;
    var settings = payload.settings;
    // A restored preference says the other device wanted reminders — this
    // device still has to grant its own permission before anything fires.
    if (settings.dailyReminder) {
      final armed = await IssueReminder.setEnabled(true, week: _week);
      if (!armed) settings = settings.copyWith(dailyReminder: false);
    }
    await _store.saveSettings(settings);
    AppFeel.apply(settings);
    final state = payload.homeStateCode;
    if (state != null && state.isNotEmpty) {
      await _store.saveHomeState(state);
    }
    SpectrumProfile? profile;
    if (payload.hasProfile) {
      profile = Scoring.profileFromIssueScores(
        issueScores: payload.issueScores,
        issues: data.issues,
        issueWeights: payload.issueWeights,
        dealbreakerIssueIds: payload.dealbreakerIssueIds,
      );
      await _store.saveRun(
        QuizRun.fromProfile(
          profile,
          label: payload.handSet ? QuizRun.handSetLabel : 'Restored',
        ),
      );
    }
    if (!mounted) return;
    setState(() {
      _settings = settings;
      if (state != null && state.isNotEmpty) _homeState = state;
      if (profile != null) {
        _profile = profile;
        _handSet = payload.handSet;
        _hasInProgress = false;
        _resumeAnswers = null;
        _resumeIndex = 0;
        _resumeImportance = null;
        _resumeDealbreakers = const [];
      }
      _view = profile != null ? _View.results : _view;
    });
    await _syncWidget();
    if (!mounted) return;
    _messengerKey.currentState?.showSnackBar(
      const SnackBar(content: Text('Restored from your other phone')),
    );
  }

  Future<void> _openTransfer() async {
    final latest = await _store.latestRun();
    final link = await _store.loadShareLink();
    if (!mounted) return;
    final profile = latest?.toProfile();
    final payload = profile == null
        ? TransferPayload(homeStateCode: _homeState, settings: _settings)
        : TransferPayload.fromProfile(
            profile: profile,
            settings: _settings,
            homeStateCode: _homeState,
            takenAt: DateTime.fromMillisecondsSinceEpoch(latest!.timestampMs),
            handSet: latest.isHandSet,
          );
    final outcome = await _navKey.currentState?.push<TransferOutcome>(
      foldAwareRoute<TransferOutcome>(
        _navKey.currentContext!,
        builder: (_) => TransferScreen(
          payload: payload,
          profile: profile,
          homeStateCode: _homeState,
          label: latest?.label,
          takenAt: latest == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(latest.timestampMs),
          existingLink: link,
          onLinkChanged: (next) async {
            if (next == null) {
              await _store.clearShareLink();
            } else {
              await _store.saveShareLink(next);
            }
          },
        ),
      ),
    );
    if (outcome == null || !mounted) return;
    await _applyTransfer(outcome.payload);
  }

  void _openSettings() {
    _navKey.currentState?.push(
      foldAwareRoute<void>(
        _navKey.currentContext!,
        builder: (_) => SettingsScreen(
          settings: _settings,
          onSettings: _applySettings,
          homeStateCode: _homeState,
          homeDistrict: _homeDistrict,
          onHomeState: _changeHomeState,
          onHomeDistrict: _changeHomeDistrict,
          onTransfer: _openTransfer,
          onClearProgress: () async {
            await _store.clearProgress();
            if (!mounted) return;
            setState(() {
              _hasInProgress = false;
              _resumeAnswers = null;
              _resumeIndex = 0;
              _resumeImportance = null;
              _resumeDealbreakers = const [];
            });
          },
          onDeleteEverything: _deleteEverything,
          onMethodology: _openMethodology,
          hasInProgress: _hasInProgress,
          hasSavedResult: _profile != null,
        ),
      ),
    );
  }

  void _openMethodology() {
    _navKey.currentState?.push(
      foldAwareRoute<void>(
        _navKey.currentContext!,
        builder: (_) => const MethodologyScreen(),
      ),
    );
  }

  ThemeMode get _themeMode => switch (_settings.theme) {
    AppThemeMode.light => ThemeMode.light,
    AppThemeMode.dark => ThemeMode.dark,
    AppThemeMode.system => ThemeMode.system,
  };

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Voteaxis',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: _themeMode,
      navigatorKey: _navKey,
      scaffoldMessengerKey: _messengerKey,
      builder: (context, child) {
        // The palette is ambient — static AppColors reads resolve through the
        // active brightness, synced here once per frame before any descendant
        // builds.
        final brightness = Theme.of(context).brightness;
        AppColors.sync(brightness);
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: _overlayStyleFor(brightness),
          child: _RestoreSystemInsets(
            child: _DuoGlanceGate(
              week: _week,
              data: _data,
              axisLabel: _profile == null
                  ? null
                  : Scoring.formatScore(_profile!.axisScore),
              child: child ?? const SizedBox.shrink(),
            ),
          ),
        );
      },
      home: _currentView(),
    );
  }

  Widget _currentView() {
    if (_view == _View.loading) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: Image.asset(
                  'assets/brand/voteaxis-mark.png',
                  width: 88,
                  height: 88,
                  fit: BoxFit.cover,
                  semanticLabel: 'Voteaxis',
                ),
              ),
              const SizedBox(height: 20),
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              ),
            ],
          ),
        ),
      );
    }

    if (_error != null || _data == null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Failed to load app data.\n$_error'),
          ),
        ),
      );
    }

    final data = _data!;
    final day = IssueOfTheDay.resolve(week: _week, questions: data.questions);

    return switch (_view) {
      _View.loading => const SizedBox.shrink(),
      _View.onboarding => OnboardingScreen(
        initialStateCode: _homeState,
        onContinue: _finishOnboarding,
      ),
      _View.home => HomeScreen(
        hasSavedResult: _profile != null,
        hasInProgress: _hasInProgress,
        homeStateCode: _homeState,
        onHomeStateChanged: _changeHomeState,
        onStartQuiz: () => _openQuiz(),
        onResumeQuiz: () => _openQuiz(resume: true),
        onViewResults: () => setState(() => _view = _View.results),
        onMethodology: _openMethodology,
        onSettings: _openSettings,
        skipQuiz: _settings.skipQuiz,
        reduceMotion: _settings.reduceMotion,
        week: _week,
        day: day,
        issueLabel: data.issuesById[day.issueId]?.label,
        onFriendCompare: _openFriendCompare,
        onSetLevel: _openManualLevel,
        onExplore: _openExplore,
      ),
      _View.quiz => QuizScreen(
        key: ValueKey(
          _resuming
              ? 'resume-${_quizQuestions.map((q) => q.id).join(',')}'
              : 'fresh-${_quizQuestions.map((q) => q.id).join(',')}',
        ),
        questions: _quizQuestions,
        issuesById: data.issuesById,
        initialAnswers: _resuming ? _resumeAnswers : null,
        initialImportance: _resuming ? _resumeImportance : null,
        initialDealbreakers: _resuming ? _resumeDealbreakers : null,
        initialIndex: _resuming ? _resumeIndex : 0,
        showDealbreakers: _settings.dealbreakerPrompts,
        onComplete: _onQuizComplete,
        onExit: _exitQuiz,
      ),
      _View.results => ResultsScreen(
        userProfile: _profile!,
        data: data,
        handSet: _handSet,
        homeStateCode: _homeState,
        homeDistrict: _homeDistrict,
        figureFloor: _settings.figureFloor,
        timeBlind: _settings.timeBlind,
        day: day,
        issueLabel: data.issuesById[day.issueId]?.label,
        onRetake: () => _openQuiz(),
        onHome: () => setState(() => _view = _View.home),
      ),
    };
  }
}

/// Propped pose (tent/laptop) swaps the whole UI for the Issue-of-the-Week
/// glance card on the pane above the crease. The app tree stays mounted
/// underneath — paused for ticks and semantics — so exiting the pose
/// returns to the same screen, scroll offset, and quiz state.
class _DuoGlanceGate extends StatelessWidget {
  const _DuoGlanceGate({
    required this.child,
    required this.week,
    required this.data,
    this.axisLabel,
  });

  final Widget child;
  final IssueOfTheWeek? week;
  final AppData? data;
  final String? axisLabel;

  @override
  Widget build(BuildContext context) {
    return DuoFoldBuilder(
      builder: (context, fold, mode) {
        final data = this.data;
        if (mode != FoldMode.glance || data == null) return child;
        final day = IssueOfTheDay.resolve(
          week: week,
          questions: data.questions,
        );
        final issueLabel = data.issuesById[day.issueId]?.label;
        return Stack(
          children: [
            Offstage(child: TickerMode(enabled: false, child: child)),
            DuoGlanceScreen(
              fold: fold,
              day: day,
              issueLabel: issueLabel,
              axisLabel: axisLabel,
            ),
          ],
        );
      },
    );
  }
}
