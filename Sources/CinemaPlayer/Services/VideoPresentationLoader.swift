@preconcurrency import AVFoundation
import AppKit
import Foundation
@preconcurrency import QuickLookThumbnailing

@MainActor
enum VideoPresentationLoader {
    /// Remote assets can stall on a slow or dead host, so details are given a
    /// deadline and the library falls back to what it already knows.
    private static let streamTimeout: Double = 12

    static func load(for url: URL) async -> VideoPresentation {
        url.isFileURL ? await loadFile(at: url) : await loadStream(at: url)
    }

    private static func loadFile(at url: URL) async -> VideoPresentation {
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

    private static func loadStream(at url: URL) async -> VideoPresentation {
        let asset = AVURLAsset(url: url)
        let details = await withTimeout(seconds: streamTimeout) {
            await readDetails(of: asset, fileSize: nil)
        }
        let thumbnail = await withTimeout(seconds: streamTimeout) {
            await makeStreamThumbnail(from: asset)
        }

        // AVFoundation exposes no tracks for an HLS asset, so its size has to
        // come from the playlist the server sent.
        var resolution = details?.resolution
        if resolution == nil {
            resolution = await manifestResolution(at: url)
        }

        return VideoPresentation(
            thumbnail: thumbnail.flatMap { $0 },
            duration: details?.duration,
            resolution: resolution,
            fileSize: nil,
            format: StreamSupport.formatLabel(for: url),
            isStream: true
        )
    }

    /// The ceiling a master playlist advertises, not a measurement — the label
    /// says "Up to" so it is never read as the rendition being served.
    private static func manifestResolution(at url: URL) async -> String? {
        guard let manifest = try? await StreamHTTP.manifest(at: url),
              manifest.hasPrefix("#EXTM3U"),
              let size = StreamSupport.highestManifestResolution(in: manifest) else {
            return nil
        }
        return StreamSupport.advertisedResolutionLabel(for: size)
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

    /// QuickLook only knows about files, so a stream's poster frame is pulled
    /// out of the asset itself.
    private static func makeStreamThumbnail(from asset: AVURLAsset) async -> NSImage? {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 480, height: 270)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 5, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 5, preferredTimescale: 600)

        guard let (image, _) = try? await generator.image(at: CMTime(seconds: 3, preferredTimescale: 600)) else {
            return nil
        }
        return NSImage(cgImage: image, size: CGSize(width: image.width, height: image.height))
    }

    private static func readDetails(for url: URL) async -> VideoDetails {
        let asset = AVURLAsset(url: url)
        return await readDetails(of: asset, fileSize: fileSizeString(for: url))
    }

    private static func readDetails(of asset: AVURLAsset, fileSize: String?) async -> VideoDetails {
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

    /// Returns nil when `operation` outlives the deadline.
    private static func withTimeout<Value: Sendable>(
        seconds: Double,
        operation: @escaping @Sendable () async -> Value
    ) async -> Value? {
        await withTaskGroup(of: Value?.self) { group in
            group.addTask { await operation() }
            group.addTask {
                try? await Task.sleep(for: .seconds(seconds))
                return nil
            }

            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }
}

private struct VideoDetails: Sendable {
    let duration: Double?
    let resolution: String?
    let fileSize: String?
}
