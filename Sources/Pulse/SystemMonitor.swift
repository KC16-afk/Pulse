import Foundation
import Darwin
#if canImport(IOKit)
import IOKit
import IOKit.ps
#endif

// MARK: - Models

struct Battery {
    let level: Double      // 0...1
    let charging: Bool
}

struct ProcessSample: Identifiable {
    let id: Int32
    let pid: Int32
    let name: String
    let cpu: Double        // fraction of total machine capacity
}

struct SystemSnapshot {
    let cpu: Double
    let cpuUser: Double
    let cpuSystem: Double
    let cpuIdle: Double
    let cpuHistory: [Double]
    let memoryUsed: UInt64
    let memoryTotal: UInt64
    let networkDown: Double   // bytes per second
    let networkUp: Double
    let battery: Battery?
    let processes: [ProcessSample]
    let date: Date
}

// MARK: - Monitor

final class SystemMonitor: ObservableObject {
    @Published var snapshot = SystemSnapshot(
        cpu: 0, cpuUser: 0, cpuSystem: 0, cpuIdle: 1,
        cpuHistory: Array(repeating: 0.04, count: 48),
        memoryUsed: 0, memoryTotal: 1,
        networkDown: 0, networkUp: 0,
        battery: nil, processes: [], date: Date()
    )

    /// Called on the main thread after every refresh (used to update the menu bar image).
    var onUpdate: ((SystemSnapshot) -> Void)?

    private var timer: Timer?
    private var lastCPUTicks: CpuTicks?
    private var lastNetwork: NetworkBytes?
    private var lastProcessTicks: [Int32: UInt64] = [:]
    private var lastRefresh = Date()
    private var history: [Double] = Array(repeating: 0.04, count: 48)

    private struct CpuTicks {
        let user: UInt64, system: UInt64, idle: UInt64, nice: UInt64
    }

    private struct NetworkBytes {
        let input: UInt32, output: UInt32
    }

    init() {
        lastCPUTicks = Self.readCPUTicks()
        lastNetwork = Self.readNetworkBytes()
        lastProcessTicks = Self.readProcessTicks()
        refresh()
        let t = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    deinit {
        timer?.invalidate()
    }

    @objc func refresh() {
        let now = Date()
        let elapsed = max(now.timeIntervalSince(lastRefresh), 0.05)
        lastRefresh = now

        let cpu = Self.cpuSample(previous: &lastCPUTicks)
        history.append(cpu.total)
        if history.count > 48 { history.removeFirst(history.count - 48) }

        let memory = Self.memoryInfo()
        let network = Self.networkRates(previous: &lastNetwork, elapsed: elapsed)
        let battery = Self.batteryInfo()
        let processes = Self.topProcesses(previous: &lastProcessTicks, elapsed: elapsed)

        let snapshot = SystemSnapshot(
            cpu: cpu.total,
            cpuUser: cpu.user,
            cpuSystem: cpu.system,
            cpuIdle: cpu.idle,
            cpuHistory: history,
            memoryUsed: memory.used,
            memoryTotal: memory.total,
            networkDown: network.down,
            networkUp: network.up,
            battery: battery,
            processes: processes,
            date: now
        )

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.snapshot = snapshot
            self.onUpdate?(snapshot)
        }
    }

    // MARK: CPU

    private static func readCPUTicks() -> CpuTicks? {
        var info = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size
        )
        let kr = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { p in
                host_statistics(mach_host_self(), host_flavor_t(HOST_CPU_LOAD_INFO), p, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return nil }
        // Tuple order follows CPU_STATE_USER / SYSTEM / IDLE / NICE.
        return CpuTicks(
            user: UInt64(info.cpu_ticks.0),
            system: UInt64(info.cpu_ticks.1),
            idle: UInt64(info.cpu_ticks.2),
            nice: UInt64(info.cpu_ticks.3)
        )
    }

    private static func cpuSample(previous: inout CpuTicks?) -> (total: Double, user: Double, system: Double, idle: Double) {
        guard let current = readCPUTicks(), let prev = previous else {
            return (0, 0, 0, 1)
        }
        previous = current
        let u = current.user &- prev.user
        let s = current.system &- prev.system
        let i = current.idle &- prev.idle
        let n = current.nice &- prev.nice
        let total = u + s + i + n
        guard total > 0 else { return (0, 0, 0, 1) }
        let idleFraction = Double(i) / Double(total)
        return (
            min(max(1 - idleFraction, 0), 1),
            Double(u) / Double(total),
            Double(s) / Double(total),
            idleFraction
        )
    }

    // MARK: Memory

    private static func memoryInfo() -> (used: UInt64, total: UInt64) {
        var total: UInt64 = 0
        var totalSize = MemoryLayout<UInt64>.size
        sysctlbyname("hw.memsize", &total, &totalSize, nil, 0)

        var pageSize: UInt64 = 4096
        var pageCount = MemoryLayout<UInt64>.size
        sysctlbyname("hw.pagesize", &pageSize, &pageCount, nil, 0)

        var vm = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size
        )
        let kr = withUnsafeMutablePointer(to: &vm) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { p in
                host_statistics64(mach_host_self(), host_flavor_t(HOST_VM_INFO64), p, &count)
            }
        }
        guard kr == KERN_SUCCESS, total > 0 else { return (0, total) }

        let free = UInt64(vm.free_count) * pageSize
        let inactive = UInt64(vm.inactive_count) * pageSize
        let used = total > free + inactive ? total - free - inactive : 0
        return (used, total)
    }

    // MARK: Network

    private static func readNetworkBytes() -> NetworkBytes {
        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0, let first = addresses else {
            return NetworkBytes(input: 0, output: 0)
        }
        var input: UInt32 = 0
        var output: UInt32 = 0
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let current = cursor {
            let name = String(cString: current.pointee.ifa_name)
            let family = current.pointee.ifa_addr?.pointee.sa_family ?? 0
            if !name.hasPrefix("lo") && (Int32(family) == AF_INET || Int32(family) == AF_INET6),
               let data = current.pointee.ifa_data {
                let d = data.assumingMemoryBound(to: if_data.self).pointee
                input &+= d.ifi_ibytes
                output &+= d.ifi_obytes
            }
            cursor = current.pointee.ifa_next
        }
        freeifaddrs(first)
        return NetworkBytes(input: input, output: output)
    }

    private static func networkRates(previous: inout NetworkBytes?, elapsed: Double) -> (down: Double, up: Double) {
        let current = readNetworkBytes()
        defer { previous = current }
        guard let prev = previous else { return (0, 0) }
        // UInt32 counters wrap; wrapping subtraction gives the correct delta.
        let down = Double(current.input &- prev.input) / elapsed
        let up = Double(current.output &- prev.output) / elapsed
        return (down, up)
    }

    // MARK: Battery

    private static func batteryInfo() -> Battery? {
        #if canImport(IOKit)
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else {
            return nil
        }
        for source in list {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  let current = description[kIOPSCurrentCapacityKey as String] as? Int,
                  let capacity = description[kIOPSMaxCapacityKey as String] as? Int,
                  capacity > 0 else { continue }
            let charging = description[kIOPSIsChargingKey as String] as? Bool ?? false
            return Battery(
                level: min(max(Double(current) / Double(capacity), 0), 1),
                charging: charging
            )
        }
        return nil
        #else
        return nil
        #endif
    }

    // MARK: Processes

    private static func readProcessTicks() -> [Int32: UInt64] {
        let count = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard count > 0 else { return [:] }
        let capacity = Int(count) + 32
        var pids = [Int32](repeating: 0, count: capacity)
        let actual = proc_listpids(
            UInt32(PROC_ALL_PIDS), 0, &pids,
            Int32(capacity * MemoryLayout<Int32>.size)
        )
        guard actual > 0 else { return [:] }

        var result: [Int32: UInt64] = [:]
        let validCount = Int(actual) / MemoryLayout<Int32>.size
        for pid in pids.prefix(validCount) where pid > 0 {
            var info = proc_taskinfo()
            let size = proc_pidinfo(
                pid, Int32(PROC_PIDTASKINFO), 0,
                &info, Int32(MemoryLayout<proc_taskinfo>.size)
            )
            if size == MemoryLayout<proc_taskinfo>.size {
                result[pid] = info.pti_total_user + info.pti_total_system
            }
        }
        return result
    }

    private static func processName(_ pid: Int32) -> String {
        var buffer = [CChar](repeating: 0, count: Int(MAXCOMLEN) + 1)
        let written = proc_name(pid, &buffer, UInt32(buffer.count))
        return written > 0 ? String(cString: buffer) : "PID \(pid)"
    }

    private static func topProcesses(previous: inout [Int32: UInt64], elapsed: Double) -> [ProcessSample] {
        let current = readProcessTicks()
        defer { previous = current }

        let cores = Double(ProcessInfo.processInfo.activeProcessorCount)
        let deltas = current.compactMap { pid, now -> (pid: Int32, nanos: UInt64)? in
            guard let before = previous[pid], now > before else { return nil }
            return (pid, now - before)
        }
        let top = deltas.sorted { $0.nanos > $1.nanos }.prefix(5)

        return top.map { sample in
            ProcessSample(
                id: sample.pid,
                pid: sample.pid,
                name: processName(sample.pid),
                cpu: Double(sample.nanos) / 1_000_000_000 / elapsed / cores
            )
        }
    }
}
