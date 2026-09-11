import CryptoKit
import Foundation

/// Keeps a local copy of a video whose host will not serve byte ranges.
///
/// AVPlayer streams a progressive file by seeking into it, which needs `Range`.
/// A host that answers every request with the whole file leaves the player
/// unable to reach the `moov` atom when it sits at the end, so the only way to
/// watch such a video is to fetch it first.
@MainActor
final class StreamCache {
    static let shared = StreamCache()

    private let directory: URL

    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("local.cinema-player/streams", isDirectory: true)
    }

    func cachedCopy(of url: URL) -> URL? {
        let location = location(for: url)
        return FileManager.default.fileExists(atPath: location.path) ? location : nil
    }

    /// Downloads `url` into the cache, reporting progress from 0 to 1. Throws
    /// `CancellationError` when the surrounding task is cancelled.
    func localCopy(of url: URL, progress: @escaping @MainActor (Double) -> Void) async throws -> URL {
        if let cached = cachedCopy(of: url) { return cached }

        guard StreamAddressPolicy.isPublic(url) else {
            throw StreamHTTPError.blockedAddress("it points at this machine or your local network")
        }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        var request = URLRequest(url: url)
        request.timeoutInterval = StreamHTTP.timeout

        let reporter = DownloadProgress(report: progress)
        let temporaryURL: URL
        let response: URLResponse
        do {
            (temporaryURL, response) = try await URLSession.shared.download(for: request, delegate: reporter)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if (error as NSError).code == NSURLErrorCancelled { throw CancellationError() }
            throw StreamHTTPError.transport(error.localizedDescription)
        }

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            try? FileManager.default.removeItem(at: temporaryURL)
            // A link that worked when it was added and now refuses is the
            // signature of a signed URL whose window has closed.
            throw [401, 403, 410].contains(http.statusCode)
                ? StreamLinkError.accessExpired
                : StreamLinkError.http(.status(http.statusCode))
        }

        let destination = location(for: url)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: temporaryURL, to: destination)
        return destination
    }

    func removeCopy(of url: URL) {
        guard let cached = cachedCopy(of: url) else { return }
        try? FileManager.default.removeItem(at: cached)
    }

    /// Named by a digest of the address so two links never collide and the same
    /// link is only ever fetched once.
    private func location(for url: URL) -> URL {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
            .map { String(format: "%02x", $0) }
            .joined()

        let pathExtension = url.pathExtension.lowercased()
        let name = MediaFileSupport.supportedExtensions.contains(pathExtension)
            ? "\(digest).\(pathExtension)"
            : "\(digest).mp4"
        return directory.appendingPathComponent(name)
    }
}

private final class DownloadProgress: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let report: @MainActor (Double) -> Void

    init(report: @escaping @MainActor (Double) -> Void) {
        self.report = report
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let fraction = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        Task { @MainActor [report] in report(min(max(fraction, 0), 1)) }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // The async download(for:) API takes ownership of the file itself.
    }
}
