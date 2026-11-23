import SwiftUI

/// Четыре наших кота. Каждый отвечает за своё: Мироня — за настроение,
/// Хлоя — за питание, Гоша — за деньги, Миса — за планер и общие дела.
enum Cat: String, CaseIterable, Identifiable {
    case miron
    case gosha
    case chloe
    case misa

    var id: String { rawValue }

    var name: String {
        switch self {
        case .miron: "Мироня"
        case .gosha: "Гоша"
        case .chloe: "Хлоя"
        case .misa: "Миса"
        }
    }

    /// За что отвечает кот.
    var roleTitle: String {
        switch self {
        case .miron: "про настроение"
        case .gosha: "про деньги"
        case .chloe: "про еду"
        case .misa: "про планер и общие дела"
        }
    }

    /// Во сколько раз кот меньше или больше «нормального» размера (Мироня большой, Хлоя маленькая).
    var sizeFactor: CGFloat {
        switch self {
        case .miron: 1.0
        case .gosha: 0.9
        case .chloe: 0.78
        case .misa: 0.82
        }
    }

    /// Ширина головы относительно размера (Гоша худенький).
    var headWidth: CGFloat {
        switch self {
        case .miron: 0.94
        case .gosha: 0.74
        case .chloe: 0.84
        case .misa: 0.9
        }
    }

    var fur: Color {
        switch self {
        case .miron: Color(red: 0.14, green: 0.13, blue: 0.14)
        case .gosha: Color(red: 0.18, green: 0.17, blue: 0.19)
        case .chloe: Color(red: 0.55, green: 0.57, blue: 0.63)
        case .misa: Color(red: 0.84, green: 0.72, blue: 0.56)
        }
    }

    var furLight: Color {
        switch self {
        case .miron: Color(red: 0.34, green: 0.32, blue: 0.33)
        case .gosha: Color(red: 0.27, green: 0.26, blue: 0.29)
        case .chloe: Color(red: 0.66, green: 0.68, blue: 0.74)
        case .misa: Color(red: 0.93, green: 0.84, blue: 0.70)
        }
    }

    var eyeColor: Color {
        switch self {
        case .miron: Color(red: 0.8, green: 0.6, blue: 0.16)
        case .gosha: Color(red: 0.62, green: 0.78, blue: 0.3)
        case .chloe: Color(red: 0.88, green: 0.55, blue: 0.14)
        case .misa: Color(red: 0.40, green: 0.56, blue: 0.30)
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

/// Мордочка кота, нарисованная фигурами SwiftUI: у каждого кота свой окрас, как в жизни.
struct CatAvatar: View {
    let cat: Cat
    var size: CGFloat = 80
    var expression: CatExpression = .normal
    /// Лапки внизу — чтобы кот «держался» за край экрана.
    var showPaws = false

    var body: some View {
        let headW = size * cat.headWidth
        let headH = size * 0.76
        let lw = max(1.2, size * 0.022)

        ZStack {
            // белая грудка за головой
            Ellipse().fill(Cat.cream)
                .frame(width: headW * 0.5, height: headH * 0.5)
                .offset(y: headH * 0.52)
            ears(headW: headW, headH: headH, lw: lw)

            // голова с мягким объёмом
            Ellipse()
                .fill(RadialGradient(colors: [cat.furLight, cat.fur],
                                     center: .init(x: 0.5, y: 0.35),
                                     startRadius: 0, endRadius: headW * 0.65))
                .frame(width: headW, height: headH)
                .overlay(Ellipse().stroke(Cat.outline.opacity(0.85), lineWidth: lw))

            markings(headW: headW, headH: headH)

            // глаза
            eye(left: true).offset(x: -headW * 0.23, y: -headH * 0.07)
            eye(left: false).offset(x: headW * 0.23, y: -headH * 0.07)

            // носик, ротик, усы
            Ellipse().fill(Cat.nosePink)
                .frame(width: size * 0.085, height: size * 0.06)
                .offset(y: headH * 0.13)
            CatMouth()
                .stroke(Cat.outline.opacity(0.9), style: StrokeStyle(lineWidth: lw * 0.8, lineCap: .round))
                .frame(width: size * 0.15, height: size * 0.06)
                .offset(y: headH * 0.25)
            Whiskers()
                .stroke(Color.white.opacity(0.75), style: StrokeStyle(lineWidth: max(1, lw * 0.5), lineCap: .round))
                .frame(width: headW * 1.25, height: headH * 0.3)
                .offset(y: headH * 0.2)

            if showPaws {
                paw.offset(x: -headW * 0.28, y: headH * 0.55)
                paw.offset(x: headW * 0.28, y: headH * 0.55)
            }
        }
        .frame(width: size, height: size)
    }

    private func ears(headW: CGFloat, headH: CGFloat, lw: CGFloat) -> some View {
        let earW = size * 0.3
        let earH = size * (cat == .gosha ? 0.42 : 0.34)
        return ZStack {
            ForEach([-1.0, 1.0], id: \.self) { side in
                ZStack {
                    CatEar().fill(cat.fur)
                        .overlay(CatEar().stroke(Cat.outline.opacity(0.85), lineWidth: lw))
                        .frame(width: earW, height: earH)
                    CatEar().fill(Cat.nosePink.opacity(0.7))
                        .frame(width: earW * 0.5, height: earH * 0.52)
                        .offset(y: earH * 0.2)
                }
                .rotationEffect(.degrees(side * 14))
                .offset(x: CGFloat(side) * headW * 0.34, y: -headH * 0.48)
            }
        }
    }

    @ViewBuilder
    private func markings(headW: CGFloat, headH: CGFloat) -> some View {
        switch cat {
        case .miron:
            // тёмный кот с белой мордочкой и белой полоской на носу
            Capsule().fill(Cat.cream)
                .frame(width: headW * 0.13, height: headH * 0.42)
                .offset(y: -headH * 0.1)
            Ellipse().fill(Cat.cream)
                .frame(width: headW * 0.6, height: headH * 0.4)
                .offset(y: headH * 0.25)
            // полоски на лбу
            ForEach([-1.0, 0.0, 1.0], id: \.self) { i in
                Capsule().fill(Color.black.opacity(0.35))
                    .frame(width: headW * 0.035, height: headH * 0.14)
                    .rotationEffect(.degrees(i * 14))
                    .offset(x: CGFloat(i) * headW * 0.1, y: -headH * 0.36)
            }
        case .chloe:
            // рыжие пятна на лбу и щеке, белая мордочка
            Ellipse().fill(Cat.peach)
                .frame(width: headW * 0.24, height: headH * 0.36)
                .rotationEffect(.degrees(12))
                .offset(x: headW * 0.0, y: -headH * 0.3)
            Ellipse().fill(Cat.peach.opacity(0.9))
                .frame(width: headW * 0.2, height: headH * 0.2)
                .offset(x: -headW * 0.3, y: headH * 0.12)
            Ellipse().fill(Cat.cream)
                .frame(width: headW * 0.36, height: headH * 0.24)
                .offset(y: headH * 0.33)
        case .misa:
            // кремовая атлантика с мягкими тенями на лбу и светлой мордочкой
            ForEach([-1.0, 0.0, 1.0], id: \.self) { i in
                Capsule().fill(Color(red: 0.66, green: 0.52, blue: 0.38).opacity(0.5))
                    .frame(width: headW * 0.035, height: headH * 0.15)
                    .rotationEffect(.degrees(i * 12))
                    .offset(x: CGFloat(i) * headW * 0.1, y: -headH * 0.36)
            }
            Ellipse().fill(Cat.cream.opacity(0.85))
                .frame(width: headW * 0.46, height: headH * 0.3)
                .offset(y: headH * 0.3)
        case .gosha:
            // чёрный, только маленькое белое пятнышко на подбородке
            Ellipse().fill(Cat.cream.opacity(0.9))
                .frame(width: headW * 0.2, height: headH * 0.1)
                .offset(y: headH * 0.42)
        }
    }

    private func eye(left: Bool) -> some View {
        let w = size * 0.17
        let h = size * (cat == .chloe ? 0.2 : 0.17)
        let tilt: Double = left ? -8 : 8
        return Group {
            switch expression {
            case .normal:
                ZStack {
                    Ellipse().fill(RadialGradient(colors: [cat.eyeColor.opacity(0.85), cat.eyeColor],
                                                  center: .center, startRadius: 0, endRadius: w * 0.6))
                        .frame(width: w, height: h)
                    Ellipse().fill(Color.black)
                        .frame(width: cat == .chloe ? w * 0.5 : w * 0.3, height: h * 0.82)
                    Circle().fill(Color.white)
                        .frame(width: size * 0.045, height: size * 0.045)
                        .offset(x: w * 0.18, y: -h * 0.22)
                    Ellipse().stroke(Color.black.opacity(0.75), lineWidth: max(1, size * 0.018))
                        .frame(width: w, height: h)
                }
                .rotationEffect(.degrees(tilt))
            case .happy:
                CatHappyEye()
                    .stroke(Color.black.opacity(0.85), style: StrokeStyle(lineWidth: max(2, size * 0.04), lineCap: .round))
                    .frame(width: size * 0.15, height: size * 0.08)
            }
        }
    }

    /// Белые лапки у всех трёх котов.
    private var paw: some View {
        ZStack {
            Ellipse().fill(Cat.cream)
                .overlay(Ellipse().stroke(Cat.outline.opacity(0.85), lineWidth: max(1.2, size * 0.022)))
            HStack(spacing: size * 0.02) {
                ForEach(0..<2, id: \.self) { _ in
                    Capsule().fill(Cat.outline.opacity(0.3)).frame(width: size * 0.012, height: size * 0.05)
                }
            }
            .offset(y: size * 0.03)
        }
        .frame(width: size * 0.25, height: size * 0.18)
    }
}

struct Whiskers: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        for i in 0..<3 {
            let dy = rect.height * (0.2 + 0.3 * CGFloat(i))
            let endY = rect.height * (0.05 + 0.45 * CGFloat(i))
            p.move(to: CGPoint(x: rect.midX - rect.width * 0.18, y: rect.minY + dy))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + endY))
            p.move(to: CGPoint(x: rect.midX + rect.width * 0.18, y: rect.minY + dy))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + endY))
        }
        return p
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
