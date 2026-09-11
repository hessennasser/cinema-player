import CoreGraphics
import Foundation

/// One quality an adaptive stream offers. A master playlist lists several and
/// the player moves between them, so these are the rungs a viewer can pin to.
struct StreamRendition: Identifiable, Hashable, Sendable {
    let size: CGSize
    /// Peak bits per second advertised for this rung, when the playlist says.
    let peakBitRate: Double?

    var id: Int { height }
    var height: Int { Int(size.height.rounded()) }
    var width: Int { Int(size.width.rounded()) }

    /// The shorthand people expect from a quality menu.
    var title: String {
        switch height {
        case 4_320...: "4320p (8K)"
        case 2_160..<4_320: "2160p (4K)"
        case 1_440..<2_160: "1440p"
        case 1_080..<1_440: "1080p"
        case 720..<1_080: "720p"
        case 480..<720: "\(height)p"
        default: "\(height)p"
        }
    }

    var detail: String {
        "\(width) × \(height)"
    }
}
