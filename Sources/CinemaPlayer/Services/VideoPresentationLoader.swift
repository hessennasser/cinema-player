@preconcurrency import AVFoundation
import AppKit
import Foundation
@preconcurrency import QuickLookThumbnailing

@MainActor
enum VideoPresentationLoader {
    static func load(for url: URL) async -> VideoPresentation {
        async let thumbnail = makeThumbnail(for: url)
        async let details = readDetails(for: url)
        let (image, mediaDetails) = await (thumbnail, details)

        return VideoPresentation(
            thumbnail: image,
            duration: mediaDetails.duration,
            resolution: mediaDetails.resolution,
            fileSize: mediaDetails.fileSize,
            format: url.pathExtension.uppercased()
        )
    }

    private static func makeThumbnail(for url: URL) async -> NSImage? {
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: 480, height: 270),
            scale: 2,
            representationTypes: .thumbnail
        )

        return await withCheckedContinuation { continuation in
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { thumbnail, _ in
                continuation.resume(returning: thumbnail?.nsImage)
            }
        }
    }

    private static func readDetails(for url: URL) async -> VideoDetails {
        let asset = AVURLAsset(url: url)
        let fileSize = fileSizeString(for: url)

        do {
            async let duration = asset.load(.duration)
            let tracks = try await asset.loadTracks(withMediaType: .video)
            let naturalSize = try await tracks.first?.load(.naturalSize)
            let loadedDuration = try await duration

            return VideoDetails(
                duration: loadedDuration.seconds.isFinite ? loadedDuration.seconds : nil,
                resolution: naturalSize.map { "\(Int($0.width.rounded())) × \(Int($0.height.rounded()))" },
                fileSize: fileSize
            )
        } catch {
            return VideoDetails(duration: nil, resolution: nil, fileSize: fileSize)
        }
    }

    private static func fileSizeString(for url: URL) -> String? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let byteCount = attributes[.size] as? NSNumber else {
            return nil
        }
        return ByteCountFormatter.string(fromByteCount: byteCount.int64Value, countStyle: .file)
    }
}

private struct VideoDetails {
    let duration: Double?
    let resolution: String?
    let fileSize: String?
}
