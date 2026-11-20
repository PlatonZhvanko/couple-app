import SwiftUI

/// Реплики котов в разделе «Питомцы»: просят внимания, игрушек, прививок.
enum PetsCatLines {
    private static let lines: [Cat: [String]] = [
        .miron: [
            "Не забыли про нас? Мы тут, пушистые и важные.",
            "Может, пора сделать прививку? Я готов. Почти.",
            "Мы хотим новых игрушек! Мышки уже не те.",
            "Когти бы подстричь, а то диван жалуется.",
            "Расчёска! Но только если нежно.",
            "Миска наполовину пуста. Это тревожно.",
        ],
        .gosha: [
            "Вы нас не забыли? Я худенький, мне надо кушать.",
            "Давно были у ветеринара? Запишите визит.",
            "Я бы поиграл. С верёвочкой. И с вами.",
            "Лоток чистый? Это важно для нашего настроения.",
            "Мы хотим лежанку помягче, и без обсуждений.",
            "Напомните про обработку от блох, пожалуйста.",
        ],
        .chloe: [
            "Мяу! Не забыли про нас?",
            "Новые игрушки! Пожалуйста! Лапками прошу!",
            "Может, пора на прививку? Я смелая, правда.",
            "Хочу на ручки. И вкусняшку. Желательно вместе.",
            "Взвесьте меня! Я, кажется, подросла.",
            "Мур-мур. Поиграйте со мной, а?",
        ],
    ]

    static func line(for cat: Cat) -> String {
        let list = lines[cat] ?? ["Мяу!"]
        let key = "pets.catLine.\(cat.rawValue)"
        let last = UserDefaults.standard.integer(forKey: key) - 1
        var index = Int.random(in: 0..<list.count)
        if list.count > 1 && index == last { index = (index + 1) % list.count }
        UserDefaults.standard.set(index + 1, forKey: key)
        return list[index]
    }
}

private struct PetsCatVisitModifier: ViewModifier {
    @State private var show = false
    @State private var cat: Cat = .miron
    @State private var line = ""

    func body(content: Content) -> some View {
        content
            .catPeek(cat, topic: .greeting, message: line, duration: 7, isPresented: $show)
            .task {
                // не чаще раза в 20 минут и не при каждом заходе
                let key = "pets.catVisit.last"
                let last = UserDefaults.standard.double(forKey: key)
                let now = Date.now.timeIntervalSince1970
                guard now - last > 20 * 60, Double.random(in: 0...1) < 0.7 else { return }
                try? await Task.sleep(for: .seconds(2))
                UserDefaults.standard.set(now, forKey: key)
                cat = Cat.allCases.randomElement() ?? .miron
                line = PetsCatLines.line(for: cat)
                show = true
            }
    }
}

extension View {
    /// Кот изредка выглядывает на экране «Питомцы» и просит внимания.
    func petsCatVisit() -> some View { modifier(PetsCatVisitModifier()) }
}
