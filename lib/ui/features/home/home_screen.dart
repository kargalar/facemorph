import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/widgets/photo_image.dart';
import '../../app/app_view_model.dart';
import '../../core/app_shell.dart';
import '../photo/photo_actions.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({required this.viewModel, super.key});

  final AppViewModel viewModel;

  @override
  Widget build(BuildContext context) => Scaffold(
    floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    floatingActionButton: ListenableBuilder(
      listenable: viewModel,
      builder: (context, _) {
        final strings = AppStrings.of(context);
        final canCapture = viewModel.entitlement?.canCapture ?? false;
        return FloatingActionButton(
          heroTag: 'capture-today',
          tooltip: strings.captureToday,
          onPressed: () {
            if (canCapture) {
              context.push('/capture');
            } else if (viewModel.entitlement?.isPremium == false) {
              _showPremiumOffer(context);
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(strings.captureUnavailable)),
              );
            }
          },
          child: Icon(
            canCapture ? Icons.camera_alt_rounded : Icons.check_rounded,
          ),
        );
      },
    ),
    body: ListenableBuilder(
      listenable: viewModel,
      builder: (context, _) {
        final strings = AppStrings.of(context);
        return ConstrainedPage(
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            DateFormat(
                              'EEEE, d MMMM',
                              strings.locale.languageCode,
                            ).format(DateTime.now()),
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            strings.today,
                            style: Theme.of(context).textTheme.headlineLarge
                                ?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -1.2,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
              SliverToBoxAdapter(
                child: Row(
                  children: [
                    Expanded(
                      child: _Metric(
                        value: '${viewModel.photos.length}',
                        label: strings.frames,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _Metric(
                        value: '${viewModel.streak}',
                        label: strings.streak,
                      ),
                    ),
                  ],
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 30)),
              SliverToBoxAdapter(
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        strings.yourJourney,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (viewModel.photos.length > 1)
                      TextButton.icon(
                        onPressed: () async {
                          await viewModel.ensureOwnPhotosLocal();
                          if (context.mounted) context.push('/preview');
                        },
                        icon: const Icon(Icons.play_circle_fill_rounded),
                        label: Text(strings.preview),
                      ),
                  ],
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 12)),
              if (viewModel.photos.isEmpty)
                SliverToBoxAdapter(
                  child: Container(
                    height: 150,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Text(
                        strings.noPhotos,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                )
              else
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 196,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: viewModel.photos.length.clamp(0, 12),
                      separatorBuilder: (_, _) => const SizedBox(width: 10),
                      itemBuilder: (context, index) {
                        final photo = viewModel.photos[index];
                        return SizedBox(
                          width: 142,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(22),
                            onTap: () => context.push('/photo', extra: photo),
                            onLongPress: () => confirmAndDeletePhoto(
                              context: context,
                              viewModel: viewModel,
                              photo: photo,
                            ),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                PhotoImage(
                                  source: photo.source,
                                  borderRadius: BorderRadius.circular(22),
                                ),
                                Positioned(
                                  left: 10,
                                  bottom: 9,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 9,
                                      vertical: 5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(
                                        alpha: 0.52,
                                      ),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      DateFormat(
                                        'd MMM',
                                        strings.locale.languageCode,
                                      ).format(photo.capturedAt),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 96)),
            ],
          ),
        );
      },
    ),
  );

  Future<void> _showPremiumOffer(BuildContext context) =>
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (_) => _PremiumOfferSheet(viewModel: viewModel),
      );
}

class _PremiumOfferSheet extends StatelessWidget {
  const _PremiumOfferSheet({required this.viewModel});

  final AppViewModel viewModel;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: ListenableBuilder(
      listenable: viewModel,
      builder: (context, _) {
        final strings = AppStrings.of(context);
        final product = viewModel.premiumProduct;
        final busy = viewModel.purchaseBusy;
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
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
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(strings.premiumBenefits),
              const SizedBox(height: 6),
              Text(
                product?.price ?? strings.purchaseUnavailable,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: product == null || busy
                      ? null
                      : () => _buy(context),
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
                  onPressed: busy ? null : () => _restore(context),
                  child: Text(strings.restorePurchases),
                ),
              ),
            ],
          ),
        );
      },
    ),
  );

  Future<void> _buy(BuildContext context) async {
    try {
      final started = await viewModel.buyPremium();
      if (!context.mounted) return;
      if (started) {
        Navigator.of(context).pop();
      } else {
        _showPurchaseError(context);
      }
    } catch (_) {
      if (context.mounted) _showPurchaseError(context);
    }
  }

  Future<void> _restore(BuildContext context) async {
    try {
      await viewModel.restorePurchases();
    } catch (_) {
      if (context.mounted) _showPurchaseError(context);
    }
  }

  void _showPurchaseError(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppStrings.of(context).purchaseFailed)),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(22),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          value,
          style: Theme.of(
            context,
          ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(label),
          ),
        ),
      ],
    ),
  );
}
