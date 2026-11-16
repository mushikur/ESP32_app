import 'package:esp_iot/features/learn/learn_progress.dart';

class TestLearnStore implements LearnProgressStore {
  String? encoded;

  @override
  Future<LearnProgress> load() async {
    final saved = encoded;
    return saved == null ? const LearnProgress() : LearnProgress.decode(saved);
  }

  @override
  Future<void> save(LearnProgress progress) async =>
      encoded = progress.encode();
}
