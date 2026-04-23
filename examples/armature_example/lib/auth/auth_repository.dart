abstract interface class AuthRepository {
  Future<String?> load();
  Future<void> save(String name);
  Future<void> clear();
}
