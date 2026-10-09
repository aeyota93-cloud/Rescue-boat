import 'package:hiddify/features/profile/data/profile_repository.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';

/// Шлюпка: переименовать подписку без скачивания — как «Изменить» в Hiddify: имя кладётся
/// в userOverride, конфиг перечитывается с диска. Возвращает текст ошибки или null.
Future<String?> renameProfile(ProfileRepository repo, ProfileEntity profile, String name) async {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return 'Имя не может быть пустым';
  final raw = await repo.getRawConfig(profile.id).run();
  final content = raw.toNullable();
  if (content == null) return 'Не удалось прочитать конфиг подписки';
  final override = (profile.userOverride ?? const UserOverride()).copyWith(name: trimmed);
  final result = await repo.offlineUpdate(profile.copyWith(userOverride: override), content).run();
  return result.match((failure) => 'Не удалось переименовать: $failure', (_) => null);
}
