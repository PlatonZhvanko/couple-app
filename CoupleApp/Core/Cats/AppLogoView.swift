import SwiftUI

/// Верх причёски с торчащими прядями.
struct SpikyHair: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let n = 9
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        for i in 0...n {
            let t = CGFloat(i) / CGFloat(n)
            let x = rect.minX + rect.width * t
            let arc = sin(t * .pi)
            let base = rect.maxY - rect.height * 0.75 * arc
            let spike: CGFloat = i % 2 == 0 ? 0 : rect.height * 0.18
            p.addLine(to: CGPoint(x: x, y: base - spike))
        }
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY),
                       control: CGPoint(x: rect.midX, y: rect.maxY - rect.height * 0.25))
        p.closeSubpath()
        return p
    }
}

/// Овальное лицо с сужением к подбородку.
struct EggFace: Shape {
    var chin: CGFloat = 0.28

    func path(in r: CGRect) -> Path {
        var p = Path()
        let w = r.width
        let h = r.height
        p.move(to: CGPoint(x: r.midX, y: r.minY))
        p.addCurve(to: CGPoint(x: r.maxX, y: r.minY + h * 0.42),
                   control1: CGPoint(x: r.midX + w * 0.38, y: r.minY),
                   control2: CGPoint(x: r.maxX, y: r.minY + h * 0.16))
        p.addCurve(to: CGPoint(x: r.midX, y: r.maxY),
                   control1: CGPoint(x: r.maxX, y: r.minY + h * 0.72),
                   control2: CGPoint(x: r.midX + w * chin, y: r.maxY))
        p.addCurve(to: CGPoint(x: r.minX, y: r.minY + h * 0.42),
                   control1: CGPoint(x: r.midX - w * chin, y: r.maxY),
                   control2: CGPoint(x: r.minX, y: r.minY + h * 0.72))
        p.addCurve(to: CGPoint(x: r.midX, y: r.minY),
                   control1: CGPoint(x: r.minX, y: r.minY + h * 0.16),
                   control2: CGPoint(x: r.midX - w * 0.38, y: r.minY))
        p.closeSubpath()
        return p
    }
}

/// Длинные волосы сзади, ложатся на плечи мягкой волной.
struct LongHairBack: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let w = r.width
        let h = r.height
        p.move(to: CGPoint(x: r.midX, y: r.minY))
        p.addCurve(to: CGPoint(x: r.maxX - w * 0.02, y: r.minY + h * 0.4),
                   control1: CGPoint(x: r.maxX - w * 0.1, y: r.minY),
                   control2: CGPoint(x: r.maxX, y: r.minY + h * 0.18))
        p.addCurve(to: CGPoint(x: r.maxX - w * 0.1, y: r.maxY),
                   control1: CGPoint(x: r.maxX + w * 0.02, y: r.minY + h * 0.7),
                   control2: CGPoint(x: r.maxX - w * 0.02, y: r.minY + h * 0.92))
        p.addCurve(to: CGPoint(x: r.minX + w * 0.1, y: r.maxY),
                   control1: CGPoint(x: r.maxX - w * 0.35, y: r.maxY - h * 0.1),
                   control2: CGPoint(x: r.minX + w * 0.35, y: r.maxY + h * 0.0))
        p.addCurve(to: CGPoint(x: r.minX + w * 0.02, y: r.minY + h * 0.4),
                   control1: CGPoint(x: r.minX + w * 0.02, y: r.minY + h * 0.92),
                   control2: CGPoint(x: r.minX - w * 0.02, y: r.minY + h * 0.7))
        p.addCurve(to: CGPoint(x: r.midX, y: r.minY),
                   control1: CGPoint(x: r.minX, y: r.minY + h * 0.18),
                   control2: CGPoint(x: r.minX + w * 0.1, y: r.minY))
        p.closeSubpath()
        return p
    }
}

/// Левая прядь чёлки: от пробора вниз вдоль щеки. Для правой отразить.
struct HairCurtain: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let w = r.width
        let h = r.height
        p.move(to: CGPoint(x: r.maxX, y: r.minY))
        p.addCurve(to: CGPoint(x: r.minX, y: r.minY + h * 0.5),
                   control1: CGPoint(x: r.minX + w * 0.35, y: r.minY),
                   control2: CGPoint(x: r.minX, y: r.minY + h * 0.2))
        p.addCurve(to: CGPoint(x: r.minX + w * 0.2, y: r.maxY),
                   control1: CGPoint(x: r.minX, y: r.minY + h * 0.78),
                   control2: CGPoint(x: r.minX + w * 0.05, y: r.minY + h * 0.95))
        p.addCurve(to: CGPoint(x: r.minX + w * 0.8, y: r.minY + h * 0.3),
                   control1: CGPoint(x: r.minX + w * 0.4, y: r.minY + h * 0.7),
                   control2: CGPoint(x: r.minX + w * 0.6, y: r.minY + h * 0.4))
        p.closeSubpath()
        return p
    }
}

/// Глаз человека: белок, радужка, зрачок, блики, ресницы.
struct PersonEye: View {
    let width: CGFloat
    let iris: Color
    var lashes = false
    var left = true

    var body: some View {
        let h = width * 0.62
        ZStack {
            Ellipse().fill(Color.white).frame(width: width, height: h)
            Circle()
                .fill(RadialGradient(colors: [iris.opacity(0.7), iris], center: .center, startRadius: 0, endRadius: h * 0.5))
                .frame(width: h * 0.95, height: h * 0.95)
            Circle().fill(Color.black.opacity(0.85)).frame(width: h * 0.42, height: h * 0.42)
            Circle().fill(Color.white).frame(width: h * 0.2, height: h * 0.2).offset(x: h * 0.14, y: -h * 0.16)
            Circle().fill(Color.white.opacity(0.7)).frame(width: h * 0.1, height: h * 0.1).offset(x: -h * 0.12, y: h * 0.14)
            // верхнее веко
            CatHappyEye()
                .stroke(Color(red: 0.2, green: 0.13, blue: 0.12),
                        style: StrokeStyle(lineWidth: width * (lashes ? 0.14 : 0.09), lineCap: .round))
                .frame(width: width * 1.02, height: h * 0.5)
                .rotationEffect(.degrees(180))
                .offset(y: -h * 0.42)
            if lashes {
                // реснички-хвостик с внешнего края
                Capsule().fill(Color(red: 0.2, green: 0.13, blue: 0.12))
                    .frame(width: width * 0.28, height: width * 0.07)
                    .rotationEffect(.degrees(left ? 28 : -28))
                    .offset(x: (left ? -1 : 1) * width * 0.5, y: -h * 0.32)
            }
        }
    }
}

/// Платон и Настя. Платон: блондин с зелёными глазами, небольшая бородка, в чёрном.
/// Настя: стройная, русые длинные волосы, зелёно-серые глаза, розовая худи и серая жилетка.
struct PersonAvatar: View {
    enum Kind { case platon, nastya }
    let kind: Kind
    var size: CGFloat = 100

    private let skin = Color(red: 0.98, green: 0.8, blue: 0.68)
    private let skinShade = Color(red: 0.92, green: 0.7, blue: 0.58)
    private var nast: Bool { kind == .nastya }
    private var hair: Color {
        nast ? Color(red: 0.7, green: 0.49, blue: 0.3) : Color(red: 0.9, green: 0.76, blue: 0.45)
    }
    private var hairDark: Color {
        nast ? Color(red: 0.5, green: 0.32, blue: 0.2) : Color(red: 0.72, green: 0.56, blue: 0.3)
    }
    private var hairLight: Color {
        nast ? Color(red: 0.85, green: 0.65, blue: 0.42) : Color(red: 0.96, green: 0.86, blue: 0.6)
    }
    private var iris: Color {
        nast ? Color(red: 0.45, green: 0.62, blue: 0.52) : Color(red: 0.22, green: 0.62, blue: 0.36)
    }

    var body: some View {
        let hw = size * (nast ? 0.4 : 0.46)
        let hh = hw * (nast ? 1.2 : 1.1)
        let hy = -size * 0.1
        let lw = max(1, size * 0.015)
        let outline = Cat.outline.opacity(0.55)

        ZStack {
            // волосы Насти сзади
            if nast {
                LongHairBack()
                    .fill(LinearGradient(colors: [hair, hairDark], startPoint: .top, endPoint: .bottom))
                    .frame(width: hw * 1.55, height: hh * 1.55)
                    .offset(y: hy + hh * 0.3)
                // капюшон худи
                Ellipse().fill(Color(red: 0.96, green: 0.72, blue: 0.8))
                    .frame(width: hw * 1.3, height: hh * 0.45)
                    .offset(y: hy + hh * 0.68)
            }

            // плечи: у Насти уже и мягче
            RoundedRectangle(cornerRadius: size * (nast ? 0.16 : 0.18), style: .continuous)
                .fill(nast ? Color(red: 0.98, green: 0.76, blue: 0.84) : Color(red: 0.13, green: 0.13, blue: 0.15))
                .overlay(RoundedRectangle(cornerRadius: size * 0.17, style: .continuous).stroke(outline, lineWidth: lw))
                .frame(width: size * (nast ? 0.7 : 0.86), height: size * 0.36)
                .offset(y: size * 0.4)
            if nast {
                // серая стёганая жилетка: две половинки по бокам от молнии
                ForEach([-1.0, 1.0], id: \.self) { side in
                    RoundedRectangle(cornerRadius: size * 0.07, style: .continuous)
                        .fill(Color(red: 0.5, green: 0.55, blue: 0.5))
                        .frame(width: size * 0.2, height: size * 0.3)
                        .offset(x: CGFloat(side) * size * 0.17, y: size * 0.44)
                }
            } else {
                // воротник чёрной худи
                Ellipse().fill(Color(red: 0.2, green: 0.2, blue: 0.22))
                    .frame(width: hw * 0.7, height: hh * 0.2)
                    .offset(y: hy + hh * 0.6)
            }

            // шея
            Capsule().fill(skinShade)
                .frame(width: hw * (nast ? 0.24 : 0.32), height: hh * 0.4)
                .offset(y: hy + hh * 0.5)

            // уши у Платона
            if !nast {
                ForEach([-1.0, 1.0], id: \.self) { side in
                    Ellipse().fill(skin).frame(width: hw * 0.13, height: hw * 0.2)
                        .offset(x: CGFloat(side) * hw * 0.5, y: hy + hh * 0.05)
                }
            }

            // лицо
            EggFace(chin: nast ? 0.24 : 0.34)
                .fill(LinearGradient(colors: [skin, skinShade.opacity(0.95)], startPoint: .top, endPoint: .bottom))
                .overlay(EggFace(chin: nast ? 0.24 : 0.34).stroke(outline, lineWidth: lw))
                .frame(width: hw, height: hh)
                .offset(y: hy)

            // причёска
            if nast {
                // объём на макушке и две пряди чёлки с пробором чуть в сторону
                Ellipse().fill(hair)
                    .frame(width: hw * 1.05, height: hh * 0.42)
                    .offset(y: hy - hh * 0.36)
                HairCurtain()
                    .fill(LinearGradient(colors: [hairLight, hair], startPoint: .top, endPoint: .bottom))
                    .frame(width: hw * 0.66, height: hh * 0.95)
                    .offset(x: -hw * 0.2, y: hy - hh * 0.03)
                HairCurtain()
                    .fill(LinearGradient(colors: [hairLight, hair], startPoint: .top, endPoint: .bottom))
                    .frame(width: hw * 0.66, height: hh * 0.95)
                    .scaleEffect(x: -1, y: 1)
                    .offset(x: hw * 0.2, y: hy - hh * 0.03)
            } else {
                SpikyHair()
                    .fill(LinearGradient(colors: [hairLight, hair], startPoint: .top, endPoint: .bottom))
                    .frame(width: hw * 1.08, height: hh * 0.58)
                    .offset(y: hy - hh * 0.4)
            }

            // брови
            ForEach([-1.0, 1.0], id: \.self) { side in
                CatHappyEye()
                    .stroke(hairDark, style: StrokeStyle(lineWidth: hw * (nast ? 0.03 : 0.045), lineCap: .round))
                    .frame(width: hw * 0.22, height: hw * 0.06)
                    .rotationEffect(.degrees(180))
                    .offset(x: CGFloat(side) * hw * 0.2, y: hy - hh * 0.09)
            }

            // глаза
            PersonEye(width: hw * (nast ? 0.25 : 0.21), iris: iris, lashes: nast, left: true)
                .offset(x: -hw * 0.2, y: hy - hh * 0.01)
            PersonEye(width: hw * (nast ? 0.25 : 0.21), iris: iris, lashes: nast, left: false)
                .offset(x: hw * 0.2, y: hy - hh * 0.01)

            // нос
            Capsule().fill(skinShade.opacity(0.9))
                .frame(width: hw * 0.05, height: hh * 0.13)
                .offset(y: hy + hh * 0.14)
            Ellipse().fill(skinShade)
                .frame(width: hw * 0.1, height: hh * 0.04)
                .offset(y: hy + hh * 0.21)

            // румянец
            ForEach([-1.0, 1.0], id: \.self) { side in
                Circle().fill(Cat.nosePink.opacity(nast ? 0.45 : 0.3))
                    .frame(width: hw * 0.2, height: hw * 0.2)
                    .offset(x: CGFloat(side) * hw * 0.28, y: hy + hh * 0.2)
            }

            // улыбка и губы
            CatMouth()
                .stroke(Color(red: 0.82, green: 0.42, blue: 0.46), style: StrokeStyle(lineWidth: lw * 1.3, lineCap: .round))
                .frame(width: hw * 0.26, height: hh * 0.07)
                .offset(y: hy + hh * 0.3)
            if nast {
                Capsule().fill(Color(red: 0.93, green: 0.5, blue: 0.56).opacity(0.85))
                    .frame(width: hw * 0.17, height: hh * 0.035)
                    .offset(y: hy + hh * 0.35)
            }

            // небольшая бородка у Платона
            if !nast {
                Ellipse().fill(hairDark.opacity(0.9))
                    .frame(width: hw * 0.26, height: hh * 0.13)
                    .offset(y: hy + hh * 0.44)
                Capsule().fill(hairDark.opacity(0.75))
                    .frame(width: hw * 0.22, height: hh * 0.025)
                    .offset(y: hy + hh * 0.25)
            }
        }
        .frame(width: size, height: size)
    }
}

/// Логотип приложения: Платон, Настя и трое котов.
struct AppLogoView: View {
    var size: CGFloat = 240
    var showBackground = true

    var body: some View {
        ZStack {
            if showBackground {
                RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                    .fill(LinearGradient(
                        colors: [Color(red: 0.98, green: 0.84, blue: 0.82), Color(red: 0.86, green: 0.68, blue: 0.6)],
                        startPoint: .top, endPoint: .bottom))
                    .frame(width: size, height: size)
            }
            Image(systemName: "heart.fill")
                .font(.system(size: size * 0.1))
                .foregroundStyle(Color(red: 0.9, green: 0.4, blue: 0.5))
                .offset(y: -size * 0.3)
            PersonAvatar(kind: .platon, size: size * 0.5)
                .offset(x: -size * 0.2, y: -size * 0.12)
            PersonAvatar(kind: .nastya, size: size * 0.5)
                .offset(x: size * 0.2, y: -size * 0.12)
            CatAvatar(cat: .gosha, size: size * 0.3, expression: .happy)
                .offset(x: -size * 0.28, y: size * 0.24)
            CatAvatar(cat: .chloe, size: size * 0.28, expression: .happy)
                .offset(x: size * 0.28, y: size * 0.26)
            CatAvatar(cat: .miron, size: size * 0.38)
                .offset(y: size * 0.24)
        }
        .frame(width: size, height: size)
    }
}
