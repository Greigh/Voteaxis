// iPhone Duo glue between the app and package:duo_fold.
//
// The app wraps VoteaxisApp in a ProviderScope, so in production every
// consumer here sees the live fold stream. Widget tests pump screens inside
// a bare MaterialApp with no scope — every helper in this file degrades to
// "unsupported / single / plain route" in that case, so tests exercise the
// non-Duo path unchanged.

import 'package:duo_fold/duo_fold.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether [context] sits under a ProviderScope. Without one there is no
/// fold stream to watch; every consumer treats the device as non-Duo.
bool hasProviderScope(BuildContext context) {
  try {
    ProviderScope.containerOf(context, listen: false);
    return true;
  } catch (_) {
    return false;
  }
}

/// The mode [FoldLayout.modeFor] resolves with this app's toggles applied.
FoldMode _resolveMode(WidgetRef ref, BuildContext context) {
  final fold = duoFoldForLayout(ref);
  return FoldLayout.modeFor(
    fold,
    width: MediaQuery.sizeOf(context).width,
    glanceEnabled: ref.watch(duoGlanceEnabledProvider),
    bookSplitEnabled: ref.watch(duoBookSplitProvider),
    horizontalCompact: fold.horizontalSizeClass == 'compact',
  );
}

/// Builds [builder] with the current fold state and resolved mode.
///
/// Without a ProviderScope — widget tests included — the builder runs once
/// with `DuoFoldState.unsupported()` and [FoldMode.single], the same values
/// a non-Duo device produces.
class DuoFoldBuilder extends StatelessWidget {
  const DuoFoldBuilder({required this.builder, super.key});

  final Widget Function(BuildContext context, DuoFoldState fold, FoldMode mode)
  builder;

  @override
  Widget build(BuildContext context) {
    if (!hasProviderScope(context)) {
      return builder(
        context,
        const DuoFoldState.unsupported(),
        FoldMode.single,
      );
    }
    return Consumer(
      builder: (context, ref, _) =>
          builder(context, duoFoldForLayout(ref), _resolveMode(ref, context)),
    );
  }
}

/// A pushed route that confines itself to the fold's secondary pane during
/// a book/flat split — the "readable content must not straddle the crease"
/// idiom. Falls back to a plain [MaterialPageRoute] when nothing foldable
/// is in play (or no ProviderScope exists, as in widget tests).
///
/// [context] must sit below MaterialApp: [FoldConfinedRoute] resolves
/// MaterialLocalizations from it. A state-level context above MaterialApp
/// (like the root App widget's) can't supply one, so callers pushing via
/// a navigator key should pass `nav.context`, not `this.context`.
Route<T> foldAwareRoute<T>(
  BuildContext context, {
  required WidgetBuilder builder,
}) {
  if (hasProviderScope(context) &&
      Localizations.of<MaterialLocalizations>(context, MaterialLocalizations) !=
          null) {
    return FoldConfinedRoute<T>(context: context, builder: builder);
  }
  return MaterialPageRoute<T>(builder: builder);
}
