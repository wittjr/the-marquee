import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/trakt_profile.dart';
import '../state/auth_controller.dart';
import '../state/profile_controller.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) =>
          ProfileController(auth: context.read<AuthController>())..load(),
      child: const _ProfileView(),
    );
  }
}

class _ProfileView extends StatelessWidget {
  const _ProfileView();

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<ProfileController>();
    final auth = context.read<AuthController>();

    return Scaffold(
      appBar: AppBar(
        title:
            const Text('Profile', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            onPressed: auth.signOut,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: profile.load,
        child: switch (profile.state) {
          ProfileState.loading =>
            const Center(child: CircularProgressIndicator()),
          ProfileState.error => _ErrorView(
              message: profile.error ?? 'Something went wrong',
              onRetry: profile.load,
            ),
          ProfileState.ready => _content(context, profile),
        },
      ),
    );
  }

  Widget _content(BuildContext context, ProfileController profile) {
    final user = profile.user!;
    final stats = profile.stats;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _ProfileHeader(user: user),
        if (profile.plex != null) ...[
          const SizedBox(height: 16),
          _PlexTile(plex: profile.plex!),
        ],
        if (stats != null) ...[
          const SizedBox(height: 24),
          _StatsRow(stats: stats),
        ],
        const SizedBox(height: 28),
        const Text('Recently Watched',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        if (profile.history.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text('No watch history yet',
                  style: TextStyle(color: Colors.white60)),
            ),
          )
        else
          for (final item in profile.history) _HistoryTile(item: item),
      ],
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  final TraktUser user;
  const _ProfileHeader({required this.user});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CircleAvatar(
          radius: 36,
          backgroundColor: const Color(0xFF1C1C22),
          backgroundImage: user.avatarUrl != null
              ? CachedNetworkImageProvider(user.avatarUrl!)
              : null,
          child: user.avatarUrl == null
              ? const Icon(Icons.person, size: 36, color: Colors.white24)
              : null,
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(user.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 22, fontWeight: FontWeight.bold)),
                  ),
                  if (user.vip) ...[
                    const SizedBox(width: 8),
                    const _VipChip(),
                  ],
                ],
              ),
              Text('@${user.username}',
                  style: const TextStyle(color: Colors.white60)),
              if (user.location != null && user.location!.isNotEmpty)
                _IconLine(icon: Icons.place_outlined, text: user.location!),
              if (user.joinedAt != null)
                _IconLine(
                    icon: Icons.calendar_today_outlined,
                    text: 'Joined ${_monthYear(user.joinedAt!)}'),
            ],
          ),
        ),
      ],
    );
  }
}

class _PlexTile extends StatelessWidget {
  final PlexStatus plex;
  const _PlexTile({required this.plex});

  @override
  Widget build(BuildContext context) {
    final connected = plex.connected;
    final accent =
        connected ? const Color(0xFFE5A00D) : Colors.white38; // Plex gold
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C22),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.cast_connected, color: accent),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Plex',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              if (connected && plex.username != null)
                Text(plex.username!,
                    style:
                        const TextStyle(color: Colors.white60, fontSize: 12)),
            ],
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: connected
                  ? const Color(0xFF2E7D32)
                  : const Color(0xFF333339),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              connected ? 'Connected' : 'Not connected',
              style: const TextStyle(
                  color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _VipChip extends StatelessWidget {
  const _VipChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFF9A825),
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Text('VIP',
          style: TextStyle(
              color: Colors.black, fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }
}

class _IconLine extends StatelessWidget {
  final IconData icon;
  final String text;
  const _IconLine({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Icon(icon, size: 14, color: Colors.white54),
          const SizedBox(width: 4),
          Flexible(
            child: Text(text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white54, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  final TraktStats stats;
  const _StatsRow({required this.stats});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _StatCard(value: _thousands(stats.moviesWatched), label: 'Movies'),
        const SizedBox(width: 12),
        _StatCard(value: _thousands(stats.episodesWatched), label: 'Episodes'),
        const SizedBox(width: 12),
        _StatCard(value: _duration(stats.totalMinutes), label: 'Watch time'),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String value;
  final String label;
  const _StatCard({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF1C1C22),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(label,
                style: const TextStyle(color: Colors.white60, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  final HistoryItem item;
  const _HistoryTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final isMovie = item.type == HistoryType.movie;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(isMovie ? Icons.movie_rounded : Icons.tv_rounded,
          color: Colors.white54),
      title: Text(item.title,
          maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: item.subtitle != null
          ? Text(item.subtitle!,
              maxLines: 1, overflow: TextOverflow.ellipsis)
          : null,
      trailing: item.watchedAt != null
          ? Text(_shortDate(item.watchedAt!),
              style: const TextStyle(color: Colors.white54, fontSize: 12))
          : null,
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const SizedBox(height: 120),
        const Icon(Icons.error_outline, size: 64, color: Colors.white24),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white60, fontSize: 12)),
        ),
        const SizedBox(height: 16),
        Center(
          child: FilledButton(onPressed: onRetry, child: const Text('Retry')),
        ),
      ],
    );
  }
}

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _monthYear(DateTime d) => '${_months[d.month - 1]} ${d.year}';

String _shortDate(DateTime d) =>
    '${_months[d.month - 1]} ${d.day}, ${d.year}';

String _thousands(int n) => n.toString().replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');

String _duration(int minutes) {
  if (minutes <= 0) return '0h';
  final days = minutes ~/ (60 * 24);
  final hours = (minutes % (60 * 24)) ~/ 60;
  if (days > 0) return '${days}d ${hours}h';
  final mins = minutes % 60;
  if (hours > 0) return '${hours}h ${mins}m';
  return '${mins}m';
}
