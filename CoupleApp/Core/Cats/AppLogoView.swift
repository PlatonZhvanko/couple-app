import SwiftUI

/// Мультяшные Платон и Настя (по фото: у Насти длинные светло-русые волосы и розовая худи).
struct PersonAvatar: View {
    enum Kind { case platon, nastya }
    let kind: Kind
    var size: CGFloat = 100

    private var skin: Color { Color(red: 0.99, green: 0.82, blue: 0.7) }
    private var hair: Color {
        kind == .nastya ? Color(red: 0.8, green: 0.55, blue: 0.35) : Color(red: 0.22, green: 0.15, blue: 0.12)
    }
    private var hoodie: Color {
        kind == .nastya ? Color(red: 0.97, green: 0.74, blue: 0.82) : Color(red: 0.45, green: 0.52, blue: 0.62)
    }

    var body: some View {
        let head = size * 0.58
        let lw = max(1.5, size * 0.025)
        ZStack {
            // длинные волосы Насти сзади
            if kind == .nastya {
                RoundedRectangle(cornerRadius: head * 0.4, style: .continuous)
                    .fill(hair)
                    .frame(width: head * 1.12, height: head * 1.25)
                    .offset(y: -size * 0.02)
            }
            // плечи
            RoundedRectangle(cornerRadius: size * 0.2, style: .continuous)
                .fill(hoodie)
                .overlay(RoundedRectangle(cornerRadius: size * 0.2, style: .continuous).stroke(Cat.outline, lineWidth: lw))
                .frame(width: size * 0.82, height: size * 0.4)
                .offset(y: size * 0.32)
            // голова
            Circle().fill(skin)
                .overlay(Circle().stroke(Cat.outline, lineWidth: lw))
                .frame(width: head, height: head)
                .offset(y: -size * 0.04)
            // чёлка / причёска
            Circle().trim(from: 0.5, to: 1.0)
                .fill(hair)
                .frame(width: head * 1.04, height: head * 1.04)
                .offset(y: -size * 0.04 - head * 0.2)
            // глазки и улыбка
            Circle().fill(Color(red: 0.2, green: 0.15, blue: 0.14))
                .frame(width: size * 0.06, height: size * 0.06)
                .offset(x: -head * 0.2, y: -size * 0.02)
            Circle().fill(Color(red: 0.2, green: 0.15, blue: 0.14))
                .frame(width: size * 0.06, height: size * 0.06)
                .offset(x: head * 0.2, y: -size * 0.02)
            CatMouth()
                .stroke(Cat.outline, style: StrokeStyle(lineWidth: lw, lineCap: .round))
                .frame(width: size * 0.14, height: size * 0.06)
                .offset(y: size * 0.09)
            Circle().fill(Cat.nosePink.opacity(0.5))
                .frame(width: size * 0.1, height: size * 0.1)
                .offset(x: -head * 0.34, y: size * 0.06)
            Circle().fill(Cat.nosePink.opacity(0.5))
                .frame(width: size * 0.1, height: size * 0.1)
                .offset(x: head * 0.34, y: size * 0.06)
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
