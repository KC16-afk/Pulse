import SwiftUI

struct ContentView: View {
    @ObservedObject var monitor: SystemMonitor
    var onQuit: () -> Void

    @State private var pulsing = false

    var body: some View {
        let snap = monitor.snapshot
        let memoryFraction = snap.memoryTotal > 0
            ? Double(snap.memoryUsed) / Double(snap.memoryTotal) : 0

        VStack(alignment: .leading, spacing: 14) {
            header

            cpuCard(snapshot: snap)

            HStack(alignment: .top, spacing: 12) {
                memoryCard(used: snap.memoryUsed, total: snap.memoryTotal, fraction: memoryFraction)
                networkCard(down: snap.networkDown, up: snap.networkUp)
            }

            if let battery = snap.battery {
                batteryCard(battery)
            }

            if !snap.processes.isEmpty {
                processesCard(snap.processes)
            }

            footer
        }
        .padding(18)
        .frame(width: 340, alignment: .leading)
        .background(.regularMaterial)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        LinearGradient(
                            colors: [.green, .blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 34, height: 34)
            .shadow(color: .blue.opacity(0.25), radius: 6, y: 2)

            VStack(alignment: .leading, spacing: 1) {
                Text("Pulse")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text("Live system monitor")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 5) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 7, height: 7)
                    .scaleEffect(pulsing ? 1.25 : 0.85)
                    .opacity(pulsing ? 0.65 : 1)
                Text("LIVE")
                    .font(.caption2.bold())
                    .foregroundStyle(.green)
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                    pulsing = true
                }
            }
        }
    }

    // MARK: CPU

    private func cpuCard(snapshot: SystemSnapshot) -> some View {
        let tint = cardColor(snapshot.cpu)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Label("CPU USAGE", systemImage: "cpu.fill")
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                Text(Formatters.percent(snapshot.cpu))
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(tint)
            }

            Sparkline(values: snapshot.cpuHistory)
                .frame(height: 62)

            HStack(spacing: 12) {
                legend(color: .green, title: "User \(Formatters.percent(snapshot.cpuUser))")
                legend(color: .orange, title: "Sys \(Formatters.percent(snapshot.cpuSystem))")
                legend(color: .gray, title: "Idle \(Formatters.percent(snapshot.cpuIdle))")
            }
        }
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
        )
    }

    private func legend(color: Color, title: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Memory / Network

    private func memoryCard(used: UInt64, total: UInt64, fraction: Double) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("MEMORY", systemImage: "memorychip")
                .font(.caption2.bold())
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Ring(fraction: fraction, color: .blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text(Formatters.percent(fraction))
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text("\(Formatters.bytes(used)) / \(Formatters.bytes(total))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func networkCard(down: Double, up: Double) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("NETWORK", systemImage: "network")
                .font(.caption2.bold())
                .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                Image(systemName: "arrow.down")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.mint)
                Text(Formatters.rate(down))
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
            }
            HStack(spacing: 6) {
                Image(systemName: "arrow.up")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.purple)
                Text(Formatters.rate(up))
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Battery / Processes / Footer

    private func batteryCard(_ battery: Battery) -> some View {
        HStack {
            Label("BATTERY", systemImage: battery.charging ? "battery.100.bolt" : "battery.75")
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
            Spacer()
            Text(Formatters.percent(battery.level))
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .monospacedDigit()
            if battery.charging {
                Text("CHARGING")
                    .font(.caption2.bold())
                    .foregroundStyle(.green)
            }
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func processesCard(_ processes: [ProcessSample]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("TOP PROCESSES", systemImage: "list.bullet")
                .font(.caption2.bold())
                .foregroundStyle(.secondary)

            ForEach(processes) { process in
                HStack(spacing: 8) {
                    Text(process.name)
                        .font(.caption)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(Formatters.percent(process.cpu))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.08))
                            Capsule()
                                .fill(LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing))
                                .frame(width: geo.size.width * min(max(process.cpu, 0), 1))
                        }
                    }
                    .frame(width: 54, height: 4)
                }
            }
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var footer: some View {
        HStack {
            Text("Refreshes every second")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Spacer()
            Button("Quit Pulse") { onQuit() }
                .buttonStyle(.borderless)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Helpers

    private func cardColor(_ cpu: Double) -> Color {
        if cpu < 0.40 { return .green }
        if cpu < 0.75 { return .orange }
        return .red
    }
}

// MARK: - Sparkline

private struct Sparkline: View {
    let values: [Double]

    var body: some View {
        GeometryReader { geo in
            draw(width: geo.size.width, height: geo.size.height)
        }
    }

    private func draw(width: CGFloat, height: CGFloat) -> some View {
        let samples = values.count >= 2 ? values : [0, 0]
        let step = width / CGFloat(samples.count - 1)
        let topInset: CGFloat = 4
        let bottomInset: CGFloat = 4

        func point(_ index: Int) -> CGPoint {
            let v = min(max(samples[index], 0), 1)
            return CGPoint(
                x: CGFloat(index) * step,
                y: height - bottomInset - CGFloat(v) * (height - topInset - bottomInset)
            )
        }

        return ZStack {
                Path { path in
                    path.move(to: CGPoint(x: 0, y: height - bottomInset))
                    for i in 0..<samples.count { path.addLine(to: point(i)) }
                    path.addLine(to: CGPoint(x: width, y: height - bottomInset))
                    path.closeSubpath()
                }
                .fill(
                    LinearGradient(
                        colors: [Color.blue.opacity(0.45), Color.blue.opacity(0.0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                Path { path in
                    for i in 0..<samples.count {
                        let p = point(i)
                        if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
                    }
                }
                .stroke(
                    LinearGradient(colors: [.mint, .blue], startPoint: .leading, endPoint: .trailing),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                )
        }
    }
}

// MARK: - Ring

private struct Ring: View {
    let fraction: Double
    let color: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.10), lineWidth: 5)
            Circle()
                .trim(from: 0, to: min(max(fraction, 0), 1))
                .stroke(
                    LinearGradient(colors: [color, .purple], startPoint: .top, endPoint: .bottom),
                    style: StrokeStyle(lineWidth: 5, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 34, height: 34)
    }
}
