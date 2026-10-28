import SwiftUI

struct MenuBarLabelView: View {
    @ObservedObject var monitor: SystemMonitor

    var body: some View {
        HStack(spacing: 8) {
            MenuStatPill(
                type: monitor.statSlot1,
                value: monitor.value(for: monitor.statSlot1),
                downBps: monitor.netDownloadBps,
                upBps: monitor.netUploadBps
            )
            
            Divider()
                .frame(height: 12)
                .opacity(0.35)
            
            MenuStatPill(
                type: monitor.statSlot2,
                value: monitor.value(for: monitor.statSlot2),
                downBps: monitor.netDownloadBps,
                upBps: monitor.netUploadBps
            )

            // Optional Pinned Network Stacked Display (if neither slot is already set to NET)
            if monitor.pinNetworkToMenuBar && monitor.statSlot1 != .network && monitor.statSlot2 != .network {
                Divider()
                    .frame(height: 12)
                    .opacity(0.35)

                MenuStatPill(
                    type: .network,
                    value: monitor.networkLoadPercentage,
                    downBps: monitor.netDownloadBps,
                    upBps: monitor.netUploadBps
                )
            }
        }
        .padding(.horizontal, 6)
        .frame(height: 22)
        .fixedSize(horizontal: true, vertical: false)
    }
}

struct MenuStatPill: View {
    let type: StatType
    let value: Double
    var downBps: Double = 0.0
    var upBps: Double = 0.0

    private var barColor: Color {
        SystemMonitor.colorFor(value: value, isBattery: type == .battery)
    }

    var body: some View {
        HStack(spacing: 4) {
            // Dynamic Mini Vertical Load Bar
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.primary.opacity(0.18))
                    .frame(width: 5, height: 14)
                
                RoundedRectangle(cornerRadius: 2)
                    .fill(barColor)
                    .frame(width: 5, height: max(2, CGFloat(value / 100.0) * 14.0))
                    .animation(.easeInOut(duration: 0.35), value: value)
            }
            
            if type == .network {
                // Stacked Upload / Download in Mbps
                VStack(alignment: .leading, spacing: -1) {
                    HStack(spacing: 1) {
                        Text("↑")
                            .font(.system(size: 7, weight: .heavy))
                            .foregroundColor(.orange)
                        Text(SystemMonitor.formatMbps(upBps, compact: true))
                            .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                            .foregroundColor(.primary)
                    }
                    HStack(spacing: 1) {
                        Text("↓")
                            .font(.system(size: 7, weight: .heavy))
                            .foregroundColor(.green)
                        Text(SystemMonitor.formatMbps(downBps, compact: true))
                            .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                            .foregroundColor(.primary)
                    }
                }
            } else {
                // Standard Stat Name & Percentage
                VStack(alignment: .leading, spacing: -1) {
                    Text(type.rawValue)
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .foregroundColor(.secondary)
                    
                    Text("\(Int(value.rounded()))%")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(.primary)
                }
            }
        }
    }
}
