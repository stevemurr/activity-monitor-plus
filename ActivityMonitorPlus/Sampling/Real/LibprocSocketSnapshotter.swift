import Darwin
import Foundation

/// Native fallback for environments where a child `netstat` process cannot
/// read the kernel PCB tables. libproc exposes the sockets owned by processes
/// the current user may inspect, which is enough to keep lifecycle logging
/// functional without shelling out.
enum LibprocSocketSnapshotter {
    static func snapshot() -> [ConnectionSnapshot] {
        var pids = [pid_t](repeating: 0, count: 16_384)
        let listed = proc_listallpids(&pids,
                                      Int32(pids.count * MemoryLayout<pid_t>.size))
        guard listed > 0 else { return [] }

        var snapshots: [ConnectionSnapshot] = []
        for pid in pids.prefix(min(Int(listed), pids.count)) where pid > 0 {
            let name = processName(pid)
            for descriptor in socketDescriptors(pid: pid) {
                if let snapshot = socketSnapshot(pid: pid, name: name,
                                                 descriptor: descriptor) {
                    snapshots.append(snapshot)
                }
            }
        }
        return NetstatParser.filterNoise(snapshots)
    }

    private static func socketDescriptors(pid: pid_t) -> [proc_fdinfo] {
        let requiredBytes = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard requiredBytes > 0 else { return [] }
        var descriptors = [proc_fdinfo](
            repeating: proc_fdinfo(),
            count: Int(requiredBytes) / MemoryLayout<proc_fdinfo>.stride)
        let returnedBytes = descriptors.withUnsafeMutableBytes { buffer in
            proc_pidinfo(pid, PROC_PIDLISTFDS, 0, buffer.baseAddress,
                         Int32(buffer.count))
        }
        guard returnedBytes > 0 else { return [] }
        let count = min(Int(returnedBytes) / MemoryLayout<proc_fdinfo>.stride,
                        descriptors.count)
        return descriptors.prefix(count).filter {
            $0.proc_fdtype == UInt32(PROX_FDTYPE_SOCKET)
        }
    }

    private static func socketSnapshot(pid: pid_t, name: String,
                                       descriptor: proc_fdinfo) -> ConnectionSnapshot? {
        var fdInfo = socket_fdinfo()
        let size = MemoryLayout<socket_fdinfo>.size
        let returned = withUnsafeMutablePointer(to: &fdInfo) { pointer in
            proc_pidfdinfo(pid, descriptor.proc_fd, PROC_PIDFDSOCKETINFO,
                           pointer, Int32(size))
        }
        guard returned == size else { return nil }

        let socket = fdInfo.psi
        let proto: NetProto
        let internet: in_sockinfo
        var state: String?
        switch socket.soi_protocol {
        case IPPROTO_TCP where socket.soi_kind == SOCKINFO_TCP:
            proto = .tcp
            internet = socket.soi_proto.pri_tcp.tcpsi_ini
            state = tcpState(socket.soi_proto.pri_tcp.tcpsi_state)
        case IPPROTO_UDP where socket.soi_kind == SOCKINFO_IN:
            proto = .udp
            internet = socket.soi_proto.pri_in
        default:
            return nil
        }

        guard let local = endpoint(address: internet.insi_laddr,
                                   port: internet.insi_lport,
                                   flags: internet.insi_vflag),
              let remote = endpoint(address: internet.insi_faddr,
                                    port: internet.insi_fport,
                                    flags: internet.insi_vflag) else { return nil }

        return ConnectionSnapshot(
            key: ConnectionKey(proto: proto, local: local, remote: remote,
                               pid: Int32(pid)),
            processName: name, state: state, rxBytes: 0, txBytes: 0)
    }

    private static func endpoint(address: in_sockinfo.__Unnamed_union_insi_laddr,
                                 port: Int32, flags: UInt8) -> String? {
        if flags & UInt8(INI_IPV4) != 0 {
            return endpoint(ip: ipv4String(address.ina_46.i46a_addr4), port: port)
        }
        if flags & UInt8(INI_IPV6) != 0 {
            return endpoint(ip: ipv6String(address.ina_6), port: port)
        }
        return nil
    }

    private static func endpoint(address: in_sockinfo.__Unnamed_union_insi_faddr,
                                 port: Int32, flags: UInt8) -> String? {
        if flags & UInt8(INI_IPV4) != 0 {
            return endpoint(ip: ipv4String(address.ina_46.i46a_addr4), port: port)
        }
        if flags & UInt8(INI_IPV6) != 0 {
            return endpoint(ip: ipv6String(address.ina_6), port: port)
        }
        return nil
    }

    private static func endpoint(ip: String, port: Int32) -> String {
        let host = ip == "0.0.0.0" || ip == "::" ? "*" : ip
        let hostPort = UInt16(bigEndian: UInt16(truncatingIfNeeded: port))
        return "\(host).\(hostPort == 0 ? "*" : String(hostPort))"
    }

    private static func ipv4String(_ source: in_addr) -> String {
        var source = source
        var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        guard inet_ntop(AF_INET, &source, &buffer, socklen_t(buffer.count)) != nil
        else { return "0.0.0.0" }
        return decodedCString(buffer)
    }

    private static func ipv6String(_ source: in6_addr) -> String {
        var source = source
        var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
        guard inet_ntop(AF_INET6, &source, &buffer, socklen_t(buffer.count)) != nil
        else { return "::" }
        return decodedCString(buffer)
    }

    private static func processName(_ pid: pid_t) -> String {
        var buffer = [CChar](repeating: 0, count: 256)
        guard proc_name(pid, &buffer, UInt32(buffer.count)) > 0 else {
            return "pid \(pid)"
        }
        return decodedCString(buffer)
    }

    private static func decodedCString(_ buffer: [CChar]) -> String {
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }

    private static func tcpState(_ state: Int32) -> String {
        switch state {
        case TSI_S_CLOSED: "CLOSED"
        case TSI_S_LISTEN: "LISTEN"
        case TSI_S_SYN_SENT: "SYN_SENT"
        case TSI_S_SYN_RECEIVED: "SYN_RECEIVED"
        case TSI_S_ESTABLISHED: "ESTABLISHED"
        case TSI_S__CLOSE_WAIT: "CLOSE_WAIT"
        case TSI_S_FIN_WAIT_1: "FIN_WAIT_1"
        case TSI_S_CLOSING: "CLOSING"
        case TSI_S_LAST_ACK: "LAST_ACK"
        case TSI_S_FIN_WAIT_2: "FIN_WAIT_2"
        case TSI_S_TIME_WAIT: "TIME_WAIT"
        default: "UNKNOWN"
        }
    }
}
