import 'dart:convert';

import 'package:firebase_app_installations/firebase_app_installations.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/notification_channel.dart';
import '../services/api.dart';
import '../services/api_service.dart';
import '../services/firestore_service.dart';
import '../theme/app_spacing.dart';
import '../theme/tokens.dart';
import '../widgets/kit/kit.dart';
import '../services/error_text.dart';

/// Notification channels editor (`screens/notifications.md`; contract 2.5.0
/// ADR-014, push 2.6.0 ADR-015). A user adds any number of channels, each a
/// type + a chosen subset of severity levels. Writes go through [Api]
/// (`fn_notification_channels`, INV-04); the list is a live subscription
/// (INV-02).
///
/// Composition (§Composition, 4.5.0/ADR-041): the Reading frame, a §2.2
/// sub-screen header, one raised row list of setting rows, then the "Add a
/// channel" form as labelled field groups with §6.8 segmented controls.
///
/// Push (4.8.0, ADR-044): creating a push channel registers this install by
/// its Firebase installation id (`fid`) — an ADDRESS, not a subscription.
/// This app carries no FCM token (no `firebase_messaging`), so a push
/// channel is saved but cannot reach this device yet, and the row says so in
/// its description slot rather than rendering as a silently enabled channel.
class NotificationSettingsPage extends StatefulWidget {
  const NotificationSettingsPage({super.key});

  @override
  State<NotificationSettingsPage> createState() =>
      _NotificationSettingsPageState();
}

/// Client-local: what was registered for this device, so the last push
/// channel's deletion can unregister it under the same keying (web:
/// `nl-fcm-token`).
const _deviceKey = 'nl-fcm-token';

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
const _draftLevels = {'error', 'warning'};

/// The description slot of a push channel that cannot deliver here. Same
/// sentence shape as the web's `PUSH_ERR_COPY.unsupported`: the channel is
/// saved, and the reader is told it will not reach this device.
const _pushUnreachable =
    'This app can’t receive push notifications yet; the channel is saved but '
    'won’t reach this device.';
const _pushRegisterFailed =
    'Saved, but this device couldn’t be registered for push right now.';

class _NotificationSettingsPageState extends State<NotificationSettingsPage> {
  String _type = 'onscreen';
  final Set<String> _levelsDraft = {..._draftLevels};
  final _destCtrl = TextEditingController();
  final _labelCtrl = TextEditingController();
  bool _busy = false;

  /// §14.2 — the rejection beside the control that refused it, verbatim.
  String? _error;

  /// What the last push registration attempt reported; shown in every push
  /// row's description while set, per §Composition's last rule.
  String? _pushNote;

  @override
  void dispose() {
    _destCtrl.dispose();
    _labelCtrl.dispose();
    super.dispose();
  }

  Future<Map<String, String>?> _readDeviceIds() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_deviceKey);
    if (raw == null) return null;
    try {
      final v = jsonDecode(raw);
      if (v is Map) return v.map((k, val) => MapEntry('$k', '$val'));
    } catch (_) {
      // An older build wrote a bare token string — keep it, dropping it would
      // strand a registered device that push then keeps reaching.
    }
    return {'token': raw};
  }

  /// Register this install for push by its `fid` (ADR-044). Returns the note
  /// for the row: null only when the device can actually be reached.
  Future<String?> _registerThisDevice() async {
    try {
      final fid = await FirebaseInstallations.instance.getId();
      final platform =
          defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'web';
      await Api.instance.registerDevice(fid: fid, platform: platform);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_deviceKey, jsonEncode({'fid': fid}));
    } catch (_) {
      return _pushRegisterFailed;
    }
    // A fid is an address, not a subscription: with no FCM token there is
    // still nothing for the sender to deliver to.
    return _pushUnreachable;
  }

  Future<void> _add() async {
    if (_levelsDraft.isEmpty) {
      setState(() => _error = 'Pick at least one level.');
      return;
    }
    if (_type == 'email' && !_emailRe.hasMatch(_destCtrl.text.trim())) {
      setState(() =>
          _error = 'Enter a valid email address for an email channel.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      String? pushNote;
      if (_type == 'push') pushNote = await _registerThisDevice();
      await Api.instance.createNotificationChannel(
        type: _type,
        levels: _levelsDraft.toList(),
        label: _labelCtrl.text.trim().isEmpty ? null : _labelCtrl.text.trim(),
        destination: _type == 'email' ? _destCtrl.text.trim() : null,
      );
      _destCtrl.clear();
      _labelCtrl.clear();
      if (!mounted) return;
      setState(() {
        _type = 'onscreen';
        _levelsDraft
          ..clear()
          ..addAll(_draftLevels);
        _pushNote = pushNote;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // Write before move: the row re-renders from the subscription once the
  // PUT lands; nothing flips locally first.
  Future<void> _patch(NotificationChannel c, Map<String, dynamic> partial) async {
    try {
      await Api.instance.updateNotificationChannel(c.id, partial);
      if (mounted && _error != null) setState(() => _error = null);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  // §18 Confirmation (4.56.0, ADR-092). `screens/notifications.md` has required
  // this since the screen existed and no client had built it — the channel went
  // on the first tap. The copy names the consequence a reader cannot see from
  // the row: the LAST push channel also unregisters the device, so one tap
  // could stop every notification reaching it.
  Future<void> _confirmRemove(
      NotificationChannel c, List<NotificationChannel> all) async {
    final name = c.label?.isNotEmpty == true
        ? c.label!
        : (_typeLabel[c.type] ?? c.type);
    final lastPush =
        c.type == 'push' && !all.any((o) => o.id != c.id && o.type == 'push');
    final lost = switch (c.type) {
      'email' => 'Activity stops reaching ${c.destination ?? 'that address'}.',
      'push' => 'Pushed alerts stop reaching your devices.',
      _ => 'Toasts and the unread badge stop appearing in the app.',
    };
    await KitConfirm.show(
      context,
      // Quoted, with no appended noun: a channel labelled "Push channel" gave
      // "Delete the Push channel channel?".
      title: 'Delete “$name”?',
      body: '$lost Your letters keep being built and sent, and nothing in your '
          'library changes.'
          '${lastPush ? '\n\nThis is your only push channel — this device will '
              'also stop being registered, so no notification of any level will '
              'reach it until you add one again.' : ''}',
      confirmLabel: 'Delete channel',
      cancelLabel: 'Keep it',
      onConfirm: () => _remove(c, all),
    );
  }

  /// Returns null on success and the server's sentence on a refusal — §18's
  /// contract with the panel, which stays open on one.
  Future<String?> _remove(
      NotificationChannel c, List<NotificationChannel> all) async {
    try {
      await Api.instance.deleteNotificationChannel(c.id);
      // Unregister this device once the last push channel is gone.
      if (c.type == 'push' &&
          !all.any((o) => o.id != c.id && o.type == 'push')) {
        final ids = await _readDeviceIds();
        if (ids != null) {
          try {
            await Api.instance
                .unregisterDevice(token: ids['token'], fid: ids['fid']);
          } catch (_) {
            // best-effort
          }
          final prefs = await SharedPreferences.getInstance();
          await prefs.remove(_deviceKey);
        }
      }
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (_) {
      return 'Could not reach your library. Check your connection.';
    }
  }

  @override
  Widget build(BuildContext context) {
    return KitPage(
      width: KitFrameWidth.reading,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SubScreenHeader(
            parentLabel: 'Settings',
            onBack: () => context.go('/settings'),
            eyebrow: 'Notifications',
            standfirst:
                'Choose how you hear about what NoteLetter does — and at what '
                'severity. Add as many channels as you like.',
          ),
          // `.set-section` opens 34 under the header, which has paid 20 of it.
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: StreamBuilder<List<NotificationChannel>>(
              stream: FirestoreService.instance.subscribeNotificationChannels(),
              builder: (context, snap) => _channelList(snap),
            ),
          ),
          // 34 again; the section header's own 32 collapses into it.
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: _addForm(),
          ),
        ],
      ),
    );
  }

  Widget _channelList(AsyncSnapshot<List<NotificationChannel>> snap) {
    final t = Tokens.of(context);
    if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
      return KitRowList(raised: true, rows: [
        KitRowSlot(child: Text('Loading…', style: KitText.meta(context))),
      ]);
    }
    // INV-24 (ADR-071): an unread channel list renders as "no channels",
    // which is the state a reader acts on by creating one they already have.
    if (snap.hasError) {
      return KitRowList(raised: true, rows: [
        KitRowSlot(
          child: KitFailureInline(
              'Your channels could not be read — '
              '${describeSdkError(snap.error!)}'),
        ),
      ]);
    }
    final channels = snap.data ?? const <NotificationChannel>[];
    if (channels.isEmpty) {
      return const KitRowList(raised: true, rows: [
        KitSettingRow(
          icon: Icons.notifications_none,
          title: 'No channels yet',
          description:
              'Add one below. An on-screen channel powers the Activity toasts '
              'and unread badge; email reaches you when you’re away.',
        ),
      ]);
    }
    return KitRowList(
      raised: true,
      rows: [
        for (final c in channels)
          KitSettingRow(
            icon: c.type == 'email' ? Icons.mail_outline : Icons.notifications_none,
            title: (c.label?.isNotEmpty ?? false)
                ? c.label!
                : (_typeLabel[c.type] ?? c.type),
            titleNote: c.enabled ? null : '(paused)',
            description: switch (c.type) {
              'email' => c.destination ?? '',
              'push' => _pushNote ?? 'Pushed to your devices',
              _ => 'Shown in the app',
            },
            below: KitSegmentedMulti(
              expand: true,
              segments: [for (final l in _levels) KitSegment(_levelLabel[l]!)],
              selected: {
                for (var i = 0; i < _levels.length; i++)
                  if (c.levels.contains(_levels[i])) i,
              },
              onToggle: (i) {
                final next = {...c.levels};
                next.contains(_levels[i])
                    ? next.remove(_levels[i])
                    : next.add(_levels[i]);
                if (next.isEmpty) {
                  setState(
                      () => _error = 'A channel needs at least one level.');
                  return;
                }
                _patch(c, {'levels': next.toList()});
              },
            ),
            trailing: [
              KitSwitch(
                value: c.enabled,
                tooltip: c.enabled ? 'Enabled' : 'Paused',
                onChanged: (v) => _patch(c, {'enabled': v}),
              ),
              KitIconButton(
                Icons.delete_outline,
                tooltip: 'Delete channel',
                color: t.fgMuted,
                onPressed: () => _confirmRemove(c, channels),
              ),
            ],
          ),
      ],
    );
  }

  Widget _addForm() {
    final t = Tokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('Add a channel'),
        KitFieldGroup(
          label: 'Type',
          first: true,
          child: KitSegmented(
            expand: true,
            segments: [for (final ty in _types) KitSegment(_typeLabel[ty]!)],
            selected: _types.indexOf(_type),
            onChanged: (i) => setState(() {
              _type = _types[i];
              _error = null;
              _pushNote = null;
            }),
          ),
        ),
        if (_type == 'email')
          KitFieldGroup(
            label: 'Send to',
            child: KitTextField(
              controller: _destCtrl,
              icon: Icons.mail_outline,
              placeholder: 'you@example.com',
              keyboardType: TextInputType.emailAddress,
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
            ),
          ),
        KitFieldGroup(
          label: 'Notify me about',
          child: KitSegmentedMulti(
            expand: true,
            segments: [for (final l in _levels) KitSegment(_levelLabel[l]!)],
            selected: {
              for (var i = 0; i < _levels.length; i++)
                if (_levelsDraft.contains(_levels[i])) i,
            },
            onToggle: (i) => setState(() {
              _levelsDraft.contains(_levels[i])
                  ? _levelsDraft.remove(_levels[i])
                  : _levelsDraft.add(_levels[i]);
              _error = null;
            }),
          ),
        ),
        KitFieldGroup(
          label: 'Label',
          note: 'optional',
          child: KitTextField(
            controller: _labelCtrl,
            placeholder: _type == 'email' ? 'Work inbox' : 'In-app',
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.s4),
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 10,
            runSpacing: AppSpacing.s2,
            children: [
              KitButton.primary(
                _busy ? 'Adding…' : 'Add channel',
                icon: _busy ? null : Icons.add,
                onPressed: _busy ? null : _add,
              ),
              // §14.2 takes no icon: the line is the rejection.
              if (_error != null) KitFailureInline(_error!),
            ],
          ),
        ),
        if (_type == 'push')
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.s2),
            child: Text(
              'Adding a push channel registers this device by its '
              'installation id.',
              style: KitText.meta(context).copyWith(color: t.fgMuted),
            ),
          ),
      ],
    );
  }
}
