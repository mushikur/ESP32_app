import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract interface class OnboardingStore {
  Future<bool> isComplete();
  Future<void> markComplete();
}

class _LocalOnboardingStore implements OnboardingStore {
  static const _completionKey = 'onboarding_completed_v1';
  final _preferences = SharedPreferencesAsync();

  @override
  Future<bool> isComplete() async =>
      await _preferences.getBool(_completionKey) ?? false;

  @override
  Future<void> markComplete() => _preferences.setBool(_completionKey, true);
}

final onboardingStoreProvider = Provider<OnboardingStore>(
  (ref) => _LocalOnboardingStore(),
);

final onboardingCompleteProvider = FutureProvider<bool>((ref) async {
  try {
    return await ref.watch(onboardingStoreProvider).isComplete();
  } on Exception {
    return false;
  }
});
