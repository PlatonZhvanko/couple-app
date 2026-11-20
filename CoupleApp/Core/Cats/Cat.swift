import SwiftUI

/// Три наших кота. Каждый отвечает за своё: Мироня — за настроение,
/// Хлоя — за питание, Гоша — за деньги.
enum Cat: String, CaseIterable, Identifiable {
    case miron
    case gosha
    case chloe

    var id: String { rawValue }

    var name: String {
        switch self {
        case .miron: "Мироня"
        case .gosha: "Гоша"
        case .chloe: "Хлоя"
        }
    }

    /// Во сколько раз кот меньше или больше «нормального» размера (Мироня большой, Хлоя маленькая).
    var sizeFactor: CGFloat {
        switch self {
        case .miron: 1.0
        case .gosha: 0.9
        case .chloe: 0.78
        }
    }

    /// Ширина головы относительно размера (Гоша худенький).
    var headWidth: CGFloat {
        switch self {
        case .miron: 0.94
        case .gosha: 0.74
        case .chloe: 0.84
        }
    }

    var fur: Color {
        switch self {
        case .miron: Color(red: 0.14, green: 0.13, blue: 0.14)
        case .gosha: Color(red: 0.18, green: 0.17, blue: 0.19)
        case .chloe: Color(red: 0.55, green: 0.57, blue: 0.63)
        }
    }

    var eyeColor: Color {
        switch self {
        case .miron: Color(red: 0.86, green: 0.68, blue: 0.2)
        case .gosha: Color(red: 0.62, green: 0.78, blue: 0.3)
        case .chloe: Color(red: 0.88, green: 0.55, blue: 0.14)
        }
    }

    static let cream = Color(red: 0.98, green: 0.95, blue: 0.9)
    static let peach = Color(red: 0.96, green: 0.73, blue: 0.52)
    static let nosePink = Color(red: 0.95, green: 0.6, blue: 0.64)
    static let outline = Color(red: 0.36, green: 0.25, blue: 0.22)
}

enum CatExpression {
    case normal
    case happy
}

/// Мультяшная мордочка кота, нарисованная фигурами SwiftUI.
struct CatAvatar: View {
    let cat: Cat
    var size: CGFloat = 80
    var expression: CatExpression = .normal
    /// Лапки внизу — чтобы кот «держался» за край экрана.
    var showPaws = false

    var body: some View {
        let headW = size * cat.headWidth
        let headH = size * 0.76
        let earW = size * 0.3
        let earH = size * (cat == .gosha ? 0.4 : 0.34)
        let lw = max(1.5, size * 0.03)

        ZStack {
            // уши
            CatEar().fill(cat.fur)
                .overlay(CatEar().stroke(Cat.outline, lineWidth: lw))
                .frame(width: earW, height: earH)
                .rotationEffect(.degrees(-14))
                .offset(x: -headW * 0.34, y: -headH * 0.5)
            CatEar().fill(cat.fur)
                .overlay(CatEar().stroke(Cat.outline, lineWidth: lw))
                .frame(width: earW, height: earH)
                .rotationEffect(.degrees(14))
                .offset(x: headW * 0.34, y: -headH * 0.5)
            CatEar().fill(Cat.nosePink.opacity(0.75))
                .frame(width: earW * 0.5, height: earH * 0.5)
                .rotationEffect(.degrees(-14))
                .offset(x: -headW * 0.34, y: -headH * 0.44)
            CatEar().fill(Cat.nosePink.opacity(0.75))
                .frame(width: earW * 0.5, height: earH * 0.5)
                .rotationEffect(.degrees(14))
                .offset(x: headW * 0.34, y: -headH * 0.44)

            // голова
            Ellipse().fill(cat.fur)
                .frame(width: headW, height: headH)
                .overlay(Ellipse().stroke(Cat.outline, lineWidth: lw))

            markings(headW: headW, headH: headH)

            // глаза
            eye(size: size).offset(x: -headW * 0.22, y: -headH * 0.06)
            eye(size: size).offset(x: headW * 0.22, y: -headH * 0.06)

            // щёчки
            Circle().fill(Cat.nosePink.opacity(0.45))
                .frame(width: size * 0.12, height: size * 0.12)
                .offset(x: -headW * 0.36, y: headH * 0.14)
            Circle().fill(Cat.nosePink.opacity(0.45))
                .frame(width: size * 0.12, height: size * 0.12)
                .offset(x: headW * 0.36, y: headH * 0.14)

            // носик и ротик
            Ellipse().fill(Cat.nosePink)
                .frame(width: size * 0.09, height: size * 0.065)
                .offset(y: headH * 0.12)
            CatMouth()
                .stroke(Cat.outline.opacity(0.9), style: StrokeStyle(lineWidth: lw * 0.8, lineCap: .round))
                .frame(width: size * 0.16, height: size * 0.07)
                .offset(y: headH * 0.25)

            if showPaws {
                paw.offset(x: -headW * 0.28, y: headH * 0.52)
                paw.offset(x: headW * 0.28, y: headH * 0.52)
            }
        }
        .frame(width: size, height: size)
    }

    @ViewBuilder
    private func markings(headW: CGFloat, headH: CGFloat) -> some View {
        switch cat {
        case .miron:
            // белая полоска на лбу и белая мордочка
            Capsule().fill(Cat.cream)
                .frame(width: headW * 0.12, height: headH * 0.42)
                .offset(y: -headH * 0.22)
            Ellipse().fill(Cat.cream)
                .frame(width: headW * 0.62, height: headH * 0.42)
                .offset(y: headH * 0.24)
        case .chloe:
            // рыжая «чёлка» на лбу и белая грудка
            Capsule().fill(Cat.peach)
                .frame(width: headW * 0.2, height: headH * 0.4)
                .offset(x: headW * 0.02, y: -headH * 0.24)
            Ellipse().fill(Cat.cream)
                .frame(width: headW * 0.36, height: headH * 0.22)
                .offset(y: headH * 0.36)
        case .gosha:
            EmptyView()
        }
    }

    @ViewBuilder
    private func eye(size: CGFloat) -> some View {
        switch expression {
        case .normal:
            ZStack {
                Ellipse().fill(cat.eyeColor)
                    .frame(width: size * 0.17, height: size * 0.2)
                Capsule().fill(Color.black)
                    .frame(width: size * 0.06, height: size * 0.15)
                Circle().fill(Color.white)
                    .frame(width: size * 0.05, height: size * 0.05)
                    .offset(x: size * 0.03, y: -size * 0.04)
            }
        case .happy:
            CatHappyEye()
                .stroke(Color.black.opacity(0.85), style: StrokeStyle(lineWidth: max(2, size * 0.04), lineCap: .round))
                .frame(width: size * 0.15, height: size * 0.08)
        }
    }

    private var paw: some View {
        Ellipse()
            .fill(cat == .miron ? Cat.cream : cat.fur)
            .frame(width: size * 0.24, height: size * 0.17)
            .overlay(Ellipse().stroke(Cat.outline, lineWidth: max(1.5, size * 0.03)))
    }
}

struct CatEar: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.midX, y: rect.minY),
                       control: CGPoint(x: rect.minX, y: rect.midY * 0.5))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY),
                       control: CGPoint(x: rect.maxX, y: rect.midY * 0.5))
        p.closeSubpath()
        return p
    }
}

struct CatMouth: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.4),
                       control: CGPoint(x: rect.minX + rect.width * 0.2, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY),
                       control: CGPoint(x: rect.maxX - rect.width * 0.2, y: rect.maxY))
        return p
    }
}

struct CatHappyEye: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY),
                       control: CGPoint(x: rect.midX, y: rect.minY - rect.height * 0.6))
        return p
    }
}
