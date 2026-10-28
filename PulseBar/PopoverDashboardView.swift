import SwiftUI
import AppKit

/// Native macOS Translucent Blur Layer + Specular Liquid Glass Sheen
struct LiquidGlassBackground: NSViewRepresentable {
    var forceDarkMode: Bool

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.state = .active
        view.material = forceDarkMode ? .hudWindow : .popover
        view.appearance = NSAppearance(named: forceDarkMode ? .vibrantDark : .vibrantLight)
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = forceDarkMode ? .hudWindow : .popover
        nsView.appearance = NSAppearance(named: forceDarkMode ? .vibrantDark : .vibrantLight)
    }
}

struct PopoverDashboardView: View {
    @ObservedObject var monitor: SystemMonitor

    var body: some View {
        ZStack {
            // Base Translucent OS Blur
            LiquidGlassBackground(forceDarkMode: monitor.forceDarkMode)
                .ignoresSafeArea()

            // Midnight Tint + Liquid Glass Specular Gradient Overlay
            LinearGradient(
                colors: monitor.forceDarkMode
                    ? [
                        Color(red: 0.04, green: 0.04, blue: 0.06).opacity(0.72),
                        Color(red: 0.12, green: 0.02, blue: 0.04).opacity(0.45),
                        Color.black.opacity(0.82)
                    ]
                    : [
                        Color.white.opacity(0.55),
                        Color.white.opacity(0.25)
                    ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 12) {
                // MARK: - Header
                HStack {
                    Image(systemName: "waveform.path.ecg.rectangle.fill")
                        .foregroundColor(.red)
                        .font(.system(size: 16))
                        .shadow(color: .red.opacity(0.5), radius: 6)
                    Text("PulseBar")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                    Spacer()
                    Text(String(format: "%.1fs poll", monitor.refreshInterval))
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule().stroke(Color.white.opacity(0.18), lineWidth: 0.5)
                        )
                }

                // MARK: - Core System Load Bars inside a Frosted Glass Card
                VStack(spacing: 10) {
                    DetailedMetricRow(
                        title: "CPU Usage",
                        subtitle: "Mach Kernel",
                        icon: "cpu",
                        percentage: monitor.cpuLoad,
                        isBattery: false
                    )

                    DetailedMetricRow(
                        title: "Memory",
                        subtitle: String(format: "%.1f / %.0f GB", monitor.memoryUsedGB, monitor.memoryTotalGB),
                        icon: "memorychip",
                        percentage: monitor.memoryUsage,
                        isBattery: false
                    )

                    DetailedMetricRow(
                        title: "GPU Load",
                        subtitle: "IOAccelerator",
                        icon: "display",
                        percentage: monitor.gpuLoad,
                        isBattery: false
                    )

                    DetailedMetricRow(
                        title: "Battery",
                        subtitle: monitor.isCharging ? "Charging • AC" : "On Battery",
                        icon: monitor.isCharging ? "battery.100.bolt" : "battery.100",
                        percentage: monitor.batteryLevel,
                        isBattery: true
                    )
                }
                .padding(11)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(monitor.forceDarkMode ? 0.04 : 0.4))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [Color.white.opacity(0.28), Color.white.opacity(0.04)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.8
                        )
                )

                // MARK: - Network Load Monitoring (Mbps)
                VStack(alignment: .leading, spacing: 6) {
                    Text("NETWORK THROUGHPUT (MBPS)")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundColor(.secondary)

                    HStack(spacing: 8) {
                        NetworkSpeedCard(
                            label: "Download ↓",
                            speedText: SystemMonitor.formatMbps(monitor.netDownloadBps),
                            icon: "arrow.down.circle.fill",
                            tint: Color(red: 0.19, green: 0.82, blue: 0.35),
                            darkMode: monitor.forceDarkMode
                        )
                        NetworkSpeedCard(
                            label: "Upload ↑",
                            speedText: SystemMonitor.formatMbps(monitor.netUploadBps),
                            icon: "arrow.up.circle.fill",
                            tint: Color(red: 1.00, green: 0.62, blue: 0.04),
                            darkMode: monitor.forceDarkMode
                        )
                    }
                }

                // MARK: - Menu Bar Customization & Settings
                VStack(alignment: .leading, spacing: 7) {
                    Text("MENU BAR & SYSTEM SETTINGS")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundColor(.secondary)

                    HStack {
                        Text("Slot 1")
                            .font(.system(size: 11.5))
                        Spacer()
                        Picker("", selection: $monitor.statSlot1) {
                            ForEach(StatType.allCases) { stat in
                                Text(stat.rawValue).tag(stat)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 205)
                    }

                    HStack {
                        Text("Slot 2")
                            .font(.system(size: 11.5))
                        Spacer()
                        Picker("", selection: $monitor.statSlot2) {
                            ForEach(StatType.allCases) { stat in
                                Text(stat.rawValue).tag(stat)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 205)
                    }

                    HStack {
                        Text("Poll Rate")
                            .font(.system(size: 11.5))
                        Spacer()
                        Picker("", selection: $monitor.refreshInterval) {
                            Text("1.5s").tag(1.5)
                            Text("2.5s").tag(2.5)
                            Text("5.0s").tag(5.0)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 205)
                    }

                    Toggle("Always Pin Stacked Net (Mbps) in Bar", isOn: $monitor.pinNetworkToMenuBar)
                        .font(.system(size: 11.5))
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .tint(.red)

                    HStack {
                        Toggle("Midnight Glass", isOn: $monitor.forceDarkMode)
                            .font(.system(size: 11.5))
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .tint(.red)

                        Spacer()

                        Toggle("Launch at Login", isOn: Binding(
                            get: { monitor.launchAtLogin },
                            set: { monitor.toggleLaunchAtLogin($0) }
                        ))
                        .font(.system(size: 11.5))
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .tint(.red)
                    }
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(monitor.forceDarkMode ? 0.035 : 0.35))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.14), lineWidth: 0.7)
                )

                // MARK: - Footer
                HStack {
                    Button("Activity Monitor") {
                        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
                    }
                    .buttonStyle(.link)
                    .font(.system(size: 11))

                    Spacer()

                    Button("Quit PulseBar") {
                        NSApplication.shared.terminate(nil)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .controlSize(.small)
                }
            }
            .padding(15)
        }
        .frame(width: 330)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.35),
                            Color.red.opacity(0.25),
                            Color.white.opacity(0.05)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .preferredColorScheme(monitor.forceDarkMode ? .dark : .light)
    }
}

struct DetailedMetricRow: View {
    let title: String
    let subtitle: String
    let icon: String
    let percentage: Double
    let isBattery: Bool

    private var barColor: Color {
        SystemMonitor.colorFor(value: percentage, isBattery: isBattery)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(barColor)
                    .frame(width: 15)
                Text(title)
                    .font(.system(size: 11.5, weight: .semibold))
                Text("• \(subtitle)")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Spacer()
                Text(String(format: "%.1f%%", percentage))
                    .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                    .foregroundColor(barColor)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.14))
                        .frame(height: 6)

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [barColor.opacity(0.75), barColor],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(
                            width: max(4, geo.size.width * CGFloat(min(max(percentage, 0), 100) / 100.0)),
                            height: 6
                        )
                        .shadow(color: barColor.opacity(0.55), radius: 4, x: 0, y: 0)
                        .animation(.easeInOut(duration: 0.35), value: percentage)
                }
            }
            .frame(height: 6)
        }
    }
}

struct NetworkSpeedCard: View {
    let label: String
    let speedText: String
    let icon: String
    let tint: Color
    let darkMode: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(tint)
                .shadow(color: tint.opacity(0.45), radius: 4)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundColor(.secondary)
                Text(speedText)
                    .font(.system(size: 11.5, weight: .bold, design: .monospaced))
            }
            Spacer()
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(darkMode ? 0.045 : 0.45))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [tint.opacity(0.4), Color.white.opacity(0.08)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.8
                )
        )
    }
}
