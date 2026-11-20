import SwiftUI

/// Мироня — большой чёрно-белый кот, отвечает в приложении за настроение.
/// Фразы выбираются по дню, поэтому подряд одна и та же почти не повторяется.
enum MoodMiron {
    static let questions: [String] = [
        "Как у тебя дела?",
        "Ну что, как прошёл твой день?",
        "Мур. Расскажешь, как ты сегодня?",
        "Присядь на минутку: как ты?",
        "Я весь день думал, как ты там.",
        "Как настроение? Только честно, я никому не скажу.",
        "Устала или устал? Расскажи Мироне.",
        "Давай подведём итог дня вместе?",
        "Хвост подрагивает: пора узнать, как у тебя дела.",
    ]

    static let reminders: [String] = [
        "Как у тебя дела? Заглянешь ко мне на минутку?",
        "Мур-мяу. Пора рассказать, как прошёл день.",
        "Я уже уселся рядом и жду твой итог дня.",
        "День почти закончился. Как ты, солнышко?",
        "Лапой по экрану: ответь, как настроение.",
        "Тихонько напоминаю: итог дня ждёт тебя.",
        "Мне интересно, как ты сегодня. Расскажешь?",
        "Мироня проверяет: всё ли хорошо?",
    ]

    static let allDone: [String] = [
        "Спасибо, что рассказал(а). Мур.",
        "Записал. Можно спокойно отдыхать.",
        "Итог дня на месте. Доброй ночи!",
    ]

    private static func pick(_ list: [String], on date: Date, shift: Int = 0) -> String {
        let day = Calendar.current.ordinality(of: .day, in: .era, for: date) ?? 0
        return list[(day + shift) % list.count]
    }

    static func question(for date: Date) -> String { pick(questions, on: date) }
    static func reminder(for date: Date) -> String { pick(reminders, on: date) }
    static func thanks(for date: Date) -> String { pick(allDone, on: date) }
}

/// Аватар Мирони: нарисованный кот в мягком круге.
struct MoodMironAvatar: View {
    var size: CGFloat = 44

    var body: some View {
        CatAvatar(cat: .miron, size: size * 0.9)
            .frame(width: size, height: size)
            .background(Circle().fill(Color.appBlush.opacity(0.25)))
    }
}
