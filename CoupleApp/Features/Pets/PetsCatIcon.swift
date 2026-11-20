import SwiftUI

/// Окрас кота для мультяшной иконки.
enum PetsCatStyle: String, CaseIterable {
    case tuxedo, slim, grey

    var fur: Color {
        switch self {
        case .tuxedo: Color(red: 0.13, green: 0.12, blue: 0.14)
        case .slim: Color(red: 0.10, green: 0.10, blue: 0.12)
        case .grey: Color(red: 0.62, green: 0.63, blue: 0.68)
        }
    }

    var background: Color {
        switch self {
        case .tuxedo: Color(red: 0.98, green: 0.86, blue: 0.88)
        case .slim: Color(red: 0.93, green: 0.88, blue: 0.80)
        case .grey: Color(red: 0.85, green: 0.78, blue: 0.74)
        }
    }

    /// Белые отметины (мордочка и грудка у Мирони).
    var hasWhiteMuzzle: Bool { self == .tuxedo }
    /// Худенький кот — мордочка уже.
    var faceWidth: CGFloat { self == .slim ? 0.62 : (self == .grey ? 0.56 : 0.74) }
    var eye: Color { self == .grey ? Color(red: 0.35, green: 0.62, blue: 0.45) : Color(red: 0.95, green: 0.78, blue: 0.25) }
}

private struct PetsEar: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

/// Милая мордочка кота, нарисованная кодом (без картинок).
struct PetsCatIcon: View {
    let style: PetsCatStyle
    var size: CGFloat = 64

    var body: some View {
        let fw = size * style.faceWidth
        let fh = size * (style == .slim ? 0.58 : 0.56)
        ZStack {
            Circle().fill(style.background)
            ZStack {
                // уши
                HStack(spacing: fw * 0.42) {
                    PetsEar().fill(style.fur).frame(width: fw * 0.3, height: fh * 0.4).rotationEffect(.degrees(-8))
                    PetsEar().fill(style.fur).frame(width: fw * 0.3, height: fh * 0.4).rotationEffect(.degrees(8))
                }
                .offset(y: -fh * 0.42)
                // голова
                Ellipse().fill(style.fur).frame(width: fw, height: fh)
                if style.hasWhiteMuzzle {
                    Ellipse().fill(.white).frame(width: fw * 0.5, height: fh * 0.5).offset(y: fh * 0.2)
                    Capsule().fill(.white).frame(width: fw * 0.1, height: fh * 0.4).offset(y: -fh * 0.15)
                }
                // глаза
                HStack(spacing: fw * 0.3) {
                    eye
                    eye
                }
                .offset(y: -fh * 0.05)
                // нос и рот
                Circle().fill(Color(red: 0.95, green: 0.55, blue: 0.62))
                    .frame(width: size * 0.07, height: size * 0.07)
                    .offset(y: fh * 0.14)
            }
            .offset(y: size * 0.04)
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var eye: some View {
        ZStack {
            Circle().fill(style.eye).frame(width: size * 0.13, height: size * 0.13)
            Capsule().fill(.black).frame(width: size * 0.035, height: size * 0.1)
        }
    }
}

/// Иконка питомца: для котов своя, для остальных лапка.
struct PetsAvatar: View {
    let pet: PetsPet
    var size: CGFloat = 64

    var body: some View {
        if let style = PetsCatStyle(rawValue: pet.iconKey) {
            PetsCatIcon(style: style, size: size)
        } else {
            Image(systemName: "pawprint.fill")
                .font(.system(size: size * 0.45))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(Circle().fill(Color(red: 0.8, green: 0.6, blue: 0.55)))
        }
    }
}
