import SwiftUI

/// С какого края экрана выглядывает кот.
enum CatPeekEdge: CaseIterable {
    case leading, trailing, top, bottom

    /// Поворот кота: лапки всегда у края экрана.
    var rotation: Double {
        switch self {
        case .leading: 90
        case .trailing: -90
        case .top: 180
        case .bottom: 0
        }
    }

    var transitionEdge: Edge {
        switch self {
        case .leading: .leading
        case .trailing: .trailing
        case .top: .top
        case .bottom: .bottom
        }
    }
}

/// Облачко с репликой.
struct CatBubble: View {
    var cat: Cat? = nil
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let cat {
                Text("\(cat.name) · \(cat.roleTitle)")
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .foregroundStyle(Color(red: 0.8, green: 0.4, blue: 0.5))
            }
            Text(text)
                .font(.system(.callout, design: .rounded).weight(.medium))
                .foregroundStyle(Color(red: 0.3, green: 0.2, blue: 0.18))
                .multilineTextAlignment(.leading)
        }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(red: 1.0, green: 0.96, blue: 0.92))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Cat.outline.opacity(0.5), lineWidth: 1.5)
            )
            .frame(maxWidth: 230)
            .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
    }
}

/// Кот, выглядывающий из-за края экрана, с облачком реплики.
struct CatPeekView: View {
    let cat: Cat
    let edge: CatPeekEdge
    let message: String
    let position: Int // 0, 1 или 2: где вдоль края
    var duration: Double = 8
    /// Если задано, кот выглядывает сбоку на этой высоте экрана: рядом с нужным блоком.
    var anchorY: CGFloat? = nil
    var onDismiss: () -> Void

    private let catSize: CGFloat = 96

    private var catView: some View {
        let s = catSize * cat.sizeFactor
        let hidden = s * 0.4
        let visible = s - hidden
        return CatAvatar(cat: cat, size: s, expression: .normal, showPaws: true)
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

    private var sideTopPadding: CGFloat {
        guard edge == .leading || edge == .trailing else { return 0 }
        if let anchorY { return max(70, anchorY - 50) }
        return 110
    }

    private var anchoredAlignment: Alignment {
        guard anchorY != nil else { return frameAlignment }
        return edge == .leading ? .topLeading : .topTrailing
    }

    @ViewBuilder
    private var content: some View {
        switch edge {
        case .leading:
            HStack(spacing: 4) { catView; CatBubble(cat: cat, text: message) }
        case .trailing:
            HStack(spacing: 4) { CatBubble(cat: cat, text: message); catView }
        case .top:
            VStack(spacing: 4) { catView; CatBubble(cat: cat, text: message) }
        case .bottom:
            VStack(spacing: 4) { CatBubble(cat: cat, text: message); catView }
        }
    }

    var body: some View {
        content
            .contentShape(Rectangle())
            .onTapGesture { onDismiss() }
            .padding(.horizontal, (edge == .top || edge == .bottom) ? 16 : 0)
            .padding(.top, sideTopPadding)
            .padding(.bottom, (edge == .leading || edge == .trailing) && anchorY == nil ? 130 : 0)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: anchoredAlignment)
            .task {
                try? await Task.sleep(for: .seconds(duration))
                onDismiss()
            }
            .transition(.move(edge: edge.transitionEdge).combined(with: .opacity))
    }
}

/// Общий «показыватель» котов: один на всё приложение. Кот всегда выезжает от настоящего
/// края экрана (сверху, снизу, слева или справа), а не из середины раздела.
@Observable
@MainActor
final class CatPeekCenter {
    var current: AnyView?
    var token = UUID()
    /// Высота (на экране) блока, рядом с которым коту логично показаться. Ставится `.catAnchor()`.
    var anchorY: CGFloat?

    func present(_ view: AnyView) {
        token = UUID()
        current = view
    }

    func dismiss() {
        current = nil
    }

    func show(
        _ cat: Cat, topic: CatTopic, message: String? = nil, edge: CatPeekEdge? = nil,
        duration: Double = 8, anchorY: CGFloat? = nil
    ) {
        let e: CatPeekEdge
        if anchorY != nil {
            e = Bool.random() ? .leading : .trailing
        } else {
            e = edge ?? CatPeekEdge.allCases.randomElement() ?? .bottom
        }
        let text = message ?? CatPhrases.random(for: cat, topic: topic)
        present(AnyView(
            CatPeekView(cat: cat, edge: e, message: text, position: Int.random(in: 0...2),
                        duration: duration, anchorY: anchorY) { [weak self] in
                self?.dismiss()
            }
        ))
    }
}

/// Единые настройки частоты появления котов. Менять числа здесь: работает для всех разделов.
enum CatSettings {
    /// Один и тот же кот в одном разделе и одной теме не чаще, чем раз в столько секунд (30 минут).
    static let visitCooldown: TimeInterval = 30 * 60
    /// Вероятность, что при заходе в раздел кот выглянет, если время пришло.
    static let visitChance = 0.8
    /// Между появлениями любых котов проходит не меньше этого времени (4 минуты).
    static let gapBetweenAnyCats: TimeInterval = 4 * 60
    /// Мироня здоровается при запуске не чаще, чем раз в столько секунд (3 часа).
    static let greetingCooldown: TimeInterval = 3 * 3600
    /// Сколько секунд кот остаётся на экране.
    static let displaySeconds: Double = 8

    /// Проверяет, можно ли коту показаться сейчас, и если да, запоминает время показа.
    /// `scope` — раздел и тема (например `"nutrition.food"`): у каждого кота в каждом разделе
    /// и теме свой отсчёт времени. Свои `cooldown` меньше 30 минут не действуют.
    static func claim(_ cat: Cat, scope: String, chance: Double? = nil, cooldown: TimeInterval? = nil) -> Bool {
        let defaults = UserDefaults.standard
        let now = Date.now.timeIntervalSince1970
        let catKey = "cat.lastVisit.\(cat.rawValue).\(scope)"
        let anyKey = "cat.lastAnyVisit"
        guard now - defaults.double(forKey: catKey) > max(cooldown ?? visitCooldown, visitCooldown),
              now - defaults.double(forKey: anyKey) > gapBetweenAnyCats,
              Double.random(in: 0...1) < (chance ?? visitChance)
        else { return false }
        defaults.set(now, forKey: catKey)
        defaults.set(now, forKey: anyKey)
        return true
    }
}

private struct CatPeekModifier: ViewModifier {
    let cat: Cat
    let topic: CatTopic
    let message: String?
    let edge: CatPeekEdge?
    let duration: Double
    @Binding var isPresented: Bool
    @Environment(CatPeekCenter.self) private var center: CatPeekCenter?

    func body(content: Content) -> some View {
        content.onChange(of: isPresented, initial: true) { _, shown in
            guard shown else { return }
            center?.show(cat, topic: topic, message: message, edge: edge, duration: duration)
            isPresented = false
        }
    }
}

extension View {
    /// Кот выглядывает с края экрана и говорит случайную реплику на тему `topic`.
    /// Край выбирается случайно, если не указан. Нажатие на кота прячет его.
    ///
    /// Пример: `.catPeek(.chloe, topic: .food, isPresented: $showChloe)`
    func catPeek(
        _ cat: Cat,
        topic: CatTopic,
        message: String? = nil,
        edge: CatPeekEdge? = nil,
        duration: Double = 8,
        isPresented: Binding<Bool>
    ) -> some View {
        modifier(CatPeekModifier(
            cat: cat, topic: topic, message: message,
            edge: edge, duration: duration, isPresented: isPresented
        ))
    }
}

private struct CatVisitModifier: ViewModifier {
    let cat: Cat
    let topic: CatTopic
    let chance: Double?
    let cooldown: TimeInterval?
    var scope: String
    var messages: [String] = []
    @Environment(CatPeekCenter.self) private var center: CatPeekCenter?

    func body(content: Content) -> some View {
        content.task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled, CatSettings.claim(cat, scope: scope, chance: chance, cooldown: cooldown) else { return }
            // Иногда кот выглядывает рядом с нужным блоком экрана, иногда просто от края.
            let anchor = Bool.random() ? center?.anchorY : nil
            center?.show(cat, topic: topic, message: messages.randomElement(),
                        duration: CatSettings.displaySeconds, anchorY: anchor)
        }
    }
}

private struct CatAnchorModifier: ViewModifier {
    @Environment(CatPeekCenter.self) private var center: CatPeekCenter?

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.frame(in: .global).midY
            } action: { y in
                center?.anchorY = y
            }
            .onDisappear { center?.anchorY = nil }
    }
}

extension View {
    /// Помечает блок, рядом с которым коту логично показаться с темой этого экрана.
    func catAnchor() -> some View { modifier(CatAnchorModifier()) }
}

extension View {
    /// Кот заглядывает при открытии экрана. Частота задаётся в `CatSettings`;
    /// `section` — название раздела (у каждого кота в каждом разделе и теме свой отсчёт 30 минут).
    func catVisit(
        _ cat: Cat, topic: CatTopic, section: String = "", chance: Double? = nil, cooldown: TimeInterval? = nil,
        messages: [String] = []
    ) -> some View {
        modifier(CatVisitModifier(
            cat: cat, topic: topic, chance: chance, cooldown: cooldown,
            scope: "\(section).\(topic.rawValue)", messages: messages
        ))
    }
}
