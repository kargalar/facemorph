class PublicUser {
  const PublicUser({
    required this.id,
    required this.displayName,
    required this.photoUrl,
    required this.isFollowing,
  });

  final String id;
  final String displayName;
  final String? photoUrl;
  final bool isFollowing;

  PublicUser copyWith({bool? isFollowing}) => PublicUser(
    id: id,
    displayName: displayName,
    photoUrl: photoUrl,
    isFollowing: isFollowing ?? this.isFollowing,
  );
}
