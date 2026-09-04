import 'package:flutter/material.dart';

import 'input/gamepad.dart';

/// Hosts the shell's branch navigators. go_router's own container keeps the
/// hidden branches focusable, so a D-pad press could walk into a tab that is
/// not on screen and A would activate something invisible. Here every branch
/// sits in its own [FocusScope] behind an [ExcludeFocus] that only the shown
/// one escapes, and a tab switch hands the focus over to the branch coming in.
///
/// (Toggling `canRequestFocus` on the scope itself would be simpler, but a
/// [FocusScope] with a caller-owned node reads the derived
/// `descendantsAreFocusable` back into the node and latches it to false.)
class BranchHost extends StatefulWidget {
  const BranchHost({super.key, required this.index, required this.children});

  final int index;
  final List<Widget> children;

  @override
  State<BranchHost> createState() => _BranchHostState();
}

class _BranchHostState extends State<BranchHost> {
  late final List<FocusScopeNode> _scopes = [
    for (var i = 0; i < widget.children.length; i++)
      FocusScopeNode(debugLabel: 'branch $i'),
  ];

  @override
  void initState() {
    super.initState();
    // The first branch pushes its routes while our scope has no focus yet,
    // so the primary focus would sit above the shortcuts until the first
    // D-pad press — Select or L1 right after launch would do nothing.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final scope = _scopes[widget.index];
      if (!scope.hasFocus) scope.requestFocus();
    });
  }

  @override
  void didUpdateWidget(BranchHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index == widget.index) return;
    // After this frame, once the old branch has let go of the focus.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _settleFocus();
    });
  }

  /// With the pad driving, the branch gets back whatever it had focused (or
  /// its first item on the next D-pad press). After a tap only the scope
  /// itself, so nothing lights up or scrolls into view. Either way a
  /// remembered search field stays unfocused: it would bring the keyboard
  /// back with it.
  void _settleFocus() {
    final scope = _scopes[widget.index];
    final manager = FocusManager.instance;
    if (manager.highlightMode == FocusHighlightMode.traditional) {
      scope.requestFocus();
    } else {
      scope.requestScopeFocus();
    }
    manager.applyFocusChangesIfNeeded();
    if (isTyping()) {
      manager.primaryFocus?.unfocus(disposition: UnfocusDisposition.scope);
    }
  }

  @override
  void dispose() {
    for (final scope in _scopes) {
      scope.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IndexedStack(
    index: widget.index,
    children: [
      for (var i = 0; i < widget.children.length; i++)
        ExcludeFocus(
          excluding: i != widget.index,
          child: FocusScope(
            node: _scopes[i],
            child: Offstage(
              offstage: i != widget.index,
              child: TickerMode(
                enabled: i == widget.index,
                child: widget.children[i],
              ),
            ),
          ),
        ),
    ],
  );
}
