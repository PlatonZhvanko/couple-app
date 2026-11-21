import SwiftUI

/// Логотип приложения: мультяшный портрет Платона и Насти и трое котов внизу.
struct AppLogoView: View {
    var size: CGFloat = 240
    var showBackground = true

    var body: some View {
        ZStack {
            Image("CouplePortrait")
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size, alignment: .top)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                        .stroke(Color(red: 0.98, green: 0.84, blue: 0.82), lineWidth: max(2, size * 0.015))
                )
                .shadow(color: .black.opacity(0.25), radius: size * 0.04, y: size * 0.02)
            // мягкий низ, чтобы коты читались
            LinearGradient(colors: [.clear, Color(red: 0.36, green: 0.24, blue: 0.22).opacity(0.55)],
                           startPoint: .center, endPoint: .bottom)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
            CatAvatar(cat: .gosha, size: size * 0.34, expression: .happy)
                .offset(x: -size * 0.3, y: size * 0.36)
            CatAvatar(cat: .chloe, size: size * 0.32, expression: .happy)
                .offset(x: size * 0.3, y: size * 0.37)
            CatAvatar(cat: .miron, size: size * 0.42)
                .offset(y: size * 0.36)
        }
        .frame(width: size, height: size)
    }
}
