import Darwin
import Foundation

/// Total CPU from host tick deltas; per-process CPU from libproc rusage deltas.
/// Both need two samples, so the first call reports zero usage.
final class LiveCPUSampler: CPUSampling {
    private let host = mach_host_self()
    private var timebase = mach_timebase_info_data_t()
    private var previousTicks: (user: UInt64, system: UInt64, idle: UInt64)?
    private var previousProcessTime: [Int32: Double] = [:]
    private var previousSampleTime: UInt64 = 0
    private var nameCache: [Int32: String] = [:]

    init() {
        mach_timebase_info(&timebase)
    }

    func sample() -> CPUSnapshot {
        let coreCount = ProcessInfo.processInfo.activeProcessorCount
        let (user, system) = sampleHostSplit()
        let processes = sampleProcesses(coreCount: coreCount)
        return CPUSnapshot(totalUsedFraction: user + system,
                           userFraction: user,
                           systemFraction: system,
                           coreCount: coreCount,
                           processes: processes)
    }

    // MARK: Host total

    private func sampleHostSplit() -> (user: Double, system: Double) {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(host, PROCESSOR_CPU_LOAD_INFO, &cpuCount,
                                  &info, &infoCount) == KERN_SUCCESS,
              let info else { return (0, 0) }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info),
                          vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.size))
        }

        var user: UInt64 = 0
        var system: UInt64 = 0
        var idle: UInt64 = 0
        for cpu in 0..<Int(cpuCount) {
            let base = cpu * Int(CPU_STATE_MAX)
            user += UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_USER)]))
            user += UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_NICE)]))
            system += UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_SYSTEM)]))
            idle += UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_IDLE)]))
        }

        defer { previousTicks = (user, system, idle) }
        guard let previous = previousTicks,
              user >= previous.user, system >= previous.system,
              idle >= previous.idle else { return (0, 0) }
        let deltaUser = user - previous.user
        let deltaSystem = system - previous.system
        let deltaTotal = deltaUser + deltaSystem + (idle - previous.idle)
        guard deltaTotal > 0 else { return (0, 0) }
        return (Double(deltaUser) / Double(deltaTotal),
                Double(deltaSystem) / Double(deltaTotal))
    }

    // MARK: Per-process

    private func sampleProcesses(coreCount: Int) -> [ProcessSample] {
        let now = mach_absolute_time()
        let wallDelta = machToNanoseconds(now &- previousSampleTime)
        let hasBaseline = previousSampleTime != 0
        previousSampleTime = now

        var pids = [pid_t](repeating: 0, count: 16384)
        let listed = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard listed > 0 else { return [] }

        var samples: [ProcessSample] = []
        var currentTimes: [Int32: Double] = [:]
        for pid in pids.prefix(min(Int(listed), pids.count)) where pid > 0 {
            var usage = rusage_info_current()
            let status = withUnsafeMutablePointer(to: &usage) {
                $0.withMemoryRebound(to: (rusage_info_t?).self, capacity: 1) {
                    proc_pid_rusage(pid, RUSAGE_INFO_CURRENT, $0)
                }
            }

            let name = processName(pid)
            guard status == KERN_SUCCESS else {
                // EPERM on other users' processes: visible, CPU unreadable.
                samples.append(ProcessSample(pid: pid, name: name,
                                             cpuFraction: nil, residentBytes: nil))
                continue
            }

            let cpuTime = machToNanoseconds(usage.ri_user_time &+ usage.ri_system_time)
            currentTimes[pid] = cpuTime

            var fraction: Double?
            if hasBaseline, wallDelta > 0, let prior = previousProcessTime[pid],
               cpuTime >= prior {
                fraction = Double(cpuTime - prior) / (wallDelta * Double(coreCount))
            }
            samples.append(ProcessSample(pid: pid, name: name,
                                         cpuFraction: fraction,
                                         residentBytes: usage.ri_resident_size))
        }
        previousProcessTime = currentTimes
        return samples
    }

    private func machToNanoseconds(_ value: UInt64) -> Double {
        Double(value) * Double(timebase.numer) / Double(timebase.denom)
    }

    private func processName(_ pid: pid_t) -> String {
        if let cached = nameCache[pid] { return cached }
        var buffer = [CChar](repeating: 0, count: 4096)
        var name: String?
        if proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 {
            name = (String(cString: buffer) as NSString).lastPathComponent
        } else {
            var short = [CChar](repeating: 0, count: 256)
            if proc_name(pid, &short, UInt32(short.count)) > 0 {
                name = String(cString: short)
            }
        }
        let resolved = name?.isEmpty == false ? name! : "pid \(pid)"
        nameCache[pid] = resolved
        if nameCache.count > 32768 { nameCache.removeAll() }
        return resolved
    }
}
