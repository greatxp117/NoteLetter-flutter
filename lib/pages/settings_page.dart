import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../models/newsletter_settings.dart';
import '../state/settings_notifier.dart';
import '../theme/app_colors.dart';
import '../widgets/app_toast.dart';

class SettingsPage extends StatefulWidget {
  final String? cloudConnectResult;
  final String? cloudConnectProvider;

  const SettingsPage({
    super.key,
    this.cloudConnectResult,
    this.cloudConnectProvider,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  // Newsletter form controllers
  bool _enabled = true;
  String _frequency = 'daily';
  final _deliveryTimeCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _purposeCtrl = TextEditingController();
  int _itemsPerNewsletter = 5;

  // Privacy toggles (local only for now)
  bool _allowTraining = false;
  bool _strictPrivacy = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _handleOAuthCallback();
      context.read<SettingsNotifier>().loadAll().then((_) {
        if (!mounted) return;
        final settings = context.read<SettingsNotifier>().newsletter;
        if (settings != null) _populateForm(settings);
      });
    });
  }

  void _handleOAuthCallback() {
    if (!mounted) return;
    final result = widget.cloudConnectResult;
    final provider = widget.cloudConnectProvider;
    if (result == 'success') {
      AppToast.show(
        context,
        'Connected ${_providerLabel(provider)} successfully.',
        type: ToastType.success,
      );
      context.read<SettingsNotifier>().loadIntegrations();
    } else if (result == 'error') {
      AppToast.show(
        context,
        'Failed to connect ${_providerLabel(provider)}. Please try again.',
        type: ToastType.error,
      );
    }
  }

  void _populateForm(NewsletterSettings s) {
    setState(() {
      _enabled = s.enabled;
      _frequency = s.frequency;
      _itemsPerNewsletter = s.itemsPerNewsletter;
    });
    _deliveryTimeCtrl.text = s.deliveryTime;
    _emailCtrl.text = s.emailAddress;
    _purposeCtrl.text = s.purposeText;
  }

  @override
  void dispose() {
    _deliveryTimeCtrl.dispose();
    _emailCtrl.dispose();
    _purposeCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveNewsletter() async {
    final current =
        context.read<SettingsNotifier>().newsletter ?? const NewsletterSettings();
    final updated = current.copyWith(
      enabled: _enabled,
      frequency: _frequency,
      deliveryTime: _deliveryTimeCtrl.text.trim(),
      emailAddress: _emailCtrl.text.trim(),
      purposeText: _purposeCtrl.text.trim(),
      itemsPerNewsletter: _itemsPerNewsletter,
    );

    final error =
        await context.read<SettingsNotifier>().saveNewsletter(updated);
    if (!mounted) return;

    if (error != null) {
      AppToast.show(context, error, type: ToastType.error);
    } else {
      AppToast.show(context, 'Newsletter settings saved.', type: ToastType.success);
    }
  }

  String _providerLabel(String? provider) {
    switch (provider) {
      case 'google_drive':
        return 'Google Drive';
      case 'onedrive':
        return 'OneDrive';
      case 'dropbox':
        return 'Dropbox';
      case 'notion':
        return 'Notion';
      default:
        return provider ?? 'cloud storage';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primary = isDark ? AppColors.primaryDark : AppColors.primary;

    return Consumer<SettingsNotifier>(
      builder: (context, settings, _) {
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(32, 28, 32, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Settings',
                      style: GoogleFonts.libreBaskerville(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Manage your account, integrations, and preferences.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: isDark
                            ? AppColors.mutedForegroundDark
                            : AppColors.mutedForeground,
                      ),
                    ),
                  ],
                ),
              ),
              // Newsletter settings card
              Padding(
                padding: const EdgeInsets.fromLTRB(32, 0, 32, 16),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Newsletter',
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Personalise your automated knowledge digest.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: isDark
                                ? AppColors.mutedForegroundDark
                                : AppColors.mutedForeground,
                          ),
                        ),
                        const SizedBox(height: 16),
                        if (settings.isLoading)
                          const Center(child: CircularProgressIndicator())
                        else ...[
                          SwitchListTile(
                            value: _enabled,
                            onChanged: (v) => setState(() => _enabled = v),
                            title: const Text('Enable newsletter'),
                            subtitle: const Text(
                                'Receive your personalised digest by email'),
                            activeThumbColor: primary,
                            contentPadding: EdgeInsets.zero,
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Frequency',
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                                fontWeight: FontWeight.w500)),
                                    const SizedBox(height: 6),
                                    DropdownButtonFormField<String>(
                                      initialValue: _frequency,
                                      decoration: const InputDecoration(
                                          contentPadding: EdgeInsets.symmetric(
                                              horizontal: 12, vertical: 10)),
                                      items: const [
                                        DropdownMenuItem(
                                            value: 'daily',
                                            child: Text('Daily')),
                                        DropdownMenuItem(
                                            value: 'weekly',
                                            child: Text('Weekly')),
                                        DropdownMenuItem(
                                            value: 'weekdays',
                                            child: Text('Weekdays')),
                                      ],
                                      onChanged: (v) =>
                                          setState(() => _frequency = v!),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Delivery time (HH:MM)',
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                                fontWeight: FontWeight.w500)),
                                    const SizedBox(height: 6),
                                    TextField(
                                      controller: _deliveryTimeCtrl,
                                      decoration: const InputDecoration(
                                        hintText: '07:00',
                                        contentPadding: EdgeInsets.symmetric(
                                            horizontal: 12, vertical: 10),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Email address',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                      fontWeight: FontWeight.w500)),
                              const SizedBox(height: 6),
                              TextField(
                                controller: _emailCtrl,
                                keyboardType: TextInputType.emailAddress,
                                decoration: const InputDecoration(
                                    hintText: 'you@example.com'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Purpose / focus',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                      fontWeight: FontWeight.w500)),
                              const SizedBox(height: 4),
                              Text(
                                'Describe what you want to learn or achieve. The AI will weight content accordingly.',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: isDark
                                      ? AppColors.mutedForegroundDark
                                      : AppColors.mutedForeground,
                                ),
                              ),
                              const SizedBox(height: 6),
                              TextField(
                                controller: _purposeCtrl,
                                maxLines: 3,
                                decoration: const InputDecoration(
                                  hintText:
                                      'e.g. Help me connect ideas across philosophy readings…',
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Items per newsletter: $_itemsPerNewsletter',
                                style: theme.textTheme.bodySmall?.copyWith(
                                    fontWeight: FontWeight.w500),
                              ),
                              Slider(
                                value: _itemsPerNewsletter.toDouble(),
                                min: 1,
                                max: 20,
                                divisions: 19,
                                activeColor: primary,
                                label: '$_itemsPerNewsletter',
                                onChanged: (v) =>
                                    setState(() => _itemsPerNewsletter = v.round()),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          FilledButton(
                            onPressed: settings.isSaving ? null : _saveNewsletter,
                            style: FilledButton.styleFrom(
                                backgroundColor: primary),
                            child: settings.isSaving
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.white),
                                  )
                                : const Text('Save Newsletter Settings'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              // Data sources card
              Padding(
                padding: const EdgeInsets.fromLTRB(32, 0, 32, 16),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Connect Data Sources',
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Import content automatically from your favourite platforms.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: isDark
                                ? AppColors.mutedForegroundDark
                                : AppColors.mutedForeground,
                          ),
                        ),
                        const SizedBox(height: 16),
                        if (settings.isLoading)
                          const Center(child: CircularProgressIndicator())
                        else ...[
                          _IntegrationTile(
                            icon: Icons.drive_folder_upload_outlined,
                            iconColor: Colors.blue,
                            title: 'Google Drive',
                            provider: 'google_drive',
                            settings: settings,
                          ),
                          Divider(
                              height: 24,
                              color: isDark
                                  ? AppColors.borderDark
                                  : AppColors.borderLight),
                          _IntegrationTile(
                            icon: Icons.cloud_outlined,
                            iconColor: Colors.blueAccent,
                            title: 'OneDrive',
                            provider: 'onedrive',
                            settings: settings,
                          ),
                          Divider(
                              height: 24,
                              color: isDark
                                  ? AppColors.borderDark
                                  : AppColors.borderLight),
                          _IntegrationTile(
                            icon: Icons.folder_outlined,
                            iconColor: Colors.blueGrey,
                            title: 'Dropbox',
                            provider: 'dropbox',
                            settings: settings,
                          ),
                          Divider(
                              height: 24,
                              color: isDark
                                  ? AppColors.borderDark
                                  : AppColors.borderLight),
                          _IntegrationTile(
                            icon: Icons.note_outlined,
                            iconColor: Colors.black87,
                            title: 'Notion',
                            provider: 'notion',
                            settings: settings,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              // Privacy card
              Padding(
                padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Privacy & Security',
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Control how your data is used.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: isDark
                                ? AppColors.mutedForegroundDark
                                : AppColors.mutedForeground,
                          ),
                        ),
                        const SizedBox(height: 16),
                        SwitchListTile(
                          value: _allowTraining,
                          onChanged: (v) =>
                              setState(() => _allowTraining = v),
                          title: const Text('Allow AI Training'),
                          subtitle: const Text(
                              'Allow your anonymized data to improve AI models'),
                          activeThumbColor: primary,
                          contentPadding: EdgeInsets.zero,
                        ),
                        SwitchListTile(
                          value: _strictPrivacy,
                          onChanged: (v) =>
                              setState(() => _strictPrivacy = v),
                          title: const Text('Strict Privacy Mode'),
                          subtitle: const Text(
                              'Disable all external data sharing'),
                          activeThumbColor: primary,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── Integration tile ──────────────────────────────────────────────────────────

class _IntegrationTile extends StatefulWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String provider;
  final SettingsNotifier settings;

  const _IntegrationTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.provider,
    required this.settings,
  });

  @override
  State<_IntegrationTile> createState() => _IntegrationTileState();
}

class _IntegrationTileState extends State<_IntegrationTile> {
  bool _busy = false;

  Future<void> _onConnect() async {
    setState(() => _busy = true);
    final error = await widget.settings.connectProvider(widget.provider);
    if (!mounted) return;
    setState(() => _busy = false);
    if (error != null) {
      AppToast.show(context, error, type: ToastType.error);
    }
  }

  Future<void> _onDisconnect() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Disconnect ${widget.title}?'),
        content: Text(
            'This will stop automatic syncing from ${widget.title}. '
            'Your already-imported documents will remain.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    final error = await widget.settings.disconnectProvider(widget.provider);
    if (!mounted) return;
    setState(() => _busy = false);

    if (error != null) {
      AppToast.show(context, error, type: ToastType.error);
    } else {
      AppToast.show(
        context,
        '${widget.title} disconnected.',
        type: ToastType.info,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final connected = widget.settings.isConnected(widget.provider);
    final integration = widget.settings.integrationFor(widget.provider);

    String subtitle;
    if (connected && integration != null) {
      subtitle = integration.providerEmail != null
          ? '${integration.providerEmail} · ${integration.lastSyncLabel}'
          : integration.lastSyncLabel;
    } else {
      subtitle = 'Not connected';
    }

    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: widget.iconColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(widget.icon, color: widget.iconColor, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(widget.title,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w500)),
                  if (connected) ...[
                    const SizedBox(width: 6),
                    Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.green,
                      ),
                    ),
                  ],
                ],
              ),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: isDark
                      ? AppColors.mutedForegroundDark
                      : AppColors.mutedForeground,
                ),
              ),
            ],
          ),
        ),
        _busy
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : OutlinedButton(
                onPressed: connected ? _onDisconnect : _onConnect,
                style: OutlinedButton.styleFrom(
                  side: BorderSide(
                    color: connected
                        ? Colors.red.shade300
                        : (isDark
                            ? AppColors.borderDark
                            : AppColors.borderLight),
                  ),
                  foregroundColor: connected
                      ? Colors.red.shade400
                      : theme.colorScheme.onSurface,
                ),
                child: Text(connected ? 'Disconnect' : 'Connect'),
              ),
      ],
    );
  }
}
