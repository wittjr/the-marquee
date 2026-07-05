import 'package:flutter/material.dart';

/// An app bar title that scrolls its page back to the top when tapped — the
/// familiar "tap the header to jump up" gesture. Give it the [ScrollController]
/// driving the page's scroll view; the tap is a no-op when that controller has
/// no attached scroll view (e.g. an error/empty state is showing).
class ScrollToTopTitle extends StatelessWidget {
  final String title;
  final ScrollController controller;

  const ScrollToTopTitle(this.title, {required this.controller, super.key});

  void _scrollToTop() {
    if (!controller.hasClients) return;
    controller.animateTo(
      0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Fill the width the app bar allots the title (up to the actions) so the
    // blank space beside the text is tappable too, not just the glyphs.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _scrollToTop,
      child: SizedBox(
        width: double.infinity,
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(title,
              style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }
}
