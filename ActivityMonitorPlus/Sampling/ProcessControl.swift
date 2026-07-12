import Darwin
import Foundation

enum TerminateOutcome: Equatable, Sendable {
    case success
    case permissionDenied
    case notFound
    case failed(errno: Int32)

    var errorDescription: String? {
        switch self {
        case .success: nil
        case .permissionDenied: "you don't have permission (owned by another user)"
        case .notFound: "the process no longer exists"
        case .failed(let code): "kill failed (errno \(code))"
        }
    }
}

struct ProcessDetails: Sendable {
    var pid: Int32
    var name: String
    var path: String?
    var parentPid: Int32?
    var user: String?
    var startDate: Date?
}

protocol ProcessControlling: Sendable {
    func terminate(pid: Int32, force: Bool) -> TerminateOutcome
    func details(pid: Int32, name: String) -> ProcessDetails
}

final class LiveProcessController: ProcessControlling {
    func terminate(pid: Int32, force: Bool) -> TerminateOutcome {
        guard kill(pid, force ? SIGKILL : SIGTERM) == 0 else {
            switch errno {
            case EPERM: return .permissionDenied
            case ESRCH: return .notFound
            default: return .failed(errno: errno)
            }
        }
        return .success
    }

    func details(pid: Int32, name: String) -> ProcessDetails {
        var details = ProcessDetails(pid: pid, name: name)

        var buffer = [CChar](repeating: 0, count: 4096)
        if proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 {
            details.path = String(cString: buffer)
        }

        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        if proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size {
            details.parentPid = Int32(bitPattern: info.pbi_ppid)
            details.startDate = Date(timeIntervalSince1970: TimeInterval(info.pbi_start_tvsec))
            if let passwd = getpwuid(info.pbi_uid) {
                details.user = String(cString: passwd.pointee.pw_name)
            }
        }
        return details
    }
}
