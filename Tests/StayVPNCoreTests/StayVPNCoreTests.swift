import XCTest
@testable import StayVPNCore

final class WGConfigTests: XCTestCase {
    let good = """
    [Interface]
    # Key for stay-mac
    PrivateKey = aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa=
    Address = 10.2.0.2/32
    DNS = 10.2.0.1

    [Peer]
    PublicKey = bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb=
    AllowedIPs = 0.0.0.0/0, ::/0
    Endpoint = 203.0.113.7:51820
    """

    func testAcceptsNormalConfig() throws {
        XCTAssertEqual(try WGConfig.validate(good).endpoint, "203.0.113.7:51820")
    }

    func testAcceptsWindowsLineEndings() throws {
        XCTAssertNoThrow(try WGConfig.validate(good.replacingOccurrences(of: "\n", with: "\r\n")))
    }

    func testRejectsHookLines() {
        for key in ["PostUp", "PreUp", "PostDown", "PreDown", "postup", "  POSTUP ", "SaveConfig"] {
            let bad = good.replacingOccurrences(of: "DNS = 10.2.0.1", with: "\(key) = touch /tmp/pwned")
            XCTAssertThrowsError(try WGConfig.validate(bad), key) { error in
                guard case WGConfig.ValidationError.forbiddenLine = error else {
                    return XCTFail("wrong error for \(key): \(error)")
                }
            }
        }
    }

    func testCommentedHookLineIsFine() {
        let text = good + "\n# PostUp = something\n"
        XCTAssertNoThrow(try WGConfig.validate(text))
    }

    func testRejectsEmptyAndNonConfigs() {
        XCTAssertThrowsError(try WGConfig.validate("  \n")) { XCTAssertEqual($0 as? WGConfig.ValidationError, .empty) }
        XCTAssertThrowsError(try WGConfig.validate("hello world")) {
            XCTAssertEqual($0 as? WGConfig.ValidationError, .missingSection("Interface"))
        }
        let noPeer = good.components(separatedBy: "[Peer]")[0]
        XCTAssertThrowsError(try WGConfig.validate(noPeer)) {
            XCTAssertEqual($0 as? WGConfig.ValidationError, .missingSection("Peer"))
        }
    }

    func testRejectsMissingKeys() {
        let noEndpoint = good.replacingOccurrences(of: "Endpoint = 203.0.113.7:51820", with: "")
        XCTAssertThrowsError(try WGConfig.validate(noEndpoint)) {
            XCTAssertEqual($0 as? WGConfig.ValidationError, .missingKey("the peer's Endpoint"))
        }
    }

    func testRejectsOversizedFile() {
        let huge = good + String(repeating: "# padding\n", count: 10_000)
        XCTAssertThrowsError(try WGConfig.validate(huge)) { XCTAssertEqual($0 as? WGConfig.ValidationError, .tooLarge) }
    }
}

final class ProfileNameTests: XCTestCase {
    func testValidNames() {
        for name in ["proton", "proton-nl", "warp", "a", "abcdefghijkl"] {
            XCTAssertTrue(ProfileName.isValid(name), name)
        }
    }

    func testInvalidNames() {
        for name in ["", "Proton", "a b", "../etc", "a/b", "-a", "a-", "abcdefghijklm", "a.conf", "naïve"] {
            XCTAssertFalse(ProfileName.isValid(name), name)
        }
    }

    func testSanitizeAlwaysYieldsValidName() {
        let inputs = ["Proton NL-FREE#12.conf", "wgcf-profile.conf", "../../etc/passwd", "---", "", "ÜBER.conf",
                      "a-very-long-file-name-indeed.conf", "abcdefghijk-z.conf"]
        for input in inputs {
            let name = ProfileName.sanitize(input)
            XCTAssertTrue(ProfileName.isValid(name), "\(input) -> \(name)")
        }
        XCTAssertEqual(ProfileName.sanitize("Proton NL-FREE#12.conf"), "proton-nl-fr")
        XCTAssertEqual(ProfileName.sanitize("wgcf-profile.conf"), "wgcf-profile")
        XCTAssertEqual(ProfileName.sanitize("---"), "vpn")
    }
}

final class StatusParserTests: XCTestCase {
    func testParsesConnectedTunnel() {
        let output = """
        profile=proton-nl
        endpoint=203.0.113.7:51820
        handshake=1700000000
        rx=12345678
        tx=2345
        --

        """
        let status = StatusParser.parse(output)
        XCTAssertEqual(status, [TunnelStatus(
            profile: "proton-nl", endpoint: "203.0.113.7:51820",
            lastHandshake: Date(timeIntervalSince1970: 1_700_000_000),
            bytesReceived: 12_345_678, bytesSent: 2345)])
    }

    func testNoHandshakeYet() {
        let status = StatusParser.parse("profile=warp\nendpoint=(none)\nhandshake=0\nrx=0\ntx=0\n--\n")
        XCTAssertEqual(status.count, 1)
        XCTAssertNil(status[0].lastHandshake)
        XCTAssertNil(status[0].endpoint)
        XCTAssertFalse(status[0].isLive())
    }

    func testEmptyOutputMeansDisconnected() {
        XCTAssertTrue(StatusParser.parse("").isEmpty)
        XCTAssertTrue(StatusParser.parse("\n\n").isEmpty)
    }

    func testIPv6EndpointKeepsItsEqualsFreeValue() {
        let status = StatusParser.parse("profile=a\nendpoint=[2001:db8::1]:51820\nhandshake=5\nrx=1\ntx=2\n--")
        XCTAssertEqual(status.first?.endpoint, "[2001:db8::1]:51820")
    }

    func testLiveness() {
        let now = Date()
        func tunnel(_ ago: TimeInterval) -> TunnelStatus {
            TunnelStatus(profile: "a", endpoint: nil, lastHandshake: now.addingTimeInterval(-ago), bytesReceived: 0, bytesSent: 0)
        }
        XCTAssertTrue(tunnel(30).isLive(now: now))
        XCTAssertFalse(tunnel(600).isLive(now: now))
    }

    func testParseProfilesDropsJunk() {
        XCTAssertEqual(StatusParser.parseProfiles("warp\nproton-nl\n\n../bad\n"), ["proton-nl", "warp"])
    }
}

final class HelperErrorTests: XCTestCase {
    func testMapsSudoPasswordPromptToSetupNeeded() {
        XCTAssertEqual(HelperClient.error(exitCode: 1, stderr: "sudo: a password is required\n"), .setupNeeded)
    }

    func testMapsToolsMissingExitCode() {
        XCTAssertEqual(HelperClient.error(exitCode: 3, stderr: "error: WireGuard tools not installed\n"), .toolsMissing)
    }

    func testPrefersHelperErrorLine() {
        let stderr = "[#] wireguard-go utun\nerror: config contains a PostUp line\nsome trailing noise\n"
        XCTAssertEqual(HelperClient.error(exitCode: 2, stderr: stderr), .failed("config contains a PostUp line"))
    }

    func testFallsBackToLastLine() {
        XCTAssertEqual(HelperClient.error(exitCode: 1, stderr: "a\nb\n"), .failed("b"))
        XCTAssertEqual(HelperClient.error(exitCode: 7, stderr: ""), .failed("The helper failed (exit code 7)."))
    }
}

final class ProfileStoreTests: XCTestCase {
    func testPreferredOrder() {
        let defaults = UserDefaults(suiteName: "stayvpn-tests-\(UUID().uuidString)")!
        let store = ProfileStore(defaults: defaults)
        XCTAssertEqual(store.preferred(among: ["a", "b"], active: nil), "a")
        store.lastUsed = "b"
        XCTAssertEqual(store.preferred(among: ["a", "b"], active: nil), "b")
        XCTAssertEqual(store.preferred(among: ["a", "b"], active: "a"), "a")
        XCTAssertEqual(store.preferred(among: ["a"], active: nil), "a")
        XCTAssertNil(store.preferred(among: [], active: nil))
    }
}

final class SpeedTestTests: XCTestCase {
    func testParsesNetworkQualityJSON() throws {
        let json = #"{"base_rtt": 23.4, "dl_throughput": 85400000, "ul_throughput": 7300000, "responsiveness": 512}"#
        let result = try SpeedTest.parse(Data(json.utf8))
        XCTAssertEqual(result.downloadMbps, 85.4, accuracy: 0.001)
        XCTAssertEqual(result.uploadMbps, 7.3, accuracy: 0.001)
        XCTAssertEqual(result.latencyMs, 23.4)
        XCTAssertEqual(result.summary, "↓ 85  ↑ 7.3 Mbps  ·  23 ms")
    }

    func testLatencyIsOptional() throws {
        let result = try SpeedTest.parse(Data(#"{"dl_throughput": 1000000, "ul_throughput": 500000}"#.utf8))
        XCTAssertNil(result.latencyMs)
        XCTAssertEqual(result.summary, "↓ 1.0  ↑ 0.5 Mbps")
    }

    func testRejectsEmptyOrFailedRuns() {
        XCTAssertThrowsError(try SpeedTest.parse(Data()))
        XCTAssertThrowsError(try SpeedTest.parse(Data("not json".utf8)))
        XCTAssertThrowsError(try SpeedTest.parse(Data(#"{"dl_throughput": 0, "ul_throughput": 0}"#.utf8)))
        XCTAssertThrowsError(try SpeedTest.parse(Data(#"{"error": "offline"}"#.utf8)))
    }
}
