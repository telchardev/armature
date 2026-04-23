abstract interface class NightModeRepository {
  Future<bool> load();
  Future<void> save(bool enabled);
}
