import SwiftUI

enum CinemaTheme {
    /// The shared brand palette: deep slate, harbor blue, and a restrained coral signal.
    static let night = Color(red: 0.047, green: 0.075, blue: 0.102) // #0C131A
    static let surface = Color(red: 0.071, green: 0.125, blue: 0.173) // #12202C
    static let elevatedSurface = Color(red: 0.086, green: 0.169, blue: 0.231) // #162B3B
    static let electricBlue = Color(red: 0.173, green: 0.388, blue: 0.537) // #2C6389
    static let signalRed = Color(red: 0.839, green: 0.353, blue: 0.282) // #D65A48
    static let paper = Color(red: 0.914, green: 0.933, blue: 0.949) // #E9EEF2
    static let quietText = Color.white.opacity(0.62)

    static let playerGradient = LinearGradient(
        colors: [night, elevatedSurface],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let accentGradient = LinearGradient(
        colors: [electricBlue, Color(red: 0.224, green: 0.463, blue: 0.624)],
        startPoint: .leading,
        endPoint: .trailing
    )
}

/// A compact “C + play” mark shared with the open-source project site.
struct CinemaMark: View {
    var size: CGFloat = 40

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                .fill(CinemaTheme.night)
            Circle()
                .trim(from: 0.13, to: 0.87)
                .stroke(
                    CinemaTheme.electricBlue,
                    style: StrokeStyle(lineWidth: size * 0.12, lineCap: .round)
                )
                .rotationEffect(.degrees(90))
                .padding(size * 0.19)
            Image(systemName: "play.fill")
                .font(.system(size: size * 0.22, weight: .bold))
                .foregroundStyle(CinemaTheme.signalRed)
                .offset(x: size * 0.025)
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Cinema Player")
    }
}

struct CinemaSurface: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(CinemaTheme.surface.opacity(0.92), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(.white.opacity(0.08), lineWidth: 1)
            }
    }
}

extension View {
    func cinemaSurface(cornerRadius: CGFloat = 20) -> some View {
        modifier(CinemaSurface(cornerRadius: cornerRadius))
    }
}
