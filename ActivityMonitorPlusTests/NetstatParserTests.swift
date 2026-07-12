import XCTest
@testable import ActivityMonitorPlus

/// Sample output captured verbatim from `netstat -anv` on this machine (macOS 27).
private let tcpSample = """
Active Internet connections (including servers)
Proto Recv-Q Send-Q  Local Address          Foreign Address        (state)          rxbytes      txbytes  rhiwat  shiwat          process:pid    state  options           gencnt    flags   flags1 usecnt rtncnt fltrs
tcp4       0      0  192.168.1.231.57479    192.168.1.241.8883     ESTABLISHED            0            0  131600  131600      BambuStudio:4170   00102 00000000 0000000000228b52 00000080 04002900      2      0 000000
tcp6       0      0  2600:1700:1152:2.57478 2606:4700:4403::.443   ESTABLISHED         6100         3165  131072  132104  Codex (Service):21223  00102 00000008 0000000000228b27 00000080 04000900      2      0 000000
tcp4       0      0  192.168.1.231.57473    35.190.46.17.443       ESTABLISHED        11632          553  131072  131600          2.1.207:21664  00102 00000008 0000000000228ad9 00000081 04002900      2      0 000000
tcp4       0      0  127.0.0.1.53317        *.*                    LISTEN                 0            0  131072  131072         Fastmail:3601   00100 00000106 0000000000202999 00000001 00000800      1      0 000000
tcp4       0      0  127.0.0.1.52000        127.0.0.1.53317        ESTABLISHED          500          200  131072  131072         Fastmail:3601   00102 00000106 0000000000202aaa 00000001 00000800      1      0 000000
"""

private let udpSample = """
Active Internet connections (including servers)
Proto Recv-Q Send-Q  Local Address          Foreign Address        (state)          rxbytes      txbytes  rhiwat  shiwat          process:pid    state  options           gencnt    flags   flags1 usecnt rtncnt fltrs
udp4       0      0  *.41641                *.*                                       38400        16000 7340032 7340032     IPNExtension:71795  00100 00000020 0000000000226107 00000000 04000800      1      0 000002
udp4       0      0  *.2021                 *.*                                           0            0  786896    9216      BambuStudio:4170   00100 00000004 00000000001fcc26 20000000 00002800      2      0 000002
udp6       0      0  2607:fb91:2c72:9.5060  *.*                                      120446        17482  786896    9216       CommCenter:838    00000 00000000 00000000001fcc08 10000001 00000800      1      0 000002
"""

final class NetstatParserTests: XCTestCase {
    func testParsesTCPRows() {
        let rows = NetstatParser.parse(tcpSample)
        XCTAssertEqual(rows.count, 5)

        let bambu = rows[0]
        XCTAssertEqual(bambu.processName, "BambuStudio")
        XCTAssertEqual(bambu.key.pid, 4170)
        XCTAssertEqual(bambu.key.proto, .tcp)
        XCTAssertEqual(bambu.key.local, "192.168.1.231.57479")
        XCTAssertEqual(bambu.key.remote, "192.168.1.241.8883")
        XCTAssertEqual(bambu.state, "ESTABLISHED")
    }

    func testParsesProcessNameContainingSpaces() {
        let rows = NetstatParser.parse(tcpSample)
        let codex = rows[1]
        XCTAssertEqual(codex.processName, "Codex (Service)")
        XCTAssertEqual(codex.key.pid, 21223)
        XCTAssertEqual(codex.rxBytes, 6100)
        XCTAssertEqual(codex.txBytes, 3165)
    }

    func testParsesProcessNameContainingDots() {
        let rows = NetstatParser.parse(tcpSample)
        let dotted = rows[2]
        XCTAssertEqual(dotted.processName, "2.1.207")
        XCTAssertEqual(dotted.key.pid, 21664)
        XCTAssertEqual(dotted.rxBytes, 11632)
    }

    func testParsesUDPRowsWithoutStateColumn() {
        let rows = NetstatParser.parse(udpSample)
        XCTAssertEqual(rows.count, 3)

        let ipn = rows[0]
        XCTAssertNil(ipn.state)
        XCTAssertEqual(ipn.processName, "IPNExtension")
        XCTAssertEqual(ipn.key.pid, 71795)
        XCTAssertEqual(ipn.rxBytes, 38400)
        XCTAssertEqual(ipn.txBytes, 16000)
        XCTAssertEqual(ipn.key.proto, .udp)
    }

    func testUnrecognizedLayoutReturnsEmpty() {
        XCTAssertEqual(NetstatParser.parse("").count, 0)
        XCTAssertEqual(NetstatParser.parse("garbage\nmore garbage").count, 0)
        // Header present but expected columns missing → treat as drifted layout.
        let drifted = "Active Internet connections\nProto Recv-Q Send-Q Local Address Foreign Address\ntcp4 0 0 a.1 b.2"
        XCTAssertEqual(NetstatParser.parse(drifted).count, 0)
    }

    func testFilterNoiseDropsListenersIdleWildcardAndLoopback() {
        let tcp = NetstatParser.filterNoise(NetstatParser.parse(tcpSample))
        // LISTEN row and the loopback connection are gone.
        XCTAssertEqual(tcp.count, 3)
        XCTAssertFalse(tcp.contains { $0.state == "LISTEN" })
        XCTAssertFalse(tcp.contains { $0.key.remote.hasPrefix("127.") })

        let udp = NetstatParser.filterNoise(NetstatParser.parse(udpSample))
        // Idle *.* socket dropped; wildcard sockets with traffic kept.
        XCTAssertEqual(udp.count, 2)
        XCTAssertFalse(udp.contains { $0.processName == "BambuStudio" })
        XCTAssertTrue(udp.contains { $0.processName == "IPNExtension" })
    }
}
