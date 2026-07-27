import 'package:flutter/material.dart';
import '../models/notification_channel.dart';
import '../services/api.dart';
import '../services/api_service.dart';
import '../services/firestore_service.dart';

/// Notification channels editor (contract 2.5.0 ADR-014; push 2.6.0 ADR-015).
/// A user adds any number of channels, each a type + a chosen subset of
/// severity levels. Writes go through [Api] (fn_notification_channels); the list
/// is a live subscription (INV-02).
///
/// Note: live push token registration needs `firebase_messaging` + a registered
/// native Firebase app (this app is web-target-only today). A push channel can
/// be created now; the FCM token/`fn_register_device` wiring lands with native
/// Firebase registration (the same deferral as the web VAPID-key prerequisite).
class NotificationSettingsPage extends StatefulWidget {
  const NotificationSettingsPage({super.key});

  @override
  State<NotificationSettingsPage> createState() =>
      _NotificationSettingsPageState();
}

const _levels = ['error', 'warning', 'success', 'info'];
const _levelLabel = {
  'error': 'Errors',
  'warning': 'Warnings',
  'success': 'Successes',
  'info': 'Info',
};
const _types = ['onscreen', 'email', 'push'];
const _typeLabel = {'onscreen': 'On-screen', 'email': 'Email', 'push': 'Push'};
final _emailRe = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

class _NotificationSettingsPageState extends State<NotificationSettingsPage> {
  String _type = 'onscreen';
  final Set<String> _draftLevels = {'error', 'warning'};
  final _destCtrl = TextEditingController();
  final _labelCtrl = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _destCtrl.dispose();
    _labelCtrl.dispose();
    super.dispose();
  }

  void _snack(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  Future<void> _add() async {
    if (_draftLevels.isEmpty) {
      _snack('Pick at least one level.');
      return;
    }
    if (_type == 'email' && !_emailRe.hasMatch(_destCtrl.text.trim())) {
      _snack('Enter a valid email address for an email channel.');
      return;
    }
    final wasPush = _type == 'push';
    setState(() => _busy = true);
    try {
      await Api.instance.createNotificationChannel(
        type: _type,
        levels: _draftLevels.toList(),
        label: _labelCtrl.text.trim().isEmpty ? null : _labelCtrl.text.trim(),
        destination: _type == 'email' ? _destCtrl.text.trim() : null,
      );
      _destCtrl.clear();
      _labelCtrl.clear();
      setState(() {
        _type = 'onscreen';
        _draftLevels
          ..clear()
          ..addAll({'error', 'warning'});
      });
      if (wasPush) {
        _snack('Push channel saved. Delivery needs native FCM setup on this app.');
      }
    } on ApiException catch (e) {
      _snack(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _patch(NotificationChannel c, Map<String, dynamic> partial) async {
    try {
      await Api.instance.updateNotificationChannel(c.id, partial);
    } on ApiException catch (e) {
      _snack(e.message);
    }
  }

  Future<void> _remove(NotificationChannel c) async {
    try {
      await Api.instance.deleteNotificationChannel(c.id);
    } on ApiException catch (e) {
      _snack(e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Channels', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              'Choose how you hear about what NoteLetter does — and at what severity.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            StreamBuilder<List<NotificationChannel>>(
              stream: FirestoreService.instance.subscribeNotificationChannels(),
              builder: (context, snap) {
                final channels = snap.data ?? const [];
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (channels.isEmpty) {
                  return const Card(
                    child: ListTile(
                      leading: Icon(Icons.notifications_none),
                      title: Text('No channels yet'),
                      subtitle: Text(
                          'Add one below. On-screen powers in-app alerts; email reaches you when away.'),
                    ),
                  );
                }
                return Column(
                  children: [for (final c in channels) _channelCard(c)],
                );
              },
            ),
            const SizedBox(height: 24),
            _addCard(theme),
          ],
        ),
      ),
    );
  }

  Widget _channelCard(NotificationChannel c) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(c.type == 'email' ? Icons.mail_outline : Icons.notifications_none),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(c.label?.isNotEmpty == true
                          ? c.label!
                          : (_typeLabel[c.type] ?? c.type)),
                      Text(
                        c.type == 'email'
                            ? (c.destination ?? '')
                            : c.type == 'push'
                                ? 'Pushed to your devices'
                                : 'Shown in the app',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: c.enabled,
                  onChanged: (v) => _patch(c, {'enabled': v}),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Delete channel',
                  onPressed: () => _remove(c),
                ),
              ],
            ),
            Wrap(
              spacing: 6,
              children: [
                for (final l in _levels)
                  FilterChip(
                    label: Text(_levelLabel[l]!),
                    selected: c.levels.contains(l),
                    onSelected: (sel) {
                      final next = {...c.levels};
                      sel ? next.add(l) : next.remove(l);
                      if (next.isEmpty) {
                        _snack('A channel needs at least one level.');
                        return;
                      }
                      _patch(c, {'levels': next.toList()});
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _addCard(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Add a channel', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            const Text('Type'),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: [
                for (final t in _types)
                  ChoiceChip(
                    label: Text(_typeLabel[t]!),
                    selected: _type == t,
                    onSelected: (_) => setState(() => _type = t),
                  ),
              ],
            ),
            if (_type == 'email') ...[
              const SizedBox(height: 12),
              TextField(
                controller: _destCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Send to',
                  hintText: 'you@example.com',
                ),
              ),
            ],
            const SizedBox(height: 12),
            const Text('Notify me about'),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              children: [
                for (final l in _levels)
                  FilterChip(
                    label: Text(_levelLabel[l]!),
                    selected: _draftLevels.contains(l),
                    onSelected: (sel) => setState(() {
                      sel ? _draftLevels.add(l) : _draftLevels.remove(l);
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _labelCtrl,
              decoration: const InputDecoration(
                labelText: 'Label (optional)',
              ),
            ),
            if (_type == 'push')
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text(
                  'Push delivery needs native FCM setup on this app; the channel '
                  'saves either way.',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _busy ? null : _add,
              icon: const Icon(Icons.add),
              label: Text(_busy ? 'Adding…' : 'Add channel'),
            ),
          ],
        ),
      ),
    );
  }
}
