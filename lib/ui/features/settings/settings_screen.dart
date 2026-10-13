import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../../../config/app_constants.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/utils/external_links.dart';
import '../../../data/services/notification_service.dart';
import '../../../data/services/theme_service.dart';
import '../../app/app_view_model.dart';
import '../../core/app_shell.dart';
import '../../core/settings_tile.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    required this.viewModel,
    required this.themeService,
    required this.notificationService,
    super.key,
  });

  final AppViewModel viewModel;
  final ThemeService themeService;
  final NotificationService notificationService;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late bool _remindersEnabled = widget.notificationService.enabled;
  late TimeOfDay _reminderTime = TimeOfDay(
    hour: widget.notificationService.reminderHour,
    minute: widget.notificationService.reminderMinute,
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(AppStrings.of(context).settings)),
    body: ListenableBuilder(
      listenable: Listenable.merge([widget.viewModel, widget.themeService]),
      builder: (context, _) {
        final strings = AppStrings.of(context);
        final user = widget.viewModel.user;
        final isDark = widget.themeService.mode == ThemeMode.dark;
        final reminderTime = MaterialLocalizations.of(
          context,
        ).formatTimeOfDay(_reminderTime);
        return ConstrainedPage(
          child: ListView(
            children: [
              _SectionTitle(strings.appearance),
              const SizedBox(height: 10),
              SettingsTile(
                icon: isDark
                    ? Icons.dark_mode_rounded
                    : Icons.light_mode_rounded,
                title: strings.darkMode,
                subtitle: isDark ? strings.dark : strings.light,
                trailing: Switch(
                  value: isDark,
                  onChanged: (value) => widget.themeService.setMode(
                    value ? ThemeMode.dark : ThemeMode.light,
                  ),
                ),
              ),
              const SizedBox(height: 26),
              _SectionTitle(strings.privacy),
              const SizedBox(height: 10),
              SettingsTile(
                icon: Icons.public_rounded,
                title: strings.publicPhotos,
                subtitle: strings.publicPhotosHint,
                trailing: Switch(
                  value: user?.isPublic ?? AppConstants.defaultPublicPhotos,
                  onChanged: user == null ? null : widget.viewModel.setPublic,
                ),
              ),
              const SizedBox(height: 12),
              SettingsTile(
                icon: Icons.notifications_active_outlined,
                title: strings.reminders,
                subtitle: strings.reminderHint(reminderTime),
                trailing: Switch(
                  value: _remindersEnabled,
                  onChanged: _setReminders,
                ),
              ),
              const SizedBox(height: 12),
              SettingsTile(
                icon: Icons.import_export_rounded,
                title: strings.photoTransfer,
                subtitle: strings.photoTransferHint,
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push('/transfer'),
              ),
              const SizedBox(height: 12),
              SettingsTile(
                icon: Icons.delete_sweep_rounded,
                title: strings.deleteAllPhotos,
                subtitle: strings.deleteAllPhotosHint,
                trailing: const Icon(Icons.delete_outline_rounded),
                onTap: widget.viewModel.busy || widget.viewModel.photos.isEmpty
                    ? null
                    : _confirmDeleteAllPhotos,
              ),
              if (widget.viewModel.isPremiumTestAccount) ...[
                const SizedBox(height: 26),
                _SectionTitle(strings.developerTools),
                const SizedBox(height: 10),
                SettingsTile(
                  icon: Icons.science_outlined,
                  title: strings.premiumTestMode,
                  subtitle: strings.premiumTestModeHint,
                  trailing: Switch(
                    value: widget.viewModel.premiumTestEnabled,
                    onChanged: widget.viewModel.setPremiumTestEnabled,
                  ),
                ),
              ],
              const SizedBox(height: 26),
              _PremiumCard(
                product: widget.viewModel.premiumProduct,
                busy: widget.viewModel.purchaseBusy,
                isPremium: widget.viewModel.entitlement?.isPremium ?? false,
                onBuy: _buyPremium,
                onRestore: _restorePurchases,
              ),
              const SizedBox(height: 26),
              _SectionTitle(strings.legal),
              const SizedBox(height: 10),
              SettingsTile(
                icon: Icons.privacy_tip_outlined,
                title: strings.privacyPolicy,
                subtitle: strings.privacyPolicy,
                trailing: const Icon(Icons.open_in_new_rounded),
                onTap: () => _openLink(AppConstants.privacyPolicyUrl),
              ),
              const SizedBox(height: 12),
              SettingsTile(
                icon: Icons.description_outlined,
                title: strings.termsOfUse,
                subtitle: strings.termsOfUse,
                trailing: const Icon(Icons.open_in_new_rounded),
                onTap: () => _openLink(AppConstants.termsOfUseUrl),
              ),
              const SizedBox(height: 12),
              SettingsTile(
                icon: Icons.manage_accounts_outlined,
                title: strings.accountDeletion,
                subtitle: strings.accountDeletionHint,
                trailing: const Icon(Icons.open_in_new_rounded),
                onTap: () => _openLink(AppConstants.accountDeletionUrl),
              ),
              const SizedBox(height: 30),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: widget.viewModel.busy
                          ? null
                          : widget.viewModel.signOut,
                      icon: const Icon(Icons.logout_rounded),
                      label: Text(strings.signOut),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: widget.viewModel.busy
                          ? null
                          : _confirmDeleteAccount,
                      icon: const Icon(Icons.delete_forever_rounded),
                      label: Text(strings.deleteAccount),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Center(
                child: Text(
                  'Version 1.0.0+1',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
            ],
          ),
        );
      },
    ),
  );

  Future<void> _setReminders(bool value) async {
    if (!value) {
      setState(() => _remindersEnabled = false);
      try {
        await widget.notificationService.cancelDaily();
      } catch (_) {
        if (mounted) setState(() => _remindersEnabled = true);
      }
      return;
    }

    final selectedTime = await showTimePicker(
      context: context,
      initialTime: _reminderTime,
    );
    if (!mounted || selectedTime == null) return;

    final previousTime = _reminderTime;
    setState(() {
      _remindersEnabled = true;
      _reminderTime = selectedTime;
    });
    final strings = AppStrings.of(context);
    try {
      await widget.notificationService.scheduleDaily(
        hour: selectedTime.hour,
        minute: selectedTime.minute,
        title: strings.appName,
        body: strings.reminderBody,
      );
    } catch (_) {
      if (mounted) {
        setState(() {
          _remindersEnabled = false;
          _reminderTime = previousTime;
        });
      }
    }
  }

  Future<void> _openLink(String url) async {
    if (await openExternalUrl(url) || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppStrings.of(context).linkOpenFailed)),
    );
  }

  Future<void> _confirmDeleteAccount() async {
    final strings = AppStrings.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(strings.deleteAccount),
        content: Text(strings.deleteAccountWarning),
        actions: [
          TextButton(
            onPressed: () => context.pop(false),
            child: Text(strings.cancel),
          ),
          FilledButton(
            onPressed: () => context.pop(true),
            child: Text(strings.deleteAccount),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    String? password;
    if (widget.viewModel.currentUserUsesPassword) {
      password = await _requestPassword(strings);
      if (password == null || !mounted) return;
    }
    try {
      await widget.viewModel.deleteAccount(password: password);
    } on FirebaseException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(strings.accountActionFailed(error.code))),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(strings.accountActionFailed('unknown'))),
        );
      }
    }
  }

  Future<void> _confirmDeleteAllPhotos() async {
    final strings = AppStrings.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(strings.deleteAllPhotos),
        content: Text(strings.deleteAllPhotosWarning),
        actions: [
          TextButton(
            onPressed: () => context.pop(false),
            child: Text(strings.cancel),
          ),
          FilledButton(
            onPressed: () => context.pop(true),
            child: Text(strings.deleteAllPhotos),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.viewModel.deleteAllPhotos();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(strings.deleteAllPhotosFailed)));
      }
    }
  }

  Future<String?> _requestPassword(AppStrings strings) async {
    final controller = TextEditingController();
    try {
      return await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(strings.password),
          content: TextField(
            controller: controller,
            autofocus: true,
            obscureText: true,
            decoration: InputDecoration(labelText: strings.password),
            onSubmitted: (_) => context.pop(controller.text),
          ),
          actions: [
            TextButton(
              onPressed: () => context.pop(),
              child: Text(strings.cancel),
            ),
            FilledButton(
              onPressed: () => context.pop(controller.text),
              child: Text(strings.deleteAccount),
            ),
          ],
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  Future<void> _buyPremium() async {
    if (widget.viewModel.premiumProduct == null ||
        widget.viewModel.purchaseBusy) {
      return;
    }
    try {
      final started = await widget.viewModel.buyPremium();
      if (!started && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppStrings.of(context).purchaseFailed)),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppStrings.of(context).purchaseFailed)),
        );
      }
    }
  }

  Future<void> _restorePurchases() async {
    if (widget.viewModel.purchaseBusy) return;
    try {
      await widget.viewModel.restorePurchases();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppStrings.of(context).purchaseFailed)),
        );
      }
    }
  }
}

class _PremiumCard extends StatelessWidget {
  const _PremiumCard({
    required this.product,
    required this.busy,
    required this.isPremium,
    required this.onBuy,
    required this.onRestore,
  });

  final ProductDetails? product;
  final bool busy;
  final bool isPremium;
  final VoidCallback onBuy;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.auto_awesome_rounded,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    strings.premium,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (isPremium)
                  Chip(
                    label: Text(strings.premiumActive),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(strings.premiumBenefits),
            const SizedBox(height: 4),
            Text(
              product?.price ?? strings.purchaseUnavailable,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: product == null || busy ? null : onBuy,
                child: busy
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(strings.subscribe),
              ),
            ),
            Center(
              child: TextButton(
                onPressed: busy ? null : onRestore,
                child: Text(strings.restorePurchases),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: Theme.of(
      context,
    ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
  );
}
