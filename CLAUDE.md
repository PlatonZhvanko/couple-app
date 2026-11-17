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
  - Два аккаунта: `CoupleMember.owner` / `.partner`. Кто вошёл: `@Environment(AccountStore.self)`,
    `account.current`, `account.myName`, `account.partnerName`. Вкладка только для одного:
    `Feature(..., availableFor: [.owner])`. Чья запись: поле `member: String` = `account.current.rawValue`.
  - `project.pbxproj` не редактировать: папки синхронизированы, новые файлы подхватываются сами.
    Не класть в `CoupleApp/` файлы `.md` и прочие не-ресурсы.
- Трекер прогресса (`progress/`) больше не ведётся: после изменений `progress/progress.json`
  и дашборд не обновлять (решение владельца, экономим токены).
