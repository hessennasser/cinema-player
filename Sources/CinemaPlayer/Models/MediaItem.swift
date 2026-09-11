import Foundation

struct MediaItem: Identifiable, Hashable {
    let id: UUID
    let title: String
    let url: URL
    let bookmarkData: Data?
    let addedAt: Date
    /// True when the host refuses byte ranges, so the file has to be fetched
    /// before it can be played rather than streamed in place.
    let needsLocalCopy: Bool

    /// True when the video lives behind a link rather than on this Mac.
    var isRemote: Bool { !url.isFileURL }

    init(
        id: UUID = UUID(),
        title: String,
        url: URL,
        bookmarkData: Data?,
        addedAt: Date = .now,
        needsLocalCopy: Bool = false
    ) {
        self.id = id
        self.title = title
        self.url = url
        self.bookmarkData = bookmarkData
        self.addedAt = addedAt
        self.needsLocalCopy = needsLocalCopy
    }
}

struct PersistedMediaItem: Codable {
    let id: UUID
    let title: String
    let lastKnownURL: URL
    let bookmarkData: Data?
    let addedAt: Date
    /// Optional so a library saved before this existed still decodes.
    let needsLocalCopy: Bool?

    init(item: MediaItem) {
        id = item.id
        title = item.title
        lastKnownURL = item.url
        bookmarkData = item.bookmarkData
        addedAt = item.addedAt
        needsLocalCopy = item.needsLocalCopy
    }

    func makeMediaItem() -> MediaItem? {
        guard let resolvedURL = resolveURL() else { return nil }

        return MediaItem(
            id: id,
            title: title,
            url: resolvedURL,
            bookmarkData: bookmarkData,
            addedAt: addedAt,
            needsLocalCopy: needsLocalCopy ?? false
        )
    }

    private func resolveURL() -> URL? {
        guard lastKnownURL.isFileURL else { return lastKnownURL }
        guard let bookmarkData else { return lastKnownURL }

        var bookmarkIsStale = false
        do {
            return try URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &bookmarkIsStale
            )
        } catch {
            return FileManager.default.fileExists(atPath: lastKnownURL.path) ? lastKnownURL : nil
        }
    }
}
