import 'package:flutter/material.dart';

/// A thin indeterminate progress bar sized to sit in an [AppBar.bottom] slot,
/// shown while a background refresh runs over already-visible cached data.
class RefreshBar extends StatelessWidget implements PreferredSizeWidget {
  const RefreshBar({super.key});

  @override
  Size get preferredSize => const Size.fromHeight(2);

  @override
  Widget build(BuildContext context) =>
      const LinearProgressIndicator(minHeight: 2);
}
