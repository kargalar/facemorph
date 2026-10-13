import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/widgets/photo_image.dart';
import '../../../domain/models/daily_photo.dart';
import '../../app/app_view_model.dart';
import '../photo/photo_actions.dart';

class CalendarSection extends StatefulWidget {
  const CalendarSection({required this.viewModel, super.key});

  final AppViewModel viewModel;

  @override
  State<CalendarSection> createState() => _CalendarSectionState();
}

class _CalendarSectionState extends State<CalendarSection> {
  DateTime _focusedDay = DateTime.now();

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final photos = widget.viewModel.photos;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 16),
            child: TableCalendar<DailyPhoto>(
              locale: strings.locale.languageCode,
              firstDay: DateTime.utc(2020),
              lastDay: DateTime.now().add(const Duration(days: 365)),
              focusedDay: _focusedDay,
              availableCalendarFormats: const {CalendarFormat.month: 'Month'},
              headerStyle: const HeaderStyle(
                titleCentered: true,
                formatButtonVisible: false,
              ),
              calendarStyle: CalendarStyle(
                outsideDaysVisible: false,
                todayDecoration: BoxDecoration(
                  border: Border.all(
                    color: Theme.of(context).colorScheme.primary,
                    width: 2,
                  ),
                  shape: BoxShape.circle,
                ),
                todayTextStyle: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                markerDecoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  shape: BoxShape.circle,
                ),
              ),
              eventLoader: (day) => photos
                  .where((photo) => isSameDay(photo.capturedAt, day))
                  .toList(),
              onPageChanged: (day) => _focusedDay = day,
              calendarBuilders: CalendarBuilders(
                markerBuilder: (context, day, dayPhotos) {
                  if (dayPhotos.isEmpty) return null;
                  return Positioned.fill(
                    child: Padding(
                      padding: const EdgeInsets.all(3),
                      child: PhotoImage(
                        source: dayPhotos.first.source,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
        const SizedBox(height: 22),
        Text(
          strings.thisMonth,
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        if (photos.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 28),
            child: Center(child: Text(strings.noPhotos)),
          )
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: photos.length,
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 180,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 0.8,
            ),
            itemBuilder: (context, index) {
              final photo = photos[index];
              return InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => context.push('/photo', extra: photo),
                onLongPress: () => confirmAndDeletePhoto(
                  context: context,
                  viewModel: widget.viewModel,
                  photo: photo,
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    PhotoImage(
                      source: photo.source,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    Positioned(
                      left: 9,
                      bottom: 8,
                      child: Text(
                        DateFormat(
                          'd MMM',
                          strings.locale.languageCode,
                        ).format(photo.capturedAt),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          shadows: [Shadow(blurRadius: 8)],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }
}
