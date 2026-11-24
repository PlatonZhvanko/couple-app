import Foundation

/// Последнее полученное расписание «Олимпика» по дням: чтобы без интернета показать сохранённое.
enum PlannerOlimpicCache {
    private static func key(_ day: String) -> String { "planner.olimpic.cache.\(day)" }

    static func save(_ payload: PlannerOlimpicDay.Payload, key day: String) {
        guard let data = try? JSONEncoder().encode(payload) else { return }
        UserDefaults.standard.set(data, forKey: key(day))
    }

    static func load(_ day: String) -> PlannerOlimpicDay.Payload? {
        guard let data = UserDefaults.standard.data(forKey: key(day)) else { return nil }
        return try? JSONDecoder().decode(PlannerOlimpicDay.Payload.self, from: data)
    }
}
