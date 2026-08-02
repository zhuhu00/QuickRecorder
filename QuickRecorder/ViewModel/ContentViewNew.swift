//
//  ContentViewNew.swift
//  QuickRecorder
//

import AppKit
import SwiftUI
import AVFoundation
import ScreenCaptureKit

enum CompactRecorderLayout {
    static let width: CGFloat = 850
    static let collapsedHeight: CGFloat = 80
    static let settingsPanelCollapsedHeight: CGFloat = 160
    static let settingsPanelExpandedHeight: CGFloat = 272
    static let settingsPanelGap: CGFloat = 8
    static let menuBarWidth: CGFloat = 416
    static let menuBarHeight: CGFloat = 150
    static let menuBarSettingsCollapsedHeight: CGFloat = 619
    static let menuBarSettingsExpandedHeight: CGFloat = 759
}

struct ContentViewNew: View {
    let fromStatusBar: Bool

    @State private var panelWindow: NSWindow?
    @State private var inlineSettingsVisible = false
    @State private var menuBarHotkeysExpanded = false
    @ObservedObject private var settingsPanel = CompactSettingsPanelCoordinator.shared
    @State private var cameraIsRunning = false
    @State private var cameraList: [AVCaptureDevice] = []
    @State private var micList: [AVCaptureDevice] = []
    @State private var hasLoadedDevices = false

    @AppStorage("cameraDevice") private var cameraDevice: String = "default"
    @AppStorage("recordMic") private var recordMic: Bool = true
    @AppStorage("micDevice") private var micDevice: String = "default"
    @AppStorage("showMouse") private var showMouse: Bool = true

    private let appDelegate = AppDelegate.shared

    init(fromStatusBar: Bool = true) {
        self.fromStatusBar = fromStatusBar
    }

    var body: some View {
        VStack(spacing: 0) {
            if fromStatusBar {
                menuBarToolbar
                    .frame(height: CompactRecorderLayout.menuBarHeight)
            } else {
                toolbar
                    .frame(height: CompactRecorderLayout.collapsedHeight)
            }

            if fromStatusBar {
                VStack(spacing: 0) {
                    Divider()
                    CompactSettingsView(compact: true) { isExpanded in
                        var transaction = Transaction()
                        transaction.disablesAnimations = true
                        withTransaction(transaction) {
                            menuBarHotkeysExpanded = isExpanded
                        }
                    }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .frame(
                            height: menuBarSettingsHeight,
                            alignment: .top
                        )
                }
                .frame(height: inlineSettingsVisible ? inlineSettingsHeight : 0, alignment: .top)
                .clipped()
                .opacity(inlineSettingsVisible ? 1 : 0)
                .allowsHitTesting(inlineSettingsVisible)
            }
        }
        .frame(
            width: contentWidth,
            height: contentHeight,
            alignment: .top
        )
        .background {
            ZStack {
                if !fromStatusBar {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.ultraThinMaterial)
                }

                if fromStatusBar {
                    CompactHostWindowReader { window in
                        panelWindow = window
                    }
                } else {
                    WindowAccessor(
                        onWindowOpen: { window in
                            panelWindow = window
                        },
                        onWindowClose: {
                            settingsPanel.hide(ifHostedBy: panelWindow)
                        }
                    )
                }
            }
        }
        .onAppear {
            refreshCameraState()
            if !fromStatusBar {
                DispatchQueue.main.async { refreshDevices() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .quickRecorderPanelDidOpen)) { _ in
            if fromStatusBar && !hasLoadedDevices { refreshDevices() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .quickRecorderPanelDidClose)) { _ in
            guard fromStatusBar else { return }
            inlineSettingsVisible = false
        }
        .onReceive(NotificationCenter.default.publisher(for: AVCaptureDevice.wasConnectedNotification)) { _ in
            DispatchQueue.main.async { refreshDevices() }
        }
        .onReceive(NotificationCenter.default.publisher(for: AVCaptureDevice.wasDisconnectedNotification)) { _ in
            DispatchQueue.main.async { refreshDevices() }
        }
        .onReceive(updateTimer) { _ in
            refreshCameraState()
        }
        .onChange(of: recordMic) { _, isEnabled in
            if isEnabled {
                Task { await SCContext.performMicCheck() }
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            sourceControls

            Divider()
                .frame(height: 64)
                .padding(.horizontal, 2)

            cameraControl
            microphoneControl
            cursorControl
            settingsControl
            closeControl
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private var menuBarToolbar: some View {
        VStack(spacing: 8) {
            sourceControls

            Divider()

            HStack(spacing: 4) {
                cameraControl
                microphoneControl
                cursorControl
                settingsControl
                closeControl
            }
        }
        .padding(10)
    }

    private var sourceControls: some View {
        HStack(spacing: 4) {
            CompactSourceButton(title: "System Audio", symbol: "waveform", action: startSystemAudio)
            CompactSourceButton(title: "Screen", symbol: "display", action: selectScreen)
            CompactSourceButton(title: "Screen Area", symbol: "viewfinder", action: selectArea)
            CompactSourceButton(title: "Window", symbol: "macwindow", action: selectWindow)
        }
    }

    private var cameraControl: some View {
        DeviceStateButton(
            title: "Camera",
            symbol: cameraIsRunning ? "video.fill" : "video.slash.fill",
            isEnabled: cameraIsRunning,
            isAvailable: !cameraList.isEmpty,
            action: toggleCamera
        ) {
            Picker("Camera".local, selection: $cameraDevice) {
                if let preferredCamera {
                    Text(preferredCamera.localizedName).tag("default")
                }
                ForEach(cameraList.filter { $0.uniqueID != preferredCamera?.uniqueID }, id: \.uniqueID) { camera in
                    Text(camera.localizedName).tag(camera.uniqueID)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .disabled(cameraList.isEmpty)
            .opacity(cameraIsRunning ? 1 : 0.55)
            .onChange(of: cameraDevice) { switchCameraIfRunning() }
        }
    }

    private var microphoneControl: some View {
        DeviceStateButton(
            title: "Microphone",
            symbol: recordMic ? "mic.fill" : "mic.slash.fill",
            isEnabled: recordMic,
            isAvailable: !micList.isEmpty,
            action: { recordMic.toggle() }
        ) {
            Picker("Microphone".local, selection: $micDevice) {
                ForEach(micList, id: \.uniqueID) { microphone in
                    Text(SCContext.microphoneDisplayName(for: microphone, devices: micList))
                        .tag(microphone.uniqueID)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .disabled(micList.isEmpty)
            .opacity(recordMic ? 1 : 0.55)
        }
    }

    private var cursorControl: some View {
        CompactIconButton(
            symbol: "cursorarrow",
            label: "Cursor",
            isActive: showMouse,
            action: { showMouse.toggle() }
        )
    }

    private var settingsControl: some View {
        CompactIconButton(
            symbol: "gearshape",
            label: "Settings",
            isActive: fromStatusBar
                ? inlineSettingsVisible
                : settingsPanel.isVisible(on: panelWindow),
            action: toggleSettings
        )
    }

    private var closeControl: some View {
        CompactIconButton(
            symbol: "xmark",
            label: fromStatusBar ? "Quit" : "Close",
            tint: .red,
            action: closeOrQuit
        )
    }

    private var preferredCamera: AVCaptureDevice? {
        cameraList.first(where: { $0.deviceType == .builtInWideAngleCamera }) ?? cameraList.first
    }

    private var selectedCamera: AVCaptureDevice? {
        if cameraDevice == "default" { return preferredCamera }
        return cameraList.first(where: { $0.uniqueID == cameraDevice }) ?? preferredCamera
    }

    private var inlineSettingsHeight: CGFloat {
        menuBarSettingsHeight + 1
    }

    private var menuBarSettingsHeight: CGFloat {
        menuBarHotkeysExpanded
            ? CompactRecorderLayout.menuBarSettingsExpandedHeight
            : CompactRecorderLayout.menuBarSettingsCollapsedHeight
    }

    private var contentHeight: CGFloat {
        (fromStatusBar ? CompactRecorderLayout.menuBarHeight : CompactRecorderLayout.collapsedHeight)
            + (fromStatusBar && inlineSettingsVisible ? inlineSettingsHeight : 0)
    }

    private var contentWidth: CGFloat {
        fromStatusBar ? CompactRecorderLayout.menuBarWidth : CompactRecorderLayout.width
    }

    private func startSystemAudio() {
        guard let displayID = SCContext.getScreenWithMouse()?.displayID else { return }
        dismissRecorderPanel()
        SCContext.updateAvailableContent {
            guard SCContext.streamType == nil,
                  let display = SCContext.availableContent?.displays.first(where: {
                      $0.displayID == displayID
                  }) else { return }
            appDelegate.createCountdownPanel(screen: display) {
                AppDelegate.shared.prepRecord(
                    type: "audio",
                    screens: display,
                    windows: nil
                )
            }
        }
    }

    private func selectScreen() {
        dismissRecorderPanel()
        appDelegate.createNewWindow(view: ScreenSelector(), title: "Screen Selector".local)
    }

    private func selectArea() {
        dismissRecorderPanel()
        SCContext.updateAvailableContent {
            appDelegate.showAreaSelector(size: NSSize(width: 600, height: 450))
            var currentDisplay = SCContext.getSCDisplayWithMouse()
            mouseMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: [.mouseMoved, .rightMouseDown, .leftMouseDown, .otherMouseDown]
            ) { _ in
                let display = SCContext.getSCDisplayWithMouse()
                if display != currentDisplay {
                    currentDisplay = display
                    closeAllWindow()
                    appDelegate.showAreaSelector(size: NSSize(width: 600, height: 450))
                }
            }
        }
    }

    private func selectWindow() {
        dismissRecorderPanel()
        appDelegate.createNewWindow(view: WinSelector(), title: "Window Selector".local)
    }

    private func dismissRecorderPanel() {
        inlineSettingsVisible = false
        settingsPanel.hide()
        closeStatusBarPopover()
        closeMainWindow()
    }

    private func closeOrQuit() {
        if fromStatusBar {
            NSApp.terminate(nil)
            return
        }

        inlineSettingsVisible = false
        settingsPanel.hide()
        panelWindow?.close()
    }

    private func toggleSettings() {
        if fromStatusBar {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                inlineSettingsVisible.toggle()
            }
            return
        }

        guard let panelWindow else { return }
        settingsPanel.toggle(relativeTo: panelWindow)
    }

    private func toggleCamera() {
        if cameraIsRunning {
            SCContext.recordCam = ""
            appDelegate.closeCamera()
            refreshCameraState()
            return
        }

        guard let camera = selectedCamera else { return }
        SCContext.recordCam = camera.localizedName
        appDelegate.recordingCamera(with: camera)
        refreshCameraState()
    }

    private func switchCameraIfRunning() {
        guard cameraIsRunning,
              let camera = selectedCamera,
              SCContext.recordCam != camera.localizedName else { return }
        appDelegate.closeCamera()
        SCContext.recordCam = camera.localizedName
        appDelegate.recordingCamera(with: camera)
        refreshCameraState()
    }

    private func refreshDevices() {
        cameraList = SCContext.getCameras()
        micList = SCContext.getMicrophone()
        hasLoadedDevices = true
        if cameraDevice != "default" && !cameraList.contains(where: { $0.uniqueID == cameraDevice }) {
            cameraDevice = "default"
        }
        micDevice = SCContext.migrateMicrophoneSelectionIfNeeded(micDevice, devices: micList)
        if micList.isEmpty { recordMic = false }
    }

    private func refreshCameraState() {
        cameraIsRunning = !SCContext.recordCam.isEmpty
        if cameraIsRunning && !appDelegate.isPresenterON && !camWindow.isVisible && camWindow.contentView != nil {
            camWindow.orderFrontRegardless()
        }
    }

}

final class CompactSettingsPanelCoordinator: NSObject, ObservableObject {
    static let shared = CompactSettingsPanelCoordinator()

    @Published private(set) var isVisible = false

    private weak var hostWindow: NSWindow?
    private var hostObservers: [NSObjectProtocol] = []
    private var hotkeysExpanded = false
    private var panelHeight: CGFloat {
        hotkeysExpanded
            ? CompactRecorderLayout.settingsPanelExpandedHeight
            : CompactRecorderLayout.settingsPanelCollapsedHeight
    }
    private lazy var panel: CompactSettingsPanel = {
        let panel = CompactSettingsPanel(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: CompactRecorderLayout.width,
                height: panelHeight
            ),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.contentView = NSHostingView(
            rootView: CompactSettingsPanelContent { [weak self] isExpanded in
                self?.setHotkeysExpanded(isExpanded)
            }
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        return panel
    }()

    func prepare() {
        _ = panel
        panel.contentView?.layoutSubtreeIfNeeded()
    }

    func toggle(relativeTo host: NSWindow) {
        if isVisible(on: host) {
            hide()
        } else {
            show(relativeTo: host)
        }
    }

    func isVisible(on host: NSWindow?) -> Bool {
        guard let host else { return false }
        return isVisible && hostWindow === host
    }

    func show(relativeTo host: NSWindow) {
        if hostWindow !== host {
            detachFromHost()
            hostWindow = host
            observeHost(host)
        }

        if panel.parent !== host {
            panel.parent?.removeChildWindow(panel)
            host.addChildWindow(panel, ordered: .above)
        }

        positionPanel()
        panel.orderFront(nil)
        isVisible = true
    }

    func hide(ifHostedBy host: NSWindow?) {
        guard hostWindow === host else { return }
        hide()
    }

    func hide() {
        guard isVisible || panel.isVisible || hostWindow != nil else { return }
        panel.orderOut(nil)
        detachFromHost()
        isVisible = false
    }

    private func positionPanel() {
        guard let hostWindow else { return }

        var origin = NSPoint(
            x: hostWindow.frame.midX - CompactRecorderLayout.width / 2,
            y: hostWindow.frame.minY
                - CompactRecorderLayout.settingsPanelGap
                - panelHeight
        )

        if let visibleFrame = hostWindow.screen?.visibleFrame {
            origin.x = min(
                max(origin.x, visibleFrame.minX),
                visibleFrame.maxX - CompactRecorderLayout.width
            )
            if origin.y < visibleFrame.minY {
                origin.y = hostWindow.frame.maxY + CompactRecorderLayout.settingsPanelGap
            }
        }

        panel.setFrame(
            NSRect(
                origin: origin,
                size: NSSize(
                    width: CompactRecorderLayout.width,
                    height: panelHeight
                )
            ),
            display: true
        )
    }

    private func observeHost(_ host: NSWindow) {
        let center = NotificationCenter.default
        hostObservers = [
            center.addObserver(forName: NSWindow.didMoveNotification, object: host, queue: .main) { [weak self] _ in
                self?.positionPanel()
            },
            center.addObserver(forName: NSWindow.didResizeNotification, object: host, queue: .main) { [weak self] _ in
                self?.positionPanel()
            },
            center.addObserver(forName: NSWindow.willCloseNotification, object: host, queue: .main) { [weak self] _ in
                self?.hide()
            }
        ]
    }

    private func setHotkeysExpanded(_ isExpanded: Bool) {
        guard hotkeysExpanded != isExpanded else { return }
        hotkeysExpanded = isExpanded
        positionPanel()
    }

    private func detachFromHost() {
        if let hostWindow, panel.parent === hostWindow {
            hostWindow.removeChildWindow(panel)
        }
        hostWindow = nil
        let center = NotificationCenter.default
        hostObservers.forEach(center.removeObserver)
        hostObservers.removeAll()
    }
}

private final class CompactSettingsPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

private struct CompactSettingsPanelContent: View {
    @State private var hotkeysExpanded = false
    let onHotkeysExpandedChange: (Bool) -> Void

    var body: some View {
        CompactSettingsView { isExpanded in
            hotkeysExpanded = isExpanded
            onHotkeysExpandedChange(isExpanded)
        }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(
                width: CompactRecorderLayout.width,
                height: hotkeysExpanded
                    ? CompactRecorderLayout.settingsPanelExpandedHeight
                    : CompactRecorderLayout.settingsPanelCollapsedHeight,
                alignment: .top
            )
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
    }
}

private struct CompactHostWindowReader: NSViewRepresentable {
    let onResolve: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            onResolve(view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            onResolve(nsView.window)
        }
    }
}

private struct CompactSourceButton: View {
    let title: String
    let symbol: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 23, weight: .medium))
                    .frame(height: 27)
                Text(title.local)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
            }
            .frame(width: 96, height: 64)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.primary.opacity(isHovering ? 0.12 : 0.04))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(title.local)
    }
}

private struct DeviceStateButton<Accessory: View>: View {
    let title: String
    let symbol: String
    let isEnabled: Bool
    let isAvailable: Bool
    let action: () -> Void
    let accessory: Accessory

    init(
        title: String,
        symbol: String,
        isEnabled: Bool,
        isAvailable: Bool = true,
        action: @escaping () -> Void,
        @ViewBuilder accessory: @escaping () -> Accessory
    ) {
        self.title = title
        self.symbol = symbol
        self.isEnabled = isEnabled
        self.isAvailable = isAvailable
        self.action = action
        self.accessory = accessory()
    }

    var body: some View {
        VStack(spacing: 3) {
            Button(action: action) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isEnabled ? Color.white : Color.primary)
                    .frame(width: 40, height: 38)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(isEnabled ? Color.accentColor : Color.primary.opacity(0.08))
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!isAvailable)

            accessory
                .controlSize(.small)
                .frame(width: 124, height: 22)
        }
        .frame(width: 124, height: 64)
        .opacity(isAvailable ? 1 : 0.45)
        .help(title.local)
        .accessibilityLabel(title.local)
    }
}

private struct CompactIconButton: View {
    let symbol: String
    let label: String
    var isActive = false
    var tint: Color = .primary
    let action: () -> Void

    var body: some View {
        VStack(spacing: 3) {
            Button(action: action) {
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(isActive ? Color.white : tint)
                    .frame(width: 40, height: 38)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(isActive ? Color.accentColor : Color.primary.opacity(0.04))
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Color.clear
                .frame(height: 22)
        }
        .frame(width: 44, height: 64)
        .help(label.local)
        .accessibilityLabel(label.local)
    }
}
