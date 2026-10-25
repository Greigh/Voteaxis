// An app bar that follows the fold. During a vertical split the leading,
// title and trailing widgets compress into the pane the screen's content
// occupies instead of hugging the display's outer edges. Horizontal splits
// (the top pane is full width) and non-Duo surfaces get an ordinary
// full-width AppBar.

import 'package:duo_fold/duo_fold.dart';
import 'package:flutter/material.dart';

import 'duo_scope.dart';

/// Which side of a vertical fold the bar confines itself to.
enum DuoPane { primary, secondary }

/// Builds an [AppBar] that confines itself to [pane] in book pose. Inside
/// the pane the title centres, matching the column of content below it.
PreferredSizeWidget duoAppBar({
  Widget? leading,
  Widget? title,
  List<Widget>? actions,
  bool automaticallyImplyLeading = true,
  DuoPane pane = DuoPane.primary,
}) {
  return _DuoPaneAppBar(
    leading: leading,
    title: title,
    actions: actions,
    automaticallyImplyLeading: automaticallyImplyLeading,
    pane: pane,
  );
}

class _DuoPaneAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _DuoPaneAppBar({
    this.leading,
    this.title,
    this.actions,
    this.automaticallyImplyLeading = true,
    this.pane = DuoPane.primary,
  });

  final Widget? leading;
  final Widget? title;
  final List<Widget>? actions;
  final bool automaticallyImplyLeading;
  final DuoPane pane;

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
        final size = MediaQuery.sizeOf(context);
        final division = FoldLayout.clippedDivision(fold, size);
        if (division == null) return _bar(centerTitle: false);
        // The confined bar re-centres its title over its pane, the way a
        // standalone pane-width screen would.
        return Align(
          alignment: pane == DuoPane.primary
              ? AlignmentDirectional.centerStart
              : AlignmentDirectional.centerEnd,
          child: SizedBox(
            width: pane == DuoPane.primary
                ? division.left
                : size.width - division.right,
            child: _bar(centerTitle: true),
          ),
        );
      },
    );
  }
}
