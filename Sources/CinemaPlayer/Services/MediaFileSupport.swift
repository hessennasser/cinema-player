import Foundation
import UniformTypeIdentifiers

enum MediaFileSupport {
    static let supportedExtensions: Set<String> = [
        "3gp", "asf", "avi", "flv", "m2ts", "m4v", "mkv", "mov", "mp4", "mpeg", "mpg", "mts", "webm", "wmv",
    ]

    static func isSupported(_ url: URL) -> Bool {
        let fileExtension = url.pathExtension.lowercased()
        return supportedExtensions.contains(fileExtension)
            || UTType(filenameExtension: fileExtension)?.conforms(to: .movie) == true
    }

    static var openPanelTypes: [UTType] {
        [.movie, .video, .mpeg4Movie, .quickTimeMovie]
    }
}
