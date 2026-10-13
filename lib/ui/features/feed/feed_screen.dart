import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../config/app_constants.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/widgets/photo_image.dart';
import '../../../domain/models/daily_photo.dart';
import '../../../domain/models/public_user.dart';
import '../../app/app_view_model.dart';

class FeedScreen extends StatelessWidget {
  const FeedScreen({required this.viewModel, super.key});

  final AppViewModel viewModel;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: AppConstants.maxContentWidth,
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: DefaultTabController(
              length: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppStrings.of(context).explore,
                    style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1.2,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    AppStrings.of(context).feedSubtitle,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TabBar(
                    tabs: [
                      Tab(text: AppStrings.of(context).friends),
                      Tab(text: AppStrings.of(context).global),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListenableBuilder(
                      listenable: viewModel,
                      builder: (context, _) => TabBarView(
                        children: [
                          _PostsView(
                            viewModel: viewModel,
                            posts: viewModel.friendsFeed,
                            users: viewModel.publicUsers,
                            emptyText: AppStrings.of(context).noFriendsFeed,
                          ),
                          _PostsView(
                            viewModel: viewModel,
                            posts: viewModel.feed,
                            users: viewModel.publicUsers,
                            emptyText: AppStrings.of(context).noFeed,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _PostsView extends StatelessWidget {
  const _PostsView({
    required this.viewModel,
    required this.posts,
    required this.users,
    required this.emptyText,
  });

  final AppViewModel viewModel;
  final List<DailyPhoto> posts;
  final List<PublicUser> users;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final suggestedUsers = users
        .where((user) => user.id != viewModel.user?.id)
        .toList();
    return CustomScrollView(
      slivers: [
        if (suggestedUsers.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    strings.discoverPeople,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 112,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: suggestedUsers.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 10),
                      itemBuilder: (context, index) => _UserCard(
                        user: suggestedUsers[index],
                        onFollow: () =>
                            _toggleFollow(context, suggestedUsers[index].id),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (posts.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: Text(emptyText)),
          )
        else
          SliverList.separated(
            itemCount: posts.length,
            separatorBuilder: (_, _) => const SizedBox(height: 18),
            itemBuilder: (context, index) => _PhotoCard(
              photo: posts[index],
              isFollowing: viewModel.isFollowing(posts[index].ownerId),
              onFollow: posts[index].ownerId == viewModel.user?.id
                  ? null
                  : () => _toggleFollow(context, posts[index].ownerId),
              onLike: () => viewModel.toggleLike(posts[index].id),
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }

  Future<void> _toggleFollow(BuildContext context, String userId) async {
    try {
      await viewModel.toggleFollow(userId);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppStrings.of(context).followFailed)),
        );
      }
    }
  }
}

class _UserCard extends StatelessWidget {
  const _UserCard({required this.user, required this.onFollow});

  final PublicUser user;
  final VoidCallback onFollow;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 160,
    child: Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            CircleAvatar(
              radius: 19,
              backgroundImage: user.photoUrl == null
                  ? null
                  : NetworkImage(user.photoUrl!),
              child: user.photoUrl == null
                  ? const Icon(Icons.person_rounded, size: 19)
                  : null,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    user.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 3),
                  SizedBox(
                    height: 27,
                    child: TextButton(
                      onPressed: onFollow,
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        alignment: Alignment.centerLeft,
                      ),
                      child: Text(
                        user.isFollowing
                            ? AppStrings.of(context).following
                            : AppStrings.of(context).follow,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _PhotoCard extends StatelessWidget {
  const _PhotoCard({
    required this.photo,
    required this.isFollowing,
    required this.onFollow,
    required this.onLike,
  });

  final DailyPhoto photo;
  final bool isFollowing;
  final VoidCallback? onFollow;
  final VoidCallback onLike;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 10),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundImage: photo.ownerAvatarUrl != null
                      ? NetworkImage(photo.ownerAvatarUrl!)
                      : null,
                  child: photo.ownerAvatarUrl == null
                      ? const Icon(Icons.person_rounded)
                      : null,
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        photo.ownerName,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        DateFormat(
                          'd MMMM • HH:mm',
                          strings.locale.languageCode,
                        ).format(photo.capturedAt),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (onFollow != null)
                  TextButton(
                    onPressed: onFollow,
                    child: Text(
                      isFollowing ? strings.following : strings.follow,
                    ),
                  ),
              ],
            ),
          ),
          AspectRatio(
            aspectRatio: 4 / 5,
            child: PhotoImage(source: photo.source),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 7, 16, 12),
            child: Row(
              children: [
                IconButton(
                  onPressed: onLike,
                  icon: Icon(
                    photo.isLiked
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                  ),
                  color: photo.isLiked ? const Color(0xFFFF375F) : null,
                ),
                Text(
                  '${photo.likeCount}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                const Icon(Icons.public_rounded, size: 17),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
