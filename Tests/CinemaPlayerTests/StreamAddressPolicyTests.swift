import XCTest
@testable import CinemaPlayer

/// Literal addresses only, so none of this depends on DNS or a network.
final class StreamAddressPolicyTests: XCTestCase {
    func testBlocksLoopbackPrivateAndLinkLocalIPv4() {
        for address in [
            "0.0.0.0", "127.0.0.1", "127.13.2.9",
            "10.0.0.1", "10.255.255.255",
            "172.16.0.1", "172.31.255.255",
            "192.168.0.1", "192.168.1.1",
            "169.254.169.254",  // the cloud metadata service
            "100.64.0.1",       // carrier-grade NAT
            "192.0.0.1", "198.18.0.1", "224.0.0.1", "255.255.255.255",
        ] {
            XCTAssertTrue(StreamAddressPolicy.isPrivate(address), "\(address) should be blocked")
        }
    }

    func testAllowsOrdinaryPublicIPv4() {
        for address in ["8.8.8.8", "1.1.1.1", "93.184.216.34", "172.15.0.1", "172.32.0.1", "11.0.0.1"] {
            XCTAssertFalse(StreamAddressPolicy.isPrivate(address), "\(address) should be allowed")
        }
    }

    func testBlocksLoopbackUniqueLocalAndMappedIPv6() {
        for address in ["::1", "::", "fc00::1", "fd12:3456::1", "fe80::1", "ff02::1", "::ffff:127.0.0.1", "::ffff:192.168.1.1"] {
            XCTAssertTrue(StreamAddressPolicy.isPrivate(address), "\(address) should be blocked")
        }
    }

    func testAllowsPublicIPv6() {
        for address in ["2001:4860:4860::8888", "2606:4700:4700::1111", "::ffff:8.8.8.8"] {
            XCTAssertFalse(StreamAddressPolicy.isPrivate(address), "\(address) should be allowed")
        }
    }

    func testTreatsUnparseableAddressesAsPrivate() {
        XCTAssertTrue(StreamAddressPolicy.isPrivate("not-an-address"))
        XCTAssertTrue(StreamAddressPolicy.isPrivate(""))
    }

    func testRejectsLocalNamesWithoutALookup() {
        for link in ["http://localhost/v.mp4", "http://nas.local/v.mp4", "http://svc.internal/v.mp4", "http://x.home.arpa/v.mp4"] {
            guard case .blocked = StreamAddressPolicy.verdict(for: URL(string: link)!) else {
                return XCTFail("\(link) should be blocked")
            }
        }
    }

    func testRejectsLiteralPrivateAddressesAndOtherSchemes() {
        for link in ["http://127.0.0.1:8080/v.mp4", "http://[::1]/v.mp4", "http://192.168.1.1/v.mp4"] {
            guard case .blocked = StreamAddressPolicy.verdict(for: URL(string: link)!) else {
                return XCTFail("\(link) should be blocked")
            }
        }

        guard case .blocked = StreamAddressPolicy.verdict(for: URL(string: "ftp://8.8.8.8/v.mp4")!) else {
            return XCTFail("non-http schemes should be blocked")
        }
    }

    func testAllowsAPublicLiteralAddress() {
        XCTAssertEqual(StreamAddressPolicy.verdict(for: URL(string: "https://93.184.216.34/v.mp4")!), .allowed)
    }
}
