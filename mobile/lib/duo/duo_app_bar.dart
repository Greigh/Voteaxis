// An app bar that follows the fold. During a vertical split the leading,
// title and trailing widgets compress into the primary pane — the same
// column the content occupies — instead of hugging the display's outer
// edges. Horizontal splits (the top pane is full width) and non-Duo
// surfaces get an ordinary full-width AppBar.

import 'package:duo_fold/duo_fold.dart';
import 'package:flutter/material.dart';

import 'duo_scope.dart';

/// Builds an [AppBar] that confines itself to the primary fold pane in
/// book pose. Inside the pane the title centres, matching the column of
/// content below it.
PreferredSizeWidget duoAppBar({
  Widget? leading,
  Widget? title,
  List<Widget>? actions,
  bool automaticallyImplyLeading = true,
}) {
  return _DuoPaneAppBar(
    leading: leading,
    title: title,
    actions: actions,
    automaticallyImplyLeading: automaticallyImplyLeading,
  );
}

class _DuoPaneAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _DuoPaneAppBar({
    this.leading,
    this.title,
    this.actions,
    this.automaticallyImplyLeading = true,
  });

  final Widget? leading;
  final Widget? title;
  final List<Widget>? actions;
  final bool automaticallyImplyLeading;

  AppBar _bar({required bool centerTitle}) => AppBar(
    leading: leading,
    title: title,
    actions: actions,
    automaticallyImplyLeading: automaticallyImplyLeading,
    centerTitle: centerTitle,
  );

  @override
  Size get preferredSize => _bar(centerTitle: false).preferredSize;

  @override
  Widget build(BuildContext context) {
    return DuoFoldBuilder(
      builder: (context, fold, mode) {
        if (mode != FoldMode.splitVertical) return _bar(centerTitle: false);
        final division = FoldLayout.clippedDivision(
          fold,
          MediaQuery.sizeOf(context),
        );
        if (division == null) return _bar(centerTitle: false);
        // The confined bar re-centres its title over the primary pane, the
        // way a standalone pane-width screen would.
        return Align(
          alignment: AlignmentDirectional.centerStart,
          child: SizedBox(width: division.left, child: _bar(centerTitle: true)),
        );
      },
    );
  }
}
