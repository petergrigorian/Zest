import SwiftUI
import AppKit
import Combine
import Darwin

extension Notification.Name {
    static let zestMenuFeatureRequested = Notification.Name("zest.menu.featureRequested")
    static let zestMenuFeatureAnchoredRequested = Notification.Name("zest.menu.featureAnchoredRequested")
}

@MainActor
final class ZestSystemMonitor: ObservableObject {
    @Published var cpu: Double = 0
    @Published var memory: Double = 0
    @Published var storage: Double = 0
    @Published var cpuHistory = Array(repeating: 0.0, count: 24)
    @Published var memoryHistory = Array(repeating: 0.0, count: 24)
    @Published var storageHistory = Array(repeating: 0.0, count: 24)

    private var timer: Timer?
    private var previousCPU: (idle: UInt64, total: UInt64)?
    private var sampleCount = 0

    func start() {
        guard timer == nil else { return }
        sample()
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            // The timer is installed on the main run loop, so avoid allocating
            // a MainActor Task every second just to hop back to the same actor.
            MainActor.assumeIsolated { self?.sample() }
        }
        t.tolerance = 0.15
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() { timer?.invalidate(); timer = nil }

    private func append(_ value: Double, to history: inout [Double]) {
        history.append(min(max(value, 0), 1))
        if history.count > 24 { history.removeFirst(history.count - 24) }
    }

    private func sample() {
        cpu = readCPU()
        memory = readMemory()
        // Storage is comparatively expensive and barely changes second-to-second.
        // Refresh it every 15 samples while keeping its history continuous.
        if sampleCount == 0 || sampleCount % 15 == 0 { storage = readStorage() }
        sampleCount &+= 1
        append(cpu, to: &cpuHistory)
        append(memory, to: &memoryHistory)
        append(storage, to: &storageHistory)
    }

    private func readCPU() -> Double {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return cpu }
        let user = UInt64(info.cpu_ticks.0), system = UInt64(info.cpu_ticks.1)
        let idle = UInt64(info.cpu_ticks.2), nice = UInt64(info.cpu_ticks.3)
        let total = user + system + idle + nice
        defer { previousCPU = (idle, total) }
        guard let old = previousCPU, total > old.total else { return cpu }
        let deltaTotal = total - old.total
        let deltaIdle = idle - old.idle
        return deltaTotal == 0 ? cpu : 1 - Double(deltaIdle) / Double(deltaTotal)
    }

    private func readMemory() -> Double {
        var vm = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &vm) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return memory }
        let page = Double(vm_kernel_page_size)
        let used = Double(vm.active_count + vm.wire_count + vm.compressor_page_count) * page
        let total = Double(ProcessInfo.processInfo.physicalMemory)
        return total > 0 ? min(used / total, 1) : 0
    }

    private func readStorage() -> Double {
        do {
            let values = try URL(fileURLWithPath: NSHomeDirectory()).resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey])
            let total = Double(values.volumeTotalCapacity ?? 0)
            let available = Double(values.volumeAvailableCapacityForImportantUsage ?? 0)
            return total > 0 ? min(max((total - available) / total, 0), 1) : 0
        } catch { return storage }
    }
}

@MainActor
struct ZestMenuBarPanel: View {
    @ObservedObject var settingsManager: ZestSettingsManager
    @ObservedObject var monitor: ZestSystemMonitor
    @ObservedObject var textContextManager: TextContextManager
    @ObservedObject var fontLibraryManager: FontLibraryManager
    // These libraries are owned by the long-lived menu-bar controller and
    // reused between popover openings. Rebuilding the Unicode/symbol indexes
    // every time the dashboard opens caused needless launch/opening work.
    @ObservedObject var clipboardManager: ClipboardHistoryManager
    @ObservedObject var emojiLibraryManager: EmojiLibraryManager
    @ObservedObject var symbolLibraryManager: SymbolLibraryManager
    @State private var selectedFeature: ZestFeature?
    @State private var hasAppeared = false
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    private var palette: ZestAccentPalette { settingsManager.accent.palette }
    private var dashboardColors: [Color] { settingsManager.accent.displayColors }

    var body: some View {
        VStack(spacing: 15) {
            HStack(spacing: 10) {
                ZestMenuBrandMark(accent: palette.primary).frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Zest").font(.system(size: 15, weight: .bold, design: .rounded))
                    Text("System dashboard").font(.system(size: 10.5, weight: .medium)).foregroundStyle(.secondary)
                }
                Spacer()
            }

            ForEach(Array(settingsManager.menuBarBlocks.enumerated()), id: \.element.id) { index, block in
                if index > 0 { ZestMenuDivider() }

                switch block {
                case .monitors:
                    HStack(spacing: 9) {
                        ZestMonitorCard(title: "Storage", value: monitor.storage, history: monitor.storageHistory, symbol: "internaldrive", palette: palette, colors: dashboardColors)
                        ZestMonitorCard(title: "Memory", value: monitor.memory, history: monitor.memoryHistory, symbol: "memorychip", palette: palette, colors: dashboardColors)
                        ZestMonitorCard(title: "CPU", value: monitor.cpu, history: monitor.cpuHistory, symbol: "cpu", palette: palette, colors: dashboardColors)
                    }

                case .pinnedActions:
                    HStack(spacing: 8) {
                        ForEach(Array(settingsManager.menuBarPinnedFeatures.enumerated()), id: \.offset) { featureIndex, feature in
                            VStack(spacing: 5) {
                                Button {
                                    selectedFeature = (selectedFeature == feature) ? nil : feature
                                } label: {
                                    ZestMenuFeatureTile(feature: feature, palette: palette, accent: settingsManager.accentColor(at: featureIndex))
                                }
                                .buttonStyle(ZestPressButtonStyle())
                                .focusable(false)
                                .popover(
                                    isPresented: Binding(
                                        get: { selectedFeature == feature },
                                        set: { if !$0 && selectedFeature == feature { selectedFeature = nil } }
                                    ),
                                    arrowEdge: featureIndex < 2 ? .leading : (featureIndex > 2 ? .trailing : .top)
                                ) {
                                    ZestMenuFeatureHost(
                                        feature: feature,
                                        textContextManager: textContextManager,
                                        fontLibraryManager: fontLibraryManager,
                                        clipboardManager: clipboardManager,
                                        emojiLibraryManager: emojiLibraryManager,
                                        symbolLibraryManager: symbolLibraryManager,
                                        accentColor: settingsManager.accentColor(at: featureIndex),
                                        isPresented: Binding(
                                            get: { selectedFeature == feature },
                                            set: { if !$0 { selectedFeature = nil } }
                                        )
                                    )
                                }

                                Text(feature.title)
                                    .font(.system(size: 9.5, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .frame(width: 57)
                            .help(feature.title)
                        }
                    }
                }
            }

            ZestMenuDivider()

            HStack(spacing: 8) {
                ZestMenuActionButton(title: "Settings", systemImage: "gearshape", palette: palette) {
                    openSettings()
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        focusSettingsWindow()
                    }
                }
                ZestMenuActionButton(title: "Bug Report", systemImage: "ladybug", palette: palette) { bugReport() }
                ZestMenuActionButton(title: "Restart", systemImage: "arrow.clockwise", palette: palette) { restartZest() }
                ZestMenuActionButton(title: "Quit", systemImage: "power", palette: palette, destructive: true) { NSApp.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 345)
        .background {
            RoundedRectangle(cornerRadius: 23, style: .continuous)
                .fill(colorScheme == .light ? Color.white.opacity(0.34) : Color.black.opacity(0.06))
                .overlay {
                    RoundedRectangle(cornerRadius: 23, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: dashboardColors.map { $0.opacity(colorScheme == .light ? 0.075 : 0.085) },
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                .glassEffect(.regular.tint(palette.primary.opacity(colorScheme == .light ? 0.085 : 0.12)), in: RoundedRectangle(cornerRadius: 23, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 23, style: .continuous)
                        .stroke(Color.white.opacity(0.28), lineWidth: 0.7)
                }
        }
        .opacity(hasAppeared ? 1 : 0)
        .offset(y: hasAppeared ? 0 : -8)
        .onAppear {
            hasAppeared = false
            withAnimation(.easeOut(duration: 0.20)) { hasAppeared = true }
        }
    }

    private func bugReport() {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
        let body = """
        Zest Bug Report

        Version: \(version) (\(build))
        macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)

        Describe the issue:

        """
        var components = URLComponents(); components.scheme = "mailto"; components.path = ""
        components.queryItems = [URLQueryItem(name: "subject", value: "Zest Bug Report"), URLQueryItem(name: "body", value: body)]
        if let url = components.url { NSWorkspace.shared.open(url) }
        dismiss()
    }

    private func restartZest() {
        let configuration = NSWorkspace.OpenConfiguration(); configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
            guard error == nil else { return }; Task { @MainActor in NSApp.terminate(nil) }
        }
    }
}

private struct ZestMenuFeatureHost: View {
    let feature: ZestFeature
    @ObservedObject var textContextManager: TextContextManager
    @ObservedObject var fontLibraryManager: FontLibraryManager
    @ObservedObject var clipboardManager: ClipboardHistoryManager
    @ObservedObject var emojiLibraryManager: EmojiLibraryManager
    @ObservedObject var symbolLibraryManager: SymbolLibraryManager
    let accentColor: Color
    @Binding var isPresented: Bool

    @ViewBuilder
    private var featureContent: some View {
        switch feature {
        case .size:
            ZestSizePanel(
                textContextManager: textContextManager,
                accentColor: accentColor,
                isPresented: $isPresented
            )
        case .font:
            ZestFontPanel(
                textContextManager: textContextManager,
                fontLibraryManager: fontLibraryManager,
                accentColor: accentColor,
                isPresented: $isPresented
            )
        case .clipboard:
            ZestClipboardPanel(clipboardManager: clipboardManager, accentColor: accentColor)
        case .emoji:
            ZestEmojiPanel(
                emojiLibraryManager: emojiLibraryManager,
                clipboardManager: clipboardManager,
                accentColor: accentColor
            )
        case .symbols:
            ZestSymbolPanel(
                symbolLibraryManager: symbolLibraryManager,
                clipboardManager: clipboardManager,
                accentColor: accentColor
            )
        default:
            EmptyView()
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(feature.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button { isPresented = false } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 24, height: 24)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .focusable(false)
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 4)

            featureContent
        }
        .fixedSize()
    }
}

struct ZestMenuDivider: View {
    var body: some View { Rectangle().fill(Color.primary.opacity(0.09)).frame(height: 1).padding(.horizontal, 3) }
}

struct ZestMonitorCard: View {
    let title: String; let value: Double; let history: [Double]; let symbol: String; let palette: ZestAccentPalette; let colors: [Color]
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 3) {
                Image(systemName: symbol)
                    .font(.system(size: 8.5, weight: .semibold))
                    .fixedSize()

                Text(title)
                    .font(.system(size: 8.5, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .layoutPriority(1)
                    .allowsTightening(true)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 2)

                Text("\(Int((value * 100).rounded()))%")
                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            ZestSparkline(values: history, accent: palette.primary)
                .frame(height: 31)
        }
        .foregroundStyle(Color.primary.opacity(0.88))
        .padding(.horizontal, 8).padding(.vertical, 9)
        .frame(maxWidth: .infinity, minHeight: 66)
        .background { RoundedRectangle(cornerRadius: 15, style: .continuous).fill(LinearGradient(colors: colors.map { $0.opacity(0.14) }, startPoint: .topLeading, endPoint: .bottomTrailing)).offset(y: 1.2) }
        .glassEffect(.regular.tint(palette.primary.opacity(0.20)), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(LinearGradient(colors: [.white.opacity(0.68), .white.opacity(0.15), palette.deep.opacity(0.18)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.8) }
        .shadow(color: .black.opacity(0.09), radius: 4, y: 2.5)
    }
}

struct ZestSparkline: View {
    let values: [Double]; let accent: Color
    var body: some View {
        GeometryReader { proxy in
            let pts = values.enumerated().map { i, value in
                CGPoint(x: values.count <= 1 ? 0 : proxy.size.width * CGFloat(i) / CGFloat(values.count - 1),
                        y: proxy.size.height * (1 - CGFloat(min(max(value, 0), 1))))
            }
            ZStack {
                RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.035))
                Path { path in
                    guard let first = pts.first else { return }; path.move(to: first)
                    for p in pts.dropFirst() { path.addLine(to: p) }
                }
                .stroke(accent.opacity(0.85), style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
            }
        }
    }
}

struct ZestMenuFeatureTile: View {
    let feature: ZestFeature
    let palette: ZestAccentPalette
    let accent: Color

    var body: some View {
        Image(systemName: feature == .font ? "bold.italic.underline" : feature.systemImage)
            .font(.system(size: 19, weight: .semibold))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(Color.primary.opacity(0.88))
            .frame(width: 57, height: 57)
            .background {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(accent.opacity(0.12))
                    .glassEffect(
                        .regular.tint(accent.opacity(0.18)),
                        in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(Color.white.opacity(0.32), lineWidth: 0.7)
            }
            .shadow(color: .black.opacity(0.08), radius: 3, y: 2)
            .contentShape(Rectangle())
    }
}

struct ZestMenuActionButton: View {
    let title: String; let systemImage: String; let palette: ZestAccentPalette; var destructive = false; let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                ZStack {
                    Circle().fill((destructive ? Color.red : palette.primary).opacity(0.13)).offset(y: 1.4)
                        .glassEffect(.regular.tint((destructive ? Color.red : palette.primary).opacity(0.22)), in: Circle())
                        .overlay { Circle().stroke(LinearGradient(colors: [.white.opacity(0.78), .white.opacity(0.18), (destructive ? Color.red : palette.deep).opacity(0.24)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.8) }
                        .shadow(color: .black.opacity(0.11), radius: 4, y: 2.5)
                    Image(systemName: systemImage).font(.system(size: 15, weight: .semibold)).foregroundStyle(destructive ? Color.red.opacity(0.90) : Color.primary.opacity(0.86))
                }.frame(width: 42, height: 42)
                Text(title).font(.system(size: 9.5, weight: .medium)).foregroundStyle(destructive ? Color.red.opacity(0.86) : Color.secondary).lineLimit(1)
            }.frame(width: 72)
        }.buttonStyle(ZestPressButtonStyle()).focusable(false)
    }
}

@MainActor
struct ZestMenuBarSettingsPreview: View {
    @ObservedObject var settingsManager: ZestSettingsManager
    @Binding var blocks: [ZestMenuBarBlock]
    @Binding var pinnedFeatures: [ZestFeature]
    @Environment(\.colorScheme) private var colorScheme

    private var palette: ZestAccentPalette { settingsManager.accent.palette }
    private var dashboardColors: [Color] { settingsManager.accent.displayColors }
    private let previewHistoryA: [Double] = [0.58,0.58,0.59,0.60,0.61,0.61,0.62,0.63,0.64,0.66,0.68,0.69,0.70,0.70,0.70,0.70,0.70,0.70,0.70,0.70,0.70,0.70,0.70,0.70]
    private let previewHistoryB: [Double] = [0.55,0.55,0.56,0.56,0.57,0.58,0.59,0.60,0.61,0.63,0.64,0.65,0.66,0.67,0.67,0.67,0.67,0.67,0.67,0.67,0.67,0.67,0.67,0.67]
    private let previewHistoryC: [Double] = [0.08,0.07,0.09,0.08,0.12,0.36,0.16,0.11,0.08,0.09,0.10,0.12,0.09,0.08,0.09,0.08,0.07,0.07,0.08,0.08,0.09,0.08,0.09,0.08]

    var body: some View {
        VStack(spacing: 15) {
            HStack(spacing: 10) {
                ZestMenuBrandMark(accent: palette.primary).frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Zest").font(.system(size: 15, weight: .bold, design: .rounded))
                    Text("System dashboard").font(.system(size: 10.5, weight: .medium)).foregroundStyle(.secondary)
                }
                Spacer()
            }

            if blocks.isEmpty {
                dashboardBlockDropPlaceholder(index: 0, text: "Drop Monitors or Pinned Actions")
            } else {
                ForEach(Array(blocks.enumerated()), id: \.element.id) { index, block in
                    if index > 0 { ZestMenuDivider() }
                    editableBlock(block, index: index)
                }
                if blocks.count < ZestMenuBarBlock.allCases.count {
                    dashboardBlockDropPlaceholder(index: blocks.count, text: "Drop another dashboard block")
                }
            }

            ZestMenuDivider()

            HStack(spacing: 8) {
                ZestMenuActionButton(title: "Settings", systemImage: "gearshape", palette: palette) {}
                ZestMenuActionButton(title: "Bug Report", systemImage: "ladybug", palette: palette) {}
                ZestMenuActionButton(title: "Restart", systemImage: "arrow.clockwise", palette: palette) {}
                ZestMenuActionButton(title: "Quit", systemImage: "power", palette: palette, destructive: true) {}
            }
            .allowsHitTesting(false)
        }
        .padding(14)
        .frame(width: 345)
        .background {
            RoundedRectangle(cornerRadius: 23, style: .continuous)
                .fill(colorScheme == .light ? Color.white.opacity(0.34) : Color.black.opacity(0.06))
                .overlay {
                    RoundedRectangle(cornerRadius: 23, style: .continuous)
                        .fill(LinearGradient(colors: dashboardColors.map { $0.opacity(colorScheme == .light ? 0.075 : 0.085) }, startPoint: .topLeading, endPoint: .bottomTrailing))
                }
                .glassEffect(.regular.tint(palette.primary.opacity(colorScheme == .light ? 0.085 : 0.12)), in: RoundedRectangle(cornerRadius: 23, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 23, style: .continuous).stroke(Color.white.opacity(0.28), lineWidth: 0.7) }
                .shadow(color: .black.opacity(0.13), radius: 10, y: 6)
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.82), value: blocks)
        .animation(.spring(response: 0.24, dampingFraction: 0.80), value: pinnedFeatures)
    }

    @ViewBuilder
    private func editableBlock(_ block: ZestMenuBarBlock, index: Int) -> some View {
        switch block {
        case .monitors:
            HStack(spacing: 9) {
                ZestMonitorCard(title: "Storage", value: 0.81, history: previewHistoryA, symbol: "internaldrive", palette: palette, colors: dashboardColors)
                ZestMonitorCard(title: "Memory", value: 0.67, history: previewHistoryB, symbol: "memorychip", palette: palette, colors: dashboardColors)
                ZestMonitorCard(title: "CPU", value: 0.09, history: previewHistoryC, symbol: "cpu", palette: palette, colors: dashboardColors)
            }
            .draggable("menublock:\(block.rawValue)")
            .dropDestination(for: String.self) { items, _ in acceptBlockDrop(items, at: index) }

        case .pinnedActions:
            HStack(spacing: 8) {
                ForEach(Array(pinnedFeatures.enumerated()), id: \.offset) { featureIndex, feature in
                    VStack(spacing: 5) {
                        ZestMenuFeatureTile(feature: feature, palette: palette, accent: settingsManager.accentColor(at: featureIndex))
                            .draggable("menufeature:\(feature.rawValue)")
                            .dropDestination(for: String.self) { items, _ in
                                guard let raw = items.first, raw.hasPrefix("menufeature:"),
                                      let dropped = ZestFeature(rawValue: String(raw.dropFirst("menufeature:".count))),
                                      dropped != .empty, dropped != .settings else { return false }
                                withAnimation(.spring(response: 0.24, dampingFraction: 0.78)) {
                                    if let existing = pinnedFeatures.firstIndex(of: dropped) {
                                        pinnedFeatures.swapAt(existing, featureIndex)
                                    } else {
                                        pinnedFeatures[featureIndex] = dropped
                                    }
                                }
                                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                                return true
                            }
                        Text(feature.title)
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(width: 57)
                }
            }
            .draggable("menublock:\(block.rawValue)")
            .dropDestination(for: String.self) { items, _ in acceptBlockDrop(items, at: index) }
        }
    }

    private func dashboardBlockDropPlaceholder(index: Int, text: String) -> some View {
        RoundedRectangle(cornerRadius: 15, style: .continuous)
            .fill(palette.primary.opacity(0.035))
            .frame(height: 62)
            .overlay {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(palette.primary.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            }
            .overlay {
                HStack(spacing: 7) {
                    Image(systemName: "plus").font(.system(size: 10, weight: .bold))
                    Text(text).font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(.secondary)
            }
            .dropDestination(for: String.self) { items, _ in acceptBlockDrop(items, at: index) }
    }

    private func acceptBlockDrop(_ items: [String], at index: Int) -> Bool {
        guard let raw = items.first, raw.hasPrefix("menublock:"),
              let dropped = ZestMenuBarBlock(rawValue: String(raw.dropFirst("menublock:".count))) else { return false }
        withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
            blocks.removeAll { $0 == dropped }
            blocks.insert(dropped, at: min(index, blocks.count))
        }
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        return true
    }
}

struct ZestMenuBarGlyph: View {
    var color: Color = .primary

    // Keep the status-item label completely deterministic. GeometryReader can
    // be offered a transient zero-size proposal by MenuBarExtra while macOS is
    // constructing the status item, which can leave a custom label invisible.
    // The menu-bar glyph is always an 18 pt asset, so draw it at that size.
    var body: some View {
        let s: CGFloat = 18
        let inner = s * 0.205
        let outer = s * 0.467
        let gap = max(0.8, s * 0.015)
        let endGap = max(1.0, s * 0.026)

        ZStack {
            ForEach(ZestSliceVisualSlot.all) { slot in
                ZestTileShape(
                    startAngle: slot.startAngle,
                    endAngle: slot.endAngle,
                    innerRadius: inner,
                    outerRadius: outer,
                    gapInset: gap,
                    startGapInset: slot.id == 0 ? endGap : nil,
                    endGapInset: slot.id == 5 ? endGap : nil
                )
                .fill(color)
            }

            Circle()
                .fill(color)
                .frame(width: inner * 1.62, height: inner * 1.62)
        }
        .frame(width: s, height: s)
        .accessibilityHidden(true)
    }
}

struct ZestMenuBrandMark: View {
    let accent: Color
    var body: some View { ZestMenuBarGlyph(color: accent).padding(5).background { Circle().fill(accent.opacity(0.11)).glassEffect(.regular.tint(accent.opacity(0.22)), in: Circle()) } }
}

// MARK: - AppKit status-item host

/// Owns Zest's menu-bar presence explicitly through NSStatusItem.
///
/// The SwiftUI dashboard remains unchanged; AppKit is only responsible for
/// the status item and popover lifecycle. This avoids relying on MenuBarExtra
/// scene insertion for a UI that Zest needs to control dynamically.
@MainActor
final class ZestMenuBarController: NSObject, NSPopoverDelegate {
    private let defaults = UserDefaults.standard
    private let showKey = "zest.settings.showInMenuBar"

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var defaultsObserver: NSObjectProtocol?
    private var featureObserver: NSObjectProtocol?
    private var pendingCloseWorkItem: DispatchWorkItem?
    private var isAnimatingPopoverClose = false
    private var isMutatingStatusItem = false
    private var isStarted = false

    private let systemMonitor = ZestSystemMonitor()
    // Build the heavier feature libraries only when the menu dashboard is first
    // opened, then keep them for the controller lifetime. This keeps app launch
    // light while eliminating repeated Unicode/index construction afterwards.
    private lazy var clipboardManager = ClipboardHistoryManager()
    private lazy var emojiLibraryManager = EmojiLibraryManager()
    private lazy var symbolLibraryManager = SymbolLibraryManager()
    private let textContextManager: TextContextManager
    private let fontLibraryManager: FontLibraryManager

    init(textContextManager: TextContextManager, fontLibraryManager: FontLibraryManager) {
        self.textContextManager = textContextManager
        self.fontLibraryManager = fontLibraryManager
        super.init()
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        systemMonitor.start()
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: defaults,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.syncVisibilityFromDefaults()
            }
        }

        // Do not mutate AppKit's private status-item window on Space changes.
        // NSStatusBar owns placement of the item in the system menu bar. Zest's
        // accessory activation policy is what allows that system-owned item to
        // remain available when another app owns a native full-screen Space.

        syncVisibilityFromDefaults()
    }

    deinit {
        if let defaultsObserver { NotificationCenter.default.removeObserver(defaultsObserver) }
        if let featureObserver { NotificationCenter.default.removeObserver(featureObserver) }
        pendingCloseWorkItem?.cancel()
    }

    private func routeFeatureRequest(_ notification: Notification) {
        guard let raw = notification.object as? String else { return }
        let index = notification.userInfo?["index"] as? Int ?? 2

        // Anchor feature panels beside the dashboard rather than beside the
        // main caret-attached Zest control. Left-side pinned items open left;
        // right-side items open right. The center item chooses the roomier side.
        let dashboardFrame = popover?.contentViewController?.view.window?.frame ?? .zero
        let screen = popover?.contentViewController?.view.window?.screen ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero
        let side: CGFloat
        if index < 2 { side = -1 }
        else if index > 2 { side = 1 }
        else {
            let leftRoom = dashboardFrame.minX - visible.minX
            let rightRoom = visible.maxX - dashboardFrame.maxX
            side = rightRoom >= leftRoom ? 1 : -1
        }
        let anchor = CGPoint(
            x: side < 0 ? dashboardFrame.minX : dashboardFrame.maxX,
            y: dashboardFrame.midY
        )

        popover?.performClose(nil)
        NotificationCenter.default.post(
            name: .zestMenuFeatureAnchoredRequested,
            object: raw,
            userInfo: ["anchorX": anchor.x, "anchorY": anchor.y, "side": side]
        )
    }

    private var shouldShow: Bool {
        // Preserve the existing default-ON behavior for users who have never
        // touched the setting.
        guard defaults.object(forKey: showKey) != nil else { return true }
        return defaults.bool(forKey: showKey)
    }

    private func syncVisibilityFromDefaults() {
        if shouldShow {
            installStatusItemIfNeeded()
        } else {
            removeStatusItem()
        }
    }

    private func installStatusItemIfNeeded() {
        guard statusItem == nil, !isMutatingStatusItem else { return }
        isMutatingStatusItem = true
        defer { isMutatingStatusItem = false }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = item.button {
            button.target = self
            button.action = #selector(toggleDashboard(_:))
            button.sendAction(on: [.leftMouseUp])
            button.toolTip = "Zest"
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleProportionallyDown
            button.image = makeStatusImage()
            button.image?.isTemplate = true
            button.setAccessibilityLabel("Zest")
        }

        // Publish the reference only after the native item is fully configured.
        // This prevents observers from seeing a half-installed status item.
        statusItem = item
        item.isVisible = true
    }

    private func removeStatusItem() {
        guard !isMutatingStatusItem else { return }
        isMutatingStatusItem = true
        defer { isMutatingStatusItem = false }

        popover?.performClose(nil)
        popover = nil

        let item = statusItem
        statusItem = nil
        if let item { NSStatusBar.system.removeStatusItem(item) }
    }

    /// Use Zest's dedicated monochrome segmented orange-slice artwork for the
    /// native status item. The asset is a preserved vector template, so AppKit
    /// supplies the correct menu-bar foreground in light, dark and highlighted
    /// states without tinting the application's full-colour brand mark.
    private func makeStatusImage() -> NSImage {
        if let image = NSImage(named: "ZestMenuBarMonochrome") {
            image.size = NSSize(width: 18, height: 18)
            image.isTemplate = true
            return image
        }

        // Keep the programmatic glyph as a safe fallback if the asset catalog
        // is ever renamed or omitted from a build target.
        let renderer = ImageRenderer(
            content: ZestMenuBarGlyph(color: .black)
                .frame(width: 18, height: 18)
        )
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        if let image = renderer.nsImage {
            image.size = NSSize(width: 18, height: 18)
            image.isTemplate = true
            return image
        }

        let fallback = NSImage(
            systemSymbolName: "circle.hexagongrid.fill",
            accessibilityDescription: "Zest"
        ) ?? NSImage(size: NSSize(width: 18, height: 18))
        fallback.size = NSSize(width: 18, height: 18)
        fallback.isTemplate = true
        return fallback
    }

    @objc
    private func toggleDashboard(_ sender: Any?) {
        guard let button = statusItem?.button else { return }

        if let popover, popover.isShown {
            closeDashboardAnimated(sender)
            return
        }

        // Recreate the settings model when opening. It loads the latest saved
        // accent and pinned-feature configuration, keeping the dashboard in
        // sync with Settings without introducing a second long-lived observer.
        let settings = ZestSettingsManager()
        let host = NSHostingController(
            rootView: ZestMenuBarPanel(
                settingsManager: settings,
                monitor: systemMonitor,
                textContextManager: textContextManager,
                fontLibraryManager: fontLibraryManager,
                clipboardManager: clipboardManager,
                emojiLibraryManager: emojiLibraryManager,
                symbolLibraryManager: symbolLibraryManager
            )
        )

        let dashboard = NSPopover()
        dashboard.behavior = .transient
        dashboard.animates = false
        let blockHeight: CGFloat = settings.menuBarBlocks.reduce(0) { partial, block in
            partial + (block == .monitors ? 86 : 83)
        }
        let separators = CGFloat(max(settings.menuBarBlocks.count, 1)) * 16
        dashboard.contentSize = NSSize(width: 345, height: 145 + blockHeight + separators)
        dashboard.contentViewController = host
        dashboard.delegate = self
        popover = dashboard

        dashboard.show(
            relativeTo: button.bounds,
            of: button,
            preferredEdge: .minY
        )
    }

    private func closeDashboardAnimated(_ sender: Any? = nil) {
        guard let dashboard = popover, dashboard.isShown else { return }
        guard !isAnimatingPopoverClose else { return }
        isAnimatingPopoverClose = true
        pendingCloseWorkItem?.cancel()

        if let view = dashboard.contentViewController?.view {
            view.wantsLayer = true
            let originalFrame = view.layer?.frame ?? .zero
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.16
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                view.animator().alphaValue = 0
                if var frame = view.layer?.frame {
                    frame.origin.y += 7
                    frame.size.width *= 0.985
                    frame.size.height *= 0.985
                    frame.origin.x = originalFrame.midX - frame.width / 2
                    view.layer?.anchorPoint = CGPoint(x: 0.5, y: 0.5)
                    view.layer?.frame = frame
                }
            }
        }

        let work = DispatchWorkItem { [weak self, weak dashboard] in
            guard let self, let dashboard else { return }
            dashboard.performClose(sender)
            self.isAnimatingPopoverClose = false
            self.pendingCloseWorkItem = nil
        }
        pendingCloseWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16, execute: work)
    }

    func popoverShouldClose(_ popover: NSPopover) -> Bool {
        if isAnimatingPopoverClose { return true }
        closeDashboardAnimated(nil)
        return false
    }

    func popoverDidClose(_ notification: Notification) {
        pendingCloseWorkItem?.cancel()
        pendingCloseWorkItem = nil
        isAnimatingPopoverClose = false
        popover = nil
    }
}
