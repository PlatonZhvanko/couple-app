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
    let text: String

    var body: some View {
        Text(text)
            .font(.system(.callout, design: .rounded).weight(.medium))
            .foregroundStyle(Color(red: 0.3, green: 0.2, blue: 0.18))
            .multilineTextAlignment(.leading)
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
    var duration: Double = 6
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

    @ViewBuilder
    private var content: some View {
        switch edge {
        case .leading:
            HStack(spacing: 4) { catView; CatBubble(text: message) }
        case .trailing:
            HStack(spacing: 4) { CatBubble(text: message); catView }
        case .top:
            VStack(spacing: 4) { catView; CatBubble(text: message) }
        case .bottom:
            VStack(spacing: 4) { CatBubble(text: message); catView }
        }
    }

    var body: some View {
        content
            .padding(.horizontal, (edge == .top || edge == .bottom) ? 16 : 0)
            .padding(.top, edge == .top ? 0 : (edge == .bottom ? 0 : 110))
            .padding(.bottom, edge == .bottom ? 49 : (edge == .top ? 0 : 130))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: frameAlignment)
            .contentShape(Rectangle())
            .onTapGesture { onDismiss() }
            .task {
                try? await Task.sleep(for: .seconds(duration))
                onDismiss()
            }
            .transition(.move(edge: edge.transitionEdge).combined(with: .opacity))
    }
}

private struct CatPeekModifier: ViewModifier {
    let cat: Cat
    let topic: CatTopic
    let message: String?
    let edge: CatPeekEdge?
    let duration: Double
    @Binding var isPresented: Bool

    func body(content: Content) -> some View {
        content.overlay {
            ZStack {
                if isPresented {
                    CatPeekView(
                        cat: cat,
                        edge: edge ?? CatPeekEdge.allCases.randomElement() ?? .bottom,
                        message: message ?? CatPhrases.random(for: cat, topic: topic),
                        position: Int.random(in: 0...2),
                        duration: duration
                    ) {
                        isPresented = false
                    }
                }
            }
            .animation(.spring(response: 0.55, dampingFraction: 0.7), value: isPresented)
            // Пустое место не перехватывает нажатия: нажимается только сам кот.
            .allowsHitTesting(isPresented)
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
        duration: Double = 6,
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
    let chance: Double
    let cooldown: TimeInterval
    @State private var show = false

    func body(content: Content) -> some View {
        content
            .catPeek(cat, topic: topic, isPresented: $show)
            .task {
                let key = "cat.lastVisit.\(cat.rawValue)"
                let last = UserDefaults.standard.double(forKey: key)
                let now = Date.now.timeIntervalSince1970
                guard now - last > cooldown, Double.random(in: 0...1) < chance else { return }
                try? await Task.sleep(for: .seconds(1.5))
                UserDefaults.standard.set(now, forKey: key)
                show = true
            }
    }
}

extension View {
    /// Кот изредка заглядывает при открытии экрана: не чаще, чем раз в `cooldown` секунд
    /// и не каждый раз (`chance` от 0 до 1).
    func catVisit(_ cat: Cat, topic: CatTopic, chance: Double = 0.7, cooldown: TimeInterval = 900) -> some View {
        modifier(CatVisitModifier(cat: cat, topic: topic, chance: chance, cooldown: cooldown))
    }
}
