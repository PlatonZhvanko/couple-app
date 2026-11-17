# Правила проекта для Claude

- Общение с владельцем на русском, простыми словами. Владелец не профессиональный разработчик.
- Нативное iOS-приложение на SwiftUI + SwiftData, iOS 18+, Xcode 16+. Без платного
  Apple Developer: никаких CloudKit, push, App Groups и других платных возможностей.
- Без сторонних зависимостей, пока без них можно обойтись.
- Архитектура: `docs/architecture.md`. Главное:
  - Каждый раздел живёт только в `CoupleApp/Features/<Раздел>/`. Не трогать чужие разделы.
  - Регистрация раздела: одна строка в `CoupleApp/Core/Features/FeatureRegistry.swift`
    (уже есть для Planner, Nutrition, Sleep, Mood, Clients, Car).
  - Модели: `@Model final class`, у всех свойств значения по умолчанию, имена с префиксом
    раздела. Перечислить в `models` своего `Feature`.
  - Данные для второго телефона: реализовать `SyncableModel`, `recordKind` вида
    `"<раздел>.<тип>"`, вызывать `markChanged()` / `markDeleted()` и `sync.requestSync()`.
    Списки фильтровать по `deletedAt == nil`.
  - `project.pbxproj` не редактировать: папки синхронизированы, новые файлы подхватываются сами.
    Не класть в `CoupleApp/` файлы `.md` и прочие не-ресурсы.
