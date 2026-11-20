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

/// Платон и Настя, чуть более жизненные, чем коты: Платон блондин с зелёными глазами в чёрном,
/// Настя с русыми волосами, зелёно-серыми глазами, в розовой худи и серой жилетке.
struct PersonAvatar: View {
    enum Kind { case platon, nastya }
    let kind: Kind
    var size: CGFloat = 100

    private let skin = Color(red: 0.96, green: 0.78, blue: 0.66)
    private let skinShade = Color(red: 0.9, green: 0.68, blue: 0.56)
    private var hair: Color {
        kind == .nastya ? Color(red: 0.62, green: 0.42, blue: 0.27) : Color(red: 0.86, green: 0.72, blue: 0.4)
    }
    private var hairDark: Color {
        kind == .nastya ? Color(red: 0.48, green: 0.31, blue: 0.2) : Color(red: 0.7, green: 0.55, blue: 0.28)
    }
    private var eyeColor: Color {
        kind == .nastya ? Color(red: 0.5, green: 0.62, blue: 0.5) : Color(red: 0.25, green: 0.6, blue: 0.35)
    }

    var body: some View {
        let head = size * 0.52
        let lw = max(1.2, size * 0.02)
        let headY = -size * 0.08
        ZStack {
            if kind == .nastya {
                // капюшон худи и длинные волосы сзади
                Ellipse().fill(Color(red: 0.96, green: 0.72, blue: 0.8))
                    .frame(width: head * 1.35, height: head * 0.8)
                    .offset(y: size * 0.24)
                RoundedRectangle(cornerRadius: head * 0.45, style: .continuous)
                    .fill(hairDark)
                    .frame(width: head * 1.12, height: head * 1.45)
                    .offset(y: headY + head * 0.22)
            }
            // плечи
            RoundedRectangle(cornerRadius: size * 0.2, style: .continuous)
                .fill(kind == .nastya ? Color(red: 0.97, green: 0.74, blue: 0.82) : Color(red: 0.12, green: 0.12, blue: 0.13))
                .overlay(RoundedRectangle(cornerRadius: size * 0.2, style: .continuous).stroke(Cat.outline.opacity(0.6), lineWidth: lw))
                .frame(width: size * 0.88, height: size * 0.42)
                .offset(y: size * 0.36)
            if kind == .nastya {
                // серая стёганая жилетка
                RoundedRectangle(cornerRadius: size * 0.1, style: .continuous)
                    .fill(Color(red: 0.42, green: 0.46, blue: 0.42))
                    .frame(width: size * 0.62, height: size * 0.3)
                    .offset(y: size * 0.42)
            }
            // шея
            Rectangle().fill(skinShade)
                .frame(width: head * 0.3, height: head * 0.3)
                .offset(y: headY + head * 0.5)
            // уши
            Circle().fill(skin).frame(width: head * 0.16, height: head * 0.2)
                .offset(x: -head * 0.5, y: headY + head * 0.05)
            Circle().fill(skin).frame(width: head * 0.16, height: head * 0.2)
                .offset(x: head * 0.5, y: headY + head * 0.05)
            // лицо
            Ellipse()
                .fill(LinearGradient(colors: [skin, skinShade], startPoint: .top, endPoint: .bottom))
                .overlay(Ellipse().stroke(Cat.outline.opacity(0.6), lineWidth: lw))
                .frame(width: head, height: head * 1.1)
                .offset(y: headY)
            // лёгкая щетина у Платона
            if kind == .platon {
                Ellipse().fill(hairDark.opacity(0.3))
                    .frame(width: head * 0.8, height: head * 0.42)
                    .offset(y: headY + head * 0.36)
                    .mask(Ellipse().frame(width: head, height: head * 1.1).offset(y: headY))
            }
            // причёска
            if kind == .platon {
                SpikyHair()
                    .fill(hair)
                    .frame(width: head * 1.1, height: head * 0.62)
                    .offset(y: headY - head * 0.42)
            } else {
                // чёлка и пряди по бокам лица
                Ellipse().fill(hair)
                    .frame(width: head * 1.06, height: head * 0.62)
                    .offset(y: headY - head * 0.38)
                Ellipse().fill(hair)
                    .frame(width: head * 0.22, height: head * 1.0)
                    .rotationEffect(.degrees(6))
                    .offset(x: -head * 0.5, y: headY + head * 0.1)
                Ellipse().fill(hair)
                    .frame(width: head * 0.22, height: head * 1.0)
                    .rotationEffect(.degrees(-6))
                    .offset(x: head * 0.5, y: headY + head * 0.1)
            }
            // брови
            ForEach([-1.0, 1.0], id: \.self) { side in
                Capsule().fill(hairDark)
                    .frame(width: head * 0.2, height: head * 0.04)
                    .rotationEffect(.degrees(side * 6))
                    .offset(x: CGFloat(side) * head * 0.2, y: headY - head * 0.12)
            }
            // глаза
            ForEach([-1.0, 1.0], id: \.self) { side in
                ZStack {
                    Ellipse().fill(Color.white).frame(width: head * 0.2, height: head * 0.12)
                    Circle().fill(eyeColor).frame(width: head * 0.11, height: head * 0.11)
                    Circle().fill(Color.black.opacity(0.85)).frame(width: head * 0.05, height: head * 0.05)
                    Circle().fill(Color.white).frame(width: head * 0.03, height: head * 0.03)
                        .offset(x: head * 0.02, y: -head * 0.02)
                }
                .offset(x: CGFloat(side) * head * 0.2, y: headY - head * 0.02)
            }
            // нос, щёки, улыбка
            Capsule().fill(skinShade)
                .frame(width: head * 0.06, height: head * 0.16)
                .offset(y: headY + head * 0.14)
            Circle().fill(Cat.nosePink.opacity(0.35))
                .frame(width: head * 0.16, height: head * 0.16)
                .offset(x: -head * 0.3, y: headY + head * 0.2)
            Circle().fill(Cat.nosePink.opacity(0.35))
                .frame(width: head * 0.16, height: head * 0.16)
                .offset(x: head * 0.3, y: headY + head * 0.2)
            CatMouth()
                .stroke(Color(red: 0.75, green: 0.4, blue: 0.4), style: StrokeStyle(lineWidth: lw, lineCap: .round))
                .frame(width: head * 0.26, height: head * 0.1)
                .offset(y: headY + head * 0.36)
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
            PersonAvatar(kind: .platon, size: size * 0.46)
                .offset(x: -size * 0.2, y: -size * 0.12)
            PersonAvatar(kind: .nastya, size: size * 0.46)
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
