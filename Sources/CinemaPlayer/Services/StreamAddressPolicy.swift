import Darwin
import Foundation

/// Decides whether a link may be fetched at all. The resolver follows addresses
/// the user pastes, so without this it would happily read a router's admin page
/// or a service bound to loopback and report what it found.
enum StreamAddressPolicy {
    /// Host names that never belong to the public internet.
    private static let blockedSuffixes = [".local", ".internal", ".localhost", ".home.arpa"]
    private static let blockedNames = ["localhost", "broadcasthost"]

    enum Verdict: Equatable {
        case allowed
        case blocked(reason: String)
    }

    /// Checks the host of `url`, resolving a name to every address it answers
    /// with, so a public name pointing at 127.0.0.1 is caught too.
    static func verdict(for url: URL) -> Verdict {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return .blocked(reason: "only http and https links can be opened")
        }
        guard let host = url.host?.lowercased(), !host.isEmpty else {
            return .blocked(reason: "the link has no host")
        }

        if blockedNames.contains(host) || blockedSuffixes.contains(where: host.hasSuffix) {
            return .blocked(reason: "it points at this machine or your local network")
        }

        // A literal address needs no lookup; a name may answer with several.
        let addresses = literalAddress(host).map { [$0] } ?? resolvedAddresses(for: host)
        guard !addresses.isEmpty else {
            return .blocked(reason: "the host name could not be resolved")
        }

        if addresses.contains(where: isPrivate) {
            return .blocked(reason: "it resolves to an address on this machine or your local network")
        }
        return .allowed
    }

    static func isPublic(_ url: URL) -> Bool {
        verdict(for: url) == .allowed
    }

    /// A cheap check that never resolves a name, for discarding candidates
    /// while reading a page. `verdict(for:)` is still the authority, and runs
    /// before anything is actually fetched.
    static func isObviouslyLocal(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return true
        }
        guard let host = url.host?.lowercased(), !host.isEmpty else { return true }

        if blockedNames.contains(host) || blockedSuffixes.contains(where: host.hasSuffix) {
            return true
        }
        // Only judge a literal address here; a name would need a lookup.
        return literalAddress(host).map(isPrivate) ?? false
    }

    // MARK: - Address classification

    static func isPrivate(_ address: String) -> Bool {
        if let bytes = packed(address, family: AF_INET) {
            return isPrivateIPv4(bytes)
        }
        if let bytes = packed(address, family: AF_INET6) {
            return isPrivateIPv6(bytes)
        }
        return true
    }

    private static func isPrivateIPv4(_ b: [UInt8]) -> Bool {
        switch (b[0], b[1]) {
        case (0, _): true                              // 0.0.0.0/8, "this network"
        case (10, _): true                             // private
        case (100, 64...127): true                     // carrier-grade NAT
        case (127, _): true                            // loopback
        case (169, 254): true                          // link-local, incl. metadata services
        case (172, 16...31): true                      // private
        case (192, 0): true                            // 192.0.0.0/24 protocol assignments
        case (192, 168): true                          // private
        case (198, 18...19): true                      // benchmarking
        case (224...255, _): true                      // multicast and reserved
        default: false
        }
    }

    private static func isPrivateIPv6(_ b: [UInt8]) -> Bool {
        // ::ffff:a.b.c.d carries a v4 address that must be judged as v4.
        let isIPv4Mapped = b[0..<10].allSatisfy { $0 == 0 } && b[10] == 0xFF && b[11] == 0xFF
        if isIPv4Mapped {
            return isPrivateIPv4(Array(b[12..<16]))
        }

        if b[0..<15].allSatisfy({ $0 == 0 }) {
            return true                                // :: and ::1
        }
        if b[0] & 0xFE == 0xFC {
            return true                                // fc00::/7 unique local
        }
        if b[0] == 0xFE, b[1] & 0xC0 == 0x80 {
            return true                                // fe80::/10 link-local
        }
        if b[0] == 0xFF {
            return true                                // ff00::/8 multicast
        }
        return false
    }

    // MARK: - Lookups

    private static func literalAddress(_ host: String) -> String? {
        // A URL keeps an IPv6 literal in brackets.
        let bare = host.hasPrefix("[") && host.hasSuffix("]")
            ? String(host.dropFirst().dropLast())
            : host

        if packed(bare, family: AF_INET) != nil || packed(bare, family: AF_INET6) != nil {
            return bare
        }
        return nil
    }

    private static func packed(_ address: String, family: Int32) -> [UInt8]? {
        let byteCount = family == AF_INET ? 4 : 16
        var buffer = [UInt8](repeating: 0, count: byteCount)

        // A zone index (fe80::1%en0) is not part of the address itself.
        let bare = address.split(separator: "%", maxSplits: 1).first.map(String.init) ?? address
        let result = bare.withCString { pointer in
            buffer.withUnsafeMutableBytes { raw in
                inet_pton(family, pointer, raw.baseAddress)
            }
        }
        return result == 1 ? buffer : nil
    }

    private static func resolvedAddresses(for host: String) -> [String] {
        var hints = addrinfo(
            ai_flags: 0,
            ai_family: AF_UNSPEC,
            ai_socktype: SOCK_STREAM,
            ai_protocol: 0,
            ai_addrlen: 0,
            ai_canonname: nil,
            ai_addr: nil,
            ai_next: nil
        )

        var head: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &head) == 0, let head else { return [] }
        defer { freeaddrinfo(head) }

        var addresses: [String] = []
        var node: UnsafeMutablePointer<addrinfo>? = head
        while let current = node {
            var text = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(
                current.pointee.ai_addr,
                current.pointee.ai_addrlen,
                &text,
                socklen_t(text.count),
                nil,
                0,
                NI_NUMERICHOST
            ) == 0 {
                let bytes = text.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
                addresses.append(String(decoding: bytes, as: UTF8.self))
            }
            node = current.pointee.ai_next
        }
        return addresses
    }
}
