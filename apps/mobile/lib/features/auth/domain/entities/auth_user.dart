class AuthUser {
  final String id;
  final String? name;
  final String? email;
  final String? photoUrl;

  AuthUser({
    required this.id,
    this.name,
    this.email,
    this.photoUrl,
  });
}