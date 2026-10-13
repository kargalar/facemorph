import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/app_strings.dart';
import '../../app/app_view_model.dart';
import '../../core/app_shell.dart';
import '../calendar/calendar_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({required this.viewModel, super.key});

  final AppViewModel viewModel;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: ListenableBuilder(
      listenable: viewModel,
      builder: (context, _) {
        final strings = AppStrings.of(context);
        final user = viewModel.user;
        return ConstrainedPage(
          child: ListView(
            children: [
              Text(
                strings.profile,
                style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1.2,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  CircleAvatar(
                    radius: 34,
                    backgroundImage: user?.photoUrl != null
                        ? NetworkImage(user!.photoUrl!)
                        : null,
                    child: user?.photoUrl == null
                        ? const Icon(Icons.person_rounded, size: 34)
                        : null,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user?.displayName ?? '',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                  ),
                  IconButton.filledTonal(
                    tooltip: strings.settings,
                    onPressed: () => context.push('/settings'),
                    icon: const Icon(Icons.settings_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Text(
                strings.calendar,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              CalendarSection(viewModel: viewModel),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    ),
  );
}
