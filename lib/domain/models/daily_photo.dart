class DailyPhoto {
  const DailyPhoto({
    required this.id,
    required this.ownerId,
    required this.ownerName,
    required this.ownerAvatarUrl,
    required this.imageUrl,
    required this.capturedAt,
    required this.isPublic,
    required this.likeCount,
    this.isLiked = false,
    this.storagePath,
    this.localPath,
    this.isOwned = false,
  });

  final String id;
  final String ownerId;
  final String ownerName;
  final String? ownerAvatarUrl;
  final String imageUrl;
  final DateTime capturedAt;
  final bool isPublic;
  final int likeCount;
  final bool isLiked;
  final String? storagePath;
  final String? localPath;
  final bool isOwned;

  String get source => localPath ?? imageUrl;

  DailyPhoto copyWith({bool? isLiked, int? likeCount, String? localPath}) =>
      DailyPhoto(
        id: id,
        ownerId: ownerId,
        ownerName: ownerName,
        ownerAvatarUrl: ownerAvatarUrl,
        imageUrl: imageUrl,
        storagePath: storagePath,
        capturedAt: capturedAt,
        isPublic: isPublic,
        likeCount: likeCount ?? this.likeCount,
        isLiked: isLiked ?? this.isLiked,
        localPath: localPath ?? this.localPath,
        isOwned: isOwned,
      );
}
