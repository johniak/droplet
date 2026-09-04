import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/tokens.dart';

/// The library's search box. It never grabs the focus by itself — Y (or a
/// tap) hands it over, B or Escape hands it back, so the pad is never stuck
/// typing.
class SearchField extends StatefulWidget {
  const SearchField({
    super.key,
    required this.hint,
    required this.onChanged,
    this.controller,
    this.focusNode,
  });

  final String hint;
  final ValueChanged<String> onChanged;
  final TextEditingController? controller;

  /// Supplied by screens that answer `FocusSearchIntent` (Y).
  final FocusNode? focusNode;

  @override
  State<SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<SearchField> {
  FocusNode? _own;

  FocusNode get _node => widget.focusNode ?? (_own ??= FocusNode());

  @override
  void initState() {
    super.initState();
    _node.onKeyEvent = _handleKey;
  }

  @override
  void dispose() {
    _own?.dispose();
    super.dispose();
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key != LogicalKeyboardKey.gameButtonB &&
        key != LogicalKeyboardKey.escape) {
      return KeyEventResult.ignored;
    }
    node.unfocus();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: widget.controller,
    focusNode: _node,
    onChanged: widget.onChanged,
    style: const TextStyle(color: kText, fontSize: 15),
    decoration: InputDecoration(
      hintText: widget.hint,
      prefixIcon: const Icon(Icons.search, color: kTextDim, size: 20),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(24),
        borderSide: const BorderSide(color: kGlassBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(24),
        borderSide: const BorderSide(color: kGlassBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(24),
        borderSide: const BorderSide(color: kAccent),
      ),
    ),
  );
}
