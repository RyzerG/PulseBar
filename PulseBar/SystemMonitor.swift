import Foundation
import Combine
import Darwin
import IOKit
import IOKit.ps
import ServiceManagement
import SwiftUI

enum StatType: String, CaseIterable, Identifiable {
    case cpu = "CPU"
    case memory = "RAM"
    case gpu = "GPU"
    case battery = "BAT"
    case network = "NET"
    var id: String { self.rawValue }
}

final class SystemMonitor: ObservableObject {
    // Telemetry Published States (0.0 to 100.0)
    @Published var cpuLoad: Double = 0.0
    @Published var memoryUsage: Double = 0.0
    @Published var memoryUsedGB: Double = 0.0
    @Published var memoryTotalGB: Double = 0.0
    @Published var gpuLoad: Double = 0.0
    
    // Battery States
    @Published var batteryLevel: Double = 100.0
    @Published var isCharging: Bool = false
    
    // Network Throughput (Bytes per second)
    @Published var netDownloadBps: Double = 0.0
    @Published var netUploadBps: Double = 0.0
    
    // User Preferences (Persisted via UserDefaults)
    @Published var statSlot1: StatType {
        didSet { UserDefaults.standard.set(statSlot1.rawValue, forKey: "statSlot1") }
    }
    @Published var statSlot2: StatType {
        didSet { UserDefaults.standard.set(statSlot2.rawValue, forKey: "statSlot2") }
    }
    @Published var pinNetworkToMenuBar: Bool {
        didSet { UserDefaults.standard.set(pinNetworkToMenuBar, forKey: "pinNetworkToMenuBar") }
    }
    @Published var refreshInterval: Double {
        didSet {
            UserDefaults.standard.set(refreshInterval, forKey: "refreshInterval")
            restartTimer()
        }
    }
    @Published var forceDarkMode: Bool {
        didSet { UserDefaults.standard.set(forceDarkMode, forKey: "forceDarkMode") }
    }
    @Published var launchAtLogin: Bool = false

    private var timer: Timer?
    private var prevCPUInfo: processor_info_array_t?
    private var prevCPUInfoCount: mach_msg_type_number_t = 0
    private var prevNetInBytes: UInt64 = 0
    private var prevNetOutBytes: UInt64 = 0
    private var prevNetTimestamp: TimeInterval = 0

    init() {
        let savedSlot1 = UserDefaults.standard.string(forKey: "statSlot1") ?? StatType.cpu.rawValue
        let savedSlot2 = UserDefaults.standard.string(forKey: "statSlot2") ?? StatType.memory.rawValue
        let savedInterval = UserDefaults.standard.double(forKey: "refreshInterval")
        
        self.statSlot1 = StatType(rawValue: savedSlot1) ?? .cpu
        self.statSlot2 = StatType(rawValue: savedSlot2) ?? .memory
        self.refreshInterval = savedInterval > 0 ? savedInterval : 2.5
        
        if UserDefaults.standard.object(forKey: "pinNetworkToMenuBar") == nil {
            self.pinNetworkToMenuBar = true // Show stacked Mbps in menu bar by default
        } else {
            self.pinNetworkToMenuBar = UserDefaults.standard.bool(forKey: "pinNetworkToMenuBar")
        }
        
        if UserDefaults.standard.object(forKey: "forceDarkMode") == nil {
            self.forceDarkMode = true
        } else {
            self.forceDarkMode = UserDefaults.standard.bool(forKey: "forceDarkMode")
        }
        
        self.memoryTotalGB = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824.0
        self.launchAtLogin = (SMAppService.mainApp.status == .enabled)
        
        updateAllMetrics()
        restartTimer()
    }

    func toggleLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLogin = (SMAppService.mainApp.status == .enabled)
        } catch {
            print("Launch at Login toggle failed: \(error)")
        }
    }

    func restartTimer() {
        timer?.invalidate()
        let newTimer = Timer(timeInterval: refreshInterval, repeats: true) { [weak self] _ in
            self?.updateAllMetrics()
        }
        newTimer.tolerance = 0.5
        RunLoop.main.add(newTimer, forMode: .common)
        timer = newTimer
    }

    func value(for stat: StatType) -> Double {
        switch stat {
        case .cpu: return cpuLoad
        case .memory: return memoryUsage
        case .gpu: return gpuLoad
        case .battery: return batteryLevel
        case .network: return networkLoadPercentage
        }
    }

    /// Converts combined network throughput into a 0-100% scale (scaled against a 100 Mbps ceiling) for the mini load bar
    var networkLoadPercentage: Double {
        let totalMbps = ((netDownloadBps + netUploadBps) * 8.0) / 1_000_000.0
        return min(max((totalMbps / 100.0) * 100.0, 0.0), 100.0)
    }

    /// Maps load (or inverse battery level) to Green, Orange, or Red
    static func colorFor(value: Double, isBattery: Bool = false) -> Color {
        if isBattery {
            if value > 40 { return Color(red: 0.19, green: 0.82, blue: 0.35) } // Green
            if value > 15 { return Color(red: 1.00, green: 0.62, blue: 0.04) } // Orange
            return Color(red: 1.00, green: 0.27, blue: 0.23) // Red
        } else {
            if value < 60 { return Color(red: 0.19, green: 0.82, blue: 0.35) } // Green
            if value < 85 { return Color(red: 1.00, green: 0.62, blue: 0.04) } // Orange
            return Color(red: 1.00, green: 0.27, blue: 0.23) // Red
        }
    }

    /// Formats Bytes/sec into Megabits per second (Mbps) for compact menu bar and cards
    static func formatMbps(_ bytesPerSec: Double, compact: Bool = false) -> String {
        let mbps = (bytesPerSec * 8.0) / 1_000_000.0
        if compact {
            if mbps < 0.1 && mbps > 0 {
                return "0.1M"
            } else if mbps < 10.0 {
                return String(format: "%.1fM", mbps)
            } else {
                return String(format: "%.0fM", mbps)
            }
        } else {
            if mbps < 1.0 {
                return String(format: "%.2f Mbps", mbps)
            } else if mbps < 100.0 {
                return String(format: "%.1f Mbps", mbps)
            } else {
                return String(format: "%.0f Mbps", mbps)
            }
        }
    }

    func updateAllMetrics() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            let cpu = self.readCPULoad()
            let (memPct, memGB) = self.readMemoryUsage()
            let gpu = self.readGPULoad()
            let (batLevel, charging) = self.readBatteryInfo()
            let (downBps, upBps) = self.readNetworkThroughput()
            
            DispatchQueue.main.async {
                self.cpuLoad = cpu
                self.memoryUsage = memPct
                self.memoryUsedGB = memGB
                self.gpuLoad = gpu
                self.batteryLevel = batLevel
                self.isCharging = charging
                self.netDownloadBps = downBps
                self.netUploadBps = upBps
            }
        }
    }

    // MARK: - 1. CPU Load
    private func readCPULoad() -> Double {
        var numCPUsU: natural_t = 0
        var cpuInfo: processor_info_array_t?
        var numCPUInfoCount: mach_msg_type_number_t = 0
        
        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &numCPUsU,
            &cpuInfo,
            &numCPUInfoCount
        )
        guard result == KERN_SUCCESS, let info = cpuInfo else { return 0.0 }
        
        var totalInUse: Int32 = 0
        var totalTicks: Int32 = 0
        
        if let prev = prevCPUInfo {
            for i in 0..<Int(numCPUsU) {
                let base = Int(CPU_STATE_MAX) * i
                let userDiff = info[base + Int(CPU_STATE_USER)] - prev[base + Int(CPU_STATE_USER)]
                let sysDiff  = info[base + Int(CPU_STATE_SYSTEM)] - prev[base + Int(CPU_STATE_SYSTEM)]
                let niceDiff = info[base + Int(CPU_STATE_NICE)] - prev[base + Int(CPU_STATE_NICE)]
                let idleDiff = info[base + Int(CPU_STATE_IDLE)] - prev[base + Int(CPU_STATE_IDLE)]
                
                let inUse = userDiff + sysDiff + niceDiff
                let total = inUse + idleDiff
                totalInUse += inUse
                totalTicks += total
            }
            let prevSize = vm_size_t(prevCPUInfoCount) * vm_size_t(MemoryLayout<integer_t>.stride)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: prev), prevSize)
        }
        
        prevCPUInfo = info
        prevCPUInfoCount = numCPUInfoCount
        
        guard totalTicks > 0 else { return 0.0 }
        return min(max((Double(totalInUse) / Double(totalTicks)) * 100.0, 0.0), 100.0)
    }

    // MARK: - 2. Memory Load
    private func readMemoryUsage() -> (Double, Double) {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return (0.0, 0.0) }
        
        let pageSize = Double(vm_kernel_page_size)
        let active = Double(stats.active_count) * pageSize
        let wired = Double(stats.wire_count) * pageSize
        let compressed = Double(stats.compressor_page_count) * pageSize
        
        let usedBytes = active + wired + compressed
        let totalBytes = Double(ProcessInfo.processInfo.physicalMemory)
        
        let pct = min(max((usedBytes / totalBytes) * 100.0, 0.0), 100.0)
        let usedGB = usedBytes / 1_073_741_824.0
        return (pct, usedGB)
    }

    // MARK: - 3. GPU Load
    private func readGPULoad() -> Double {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("IOAccelerator"),
            &iterator
        ) == kIOReturnSuccess else { return 0.0 }
        defer { IOObjectRelease(iterator) }
        
        var service = IOIteratorNext(iterator)
        while service != 0 {
            var props: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == kIOReturnSuccess,
               let dict = props?.takeRetainedValue() as? [String: Any],
               let perfStats = dict["PerformanceStatistics"] as? [String: Any] {
                
                let utilization = (perfStats["Device Utilization %"] as? NSNumber)?.doubleValue
                    ?? (perfStats["GPU Activity(%)"] as? NSNumber)?.doubleValue
                    ?? (perfStats["Renderer Utilization %"] as? NSNumber)?.doubleValue
                
                if let validUsage = utilization {
                    IOObjectRelease(service)
                    return min(max(validUsage, 0.0), 100.0)
                }
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        return 0.0
    }

    // MARK: - 4. Battery Info
    private func readBatteryInfo() -> (Double, Bool) {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else {
            return (100.0, false)
        }
        for source in sources {
            if let desc = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any],
               let cur = desc[kIOPSCurrentCapacityKey] as? Double,
               let maxCap = desc[kIOPSMaxCapacityKey] as? Double, maxCap > 0 {
                let isCharging = (desc[kIOPSIsChargingKey] as? Bool) ?? false
                return ((cur / maxCap) * 100.0, isCharging)
            }
        }
        return (100.0, false)
    }

    // MARK: - 5. Network Throughput
    private func readNetworkThroughput() -> (Double, Double) {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return (0.0, 0.0) }
        defer { freeifaddrs(ifaddr) }
        
        var totalIn: UInt64 = 0
        var totalOut: UInt64 = 0
        var ptr: UnsafeMutablePointer<ifaddrs>? = firstAddr
        
        while let current = ptr {
            let name = String(cString: current.pointee.ifa_name)
            if name.hasPrefix("en"),
               let addr = current.pointee.ifa_addr,
               addr.pointee.sa_family == UInt8(AF_LINK),
               let data = current.pointee.ifa_data {
                let networkData = data.assumingMemoryBound(to: if_data.self).pointee
                totalIn += UInt64(networkData.ifi_ibytes)
                totalOut += UInt64(networkData.ifi_obytes)
            }
            ptr = current.pointee.ifa_next
        }
        
        let now = Date().timeIntervalSince1970
        defer {
            prevNetInBytes = totalIn
            prevNetOutBytes = totalOut
            prevNetTimestamp = now
        }
        
        guard prevNetTimestamp > 0, now > prevNetTimestamp else { return (0.0, 0.0) }
        let elapsed = now - prevNetTimestamp
        let diffIn = totalIn >= prevNetInBytes ? Double(totalIn - prevNetInBytes) : 0.0
        let diffOut = totalOut >= prevNetOutBytes ? Double(totalOut - prevNetOutBytes) : 0.0
        
        return (diffIn / elapsed, diffOut / elapsed)
    }
}
