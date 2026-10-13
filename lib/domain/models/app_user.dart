class AppUser {
  const AppUser({
    required this.id,
    required this.displayName,
    required this.email,
    required this.photoUrl,
    required this.isPublic,
    required this.trialStartedAt,
    this.premiumUntil,
  });

  final String id;
  final String displayName;
  final String email;
  final String? photoUrl;
  final bool isPublic;
  final DateTime trialStartedAt;
  final DateTime? premiumUntil;

  bool get isPremium =>
      premiumUntil != null && premiumUntil!.isAfter(DateTime.now());

  AppUser copyWith({bool? isPublic, DateTime? premiumUntil}) => AppUser(
    id: id,
    displayName: displayName,
    email: email,
    photoUrl: photoUrl,
    isPublic: isPublic ?? this.isPublic,
    trialStartedAt: trialStartedAt,
    premiumUntil: premiumUntil ?? this.premiumUntil,
  );
}
