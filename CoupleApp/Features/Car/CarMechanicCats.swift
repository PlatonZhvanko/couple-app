import SwiftUI

/// Реплики котов-механиков для раздела «Авто».
enum CarCatLines {
    enum Hint { case odometer, service, general }

    private static let service: [Cat: [String]] = [
        .miron: [
            "Не пора ли поменять масло? Я проверил, смотрю на вас.",
            "Масло, фильтры, колодки... Что у нас по ТО?",
            "Мрр. Лампочка на панели горит? Это не украшение.",
            "Хозяин, машина просит внимания. Тихо, но просит.",
            "Я бы заглянул под капот. Ну, если вы подержите.",
        ],
        .gosha: [
            "Чо как там по ремонту? Я всё записываю.",
            "Запчасти дорогие, а я считаю. Внесите траты!",
            "Шины скоро менять? Лучше заранее, чем в сугроб.",
            "Страховка и техосмотр не сами продлеваются, ага.",
            "Я бы проверил тормоза. Но у меня лапки.",
        ],
        .chloe: [
            "Пи-пи! Кто-то забыл про ТО?",
            "Я маленькая, но вижу: пора на сервис.",
            "Мойка! Машина грустная и грязная.",
            "Давление в шинах проверяли? Я бы проверила.",
            "Ключ на семнадцать? Я принесу. Потом.",
        ],
    ]

    private static let odometer: [Cat: [String]] = [
        .miron: [
            "Что-то ты давно не записывал пробег. Пора исправить?",
            "Пробег сам себя не запишет. Лапы у меня короткие.",
            "Сколько сейчас на одометре? Скажи мне, я запомню.",
        ],
        .gosha: [
            "Давно нет записей о пробеге. Я нервничаю, как бухгалтер.",
            "Заправка была? Запиши литры и пробег, я посчитаю расход.",
            "Без пробега я не вижу, сколько вы тратите на километр.",
        ],
        .chloe: [
            "Эй, не забыли про нас? Про пробег тоже!",
            "Цифры на панели, цифры в приложении. Давайте совпадём.",
            "Мур. Запишите пробег, и я спокойно посплю.",
        ],
    ]

    private static let general: [Cat: [String]] = [
        .miron: [
            "Добро пожаловать в гараж. Я тут за главного.",
            "Красивая у вас машина. Особенно сиденье для кота.",
            "Мрр. Давайте без поломок, ладно?",
        ],
        .gosha: [
            "Гаражный учёт: всё по порядку, чек к чеку.",
            "Сколько в этом месяце потратили на авто? Посмотрите итоги.",
            "Я уже надел каску. Что чиним?",
        ],
        .chloe: [
            "Я тут подержу гаечный ключ. Или поиграю с ним.",
            "Пи! Нашла болтик. Он не от вашей машины, не волнуйтесь.",
            "Можно я посижу на торпедо?",
        ],
    ]

    static func line(cat: Cat, hint: Hint) -> String {
        let list: [String]
        switch hint {
        case .odometer: list = odometer[cat] ?? []
        case .service: list = service[cat] ?? []
        case .general: list = general[cat] ?? []
        }
        let all = list.isEmpty ? ["Мяу!"] : list
        // чаще подходящая тема, иногда ТО
        return all.randomElement() ?? "Мяу!"
    }
}

/// Каска механика поверх мордочки кота.
private struct CarHardHat: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            UnevenRoundedRectangle(topLeadingRadius: size * 0.3, topTrailingRadius: size * 0.3)
                .fill(Color(red: 0.98, green: 0.78, blue: 0.2))
                .frame(width: size * 0.56, height: size * 0.24)
                .overlay(
                    Rectangle().fill(Color(red: 0.92, green: 0.62, blue: 0.12))
                        .frame(width: size * 0.07)
                )
                .offset(y: -size * 0.1)
            Capsule()
                .fill(Color(red: 0.92, green: 0.62, blue: 0.12))
                .frame(width: size * 0.74, height: size * 0.07)
        }
    }
}

/// Кот в костюме механика: каска, гаечный ключ.
struct CarMechanicCat: View {
    let cat: Cat
    let size: CGFloat

    var body: some View {
        ZStack {
            CatAvatar(cat: cat, size: size, expression: .happy, showPaws: true)
            CarHardHat(size: size)
                .offset(y: -size * 0.36)
            Image(systemName: "wrench.adjustable.fill")
                .font(.system(size: size * 0.24))
                .foregroundStyle(Color(red: 0.55, green: 0.58, blue: 0.62))
                .rotationEffect(.degrees(35))
                .offset(x: size * 0.36, y: size * 0.36)
        }
        .frame(width: size, height: size)
    }
}

/// Кот-механик выглядывает с края экрана и говорит реплику.
struct CarCatPeekView: View {
    let cat: Cat
    let edge: CatPeekEdge
    let message: String
    let position: Int
    var onDismiss: () -> Void

    private let baseSize: CGFloat = 96

    private var catView: some View {
        let s = baseSize * cat.sizeFactor
        let visible = s * 0.6
        return CarMechanicCat(cat: cat, size: s)
            .rotationEffect(.degrees(edge.rotation))
            .frame(width: s, height: s)
            .frame(
                width: (edge == .leading || edge == .trailing) ? visible : s,
                height: (edge == .top || edge == .bottom) ? visible : s,
                alignment: clipAlignment
            )
            .clipped()
    }

    private var clipAlignment: Alignment {
        switch edge {
        case .leading: .trailing
        case .trailing: .leading
        case .top: .bottom
        case .bottom: .top
        }
    }

    private var frameAlignment: Alignment {
        let h: HorizontalAlignment = position == 0 ? .leading : (position == 1 ? .center : .trailing)
        let v: VerticalAlignment = position == 0 ? .top : (position == 1 ? .center : .bottom)
        switch edge {
        case .leading: return Alignment(horizontal: .leading, vertical: v)
        case .trailing: return Alignment(horizontal: .trailing, vertical: v)
        case .top: return Alignment(horizontal: h, vertical: .top)
        case .bottom: return Alignment(horizontal: h, vertical: .bottom)
        }
    }

    private var bubble: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(cat.name) · механик")
                .font(.system(.caption, design: .rounded).weight(.bold))
                .foregroundStyle(Color(red: 0.8, green: 0.4, blue: 0.5))
            Text(message)
                .font(.system(.callout, design: .rounded).weight(.medium))
                .foregroundStyle(Color(red: 0.3, green: 0.2, blue: 0.18))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(red: 1.0, green: 0.96, blue: 0.92)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Cat.outline.opacity(0.5), lineWidth: 1.5))
        .frame(maxWidth: 230)
        .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
    }

    @ViewBuilder
    private var content: some View {
        switch edge {
        case .leading: HStack(spacing: 4) { catView; bubble }
        case .trailing: HStack(spacing: 4) { bubble; catView }
        case .top: VStack(spacing: 4) { catView; bubble }
        case .bottom: VStack(spacing: 4) { bubble; catView }
        }
    }

    var body: some View {
        content
            .contentShape(Rectangle())
            .onTapGesture { onDismiss() }
            .padding(.horizontal, (edge == .top || edge == .bottom) ? 16 : 0)
            .padding(.top, (edge == .leading || edge == .trailing) ? 110 : 0)
            .padding(.bottom, (edge == .leading || edge == .trailing) ? 130 : 0)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: frameAlignment)
            .task {
                try? await Task.sleep(for: .seconds(7))
                onDismiss()
            }
            .transition(.move(edge: edge.transitionEdge).combined(with: .opacity))
    }
}

private struct CarCatVisitModifier: ViewModifier {
    let hint: CarCatLines.Hint
    @Environment(CatPeekCenter.self) private var center

    func body(content: Content) -> some View {
        content.task {
            try? await Task.sleep(for: .seconds(2))
            let cat = Cat.allCases.randomElement() ?? .miron
            guard !Task.isCancelled, CatSettings.claim(cat) else { return }
            center.present(AnyView(
                CarCatPeekView(
                    cat: cat, edge: CatPeekEdge.allCases.randomElement() ?? .bottom,
                    message: CarCatLines.line(cat: cat, hint: hint), position: Int.random(in: 0...2)
                ) { center.dismiss() }
            ))
        }
    }
}

extension View {
    /// Кот-механик изредка выглядывает на экране «Авто» с репликой по теме.
    func carCatVisit(hint: CarCatLines.Hint) -> some View {
        modifier(CarCatVisitModifier(hint: hint))
    }
}
