//
//  StatusBarItem.swift
//  QuickRecorder
//
//  Created by apple on 2024/4/16.
//

import SwiftUI

private let statusBarPopover = NSPopover()
private let recordingStatusViewIdentifier = NSUserInterfaceItemIdentifier("QuickRecorderRecordingStatusView")

extension Notification.Name {
    static let quickRecorderPanelDidOpen = Notification.Name("QuickRecorderPanelDidOpen")
    static let quickRecorderPanelDidClose = Notification.Name("QuickRecorderPanelDidClose")
}

func closeStatusBarPopover() {
    CompactSettingsPanelCoordinator.shared.hide()
    statusBarPopover.performClose(nil)
}

private final class StatusBarActionTarget: NSObject, NSPopoverDelegate {
    static let shared = StatusBarActionTarget()
    private lazy var recorderController = NSHostingController(rootView: AnyView(ContentViewNew()))
    private var outsideClickMonitor: Any?

    @objc func togglePopover(_ sender: NSStatusBarButton) {
        if statusBarPopover.isShown {
            closeStatusBarPopover()
            return
        }

        statusBarPopover.behavior = .transient
        statusBarPopover.delegate = self
        if statusBarPopover.contentViewController !== recorderController {
            statusBarPopover.contentViewController = recorderController
        }
        statusBarPopover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        startOutsideClickMonitoring()
        DispatchQueue.main.async { restoreCameraOverlayerIfNeeded() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            NotificationCenter.default.post(name: .quickRecorderPanelDidOpen, object: nil)
        }
    }

    func popoverDidClose(_ notification: Notification) {
        stopOutsideClickMonitoring()
        CompactSettingsPanelCoordinator.shared.hide()
        NotificationCenter.default.post(name: .quickRecorderPanelDidClose, object: nil)
    }

    private func startOutsideClickMonitoring() {
        stopOutsideClickMonitoring()
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { _ in
            DispatchQueue.main.async {
                guard statusBarPopover.isShown else { return }
                closeStatusBarPopover()
            }
        }
    }

    private func stopOutsideClickMonitoring() {
        guard let outsideClickMonitor else { return }
        NSEvent.removeMonitor(outsideClickMonitor)
        self.outsideClickMonitor = nil
    }
}

private func restoreCameraOverlayerIfNeeded() {
    guard !SCContext.recordCam.isEmpty,
          !AppDelegate.shared.isPresenterON,
          camWindow.contentView != nil else { return }
    camWindow.orderFrontRegardless()
}

func configureIdleStatusBarItem(_ item: NSStatusItem) {
    guard let button = item.button else { return }

    item.length = NSStatusItem.squareLength
    let configuration = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
    let image = NSImage(systemSymbolName: "record.circle", accessibilityDescription: "QuickRecorder")?
        .withSymbolConfiguration(configuration)
    image?.isTemplate = true
    button.image = image
    button.title = ""
    button.imagePosition = .imageOnly
    button.target = StatusBarActionTarget.shared
    button.action = #selector(StatusBarActionTarget.togglePopover(_:))
    button.toolTip = "QuickRecorder"
    button.setAccessibilityLabel("QuickRecorder")
    item.isVisible = true
}

class PopoverState: ObservableObject {
    static let shared = PopoverState()
    @Published var isShowing: Bool = false
    @Published var isPaused: Bool = false
}

struct StatusBarItem: View {
    @State private var recordingLength = "00:00"
    @StateObject private var popoverState = PopoverState.shared
    
    var body: some View {
        HStack(spacing: 0) {
            if SCContext.streamType != nil {
                ZStack {
                    Rectangle()
                        .fill(Color.mypurple)
                        .shadow(color: .black.opacity(0.3), radius: 4)
                        .cornerRadius(4)
                    HStack(spacing: 4) {
                        if SCContext.isStopping {
                            Text("Processing...".local)
                                .foregroundStyle(.white)
                                .font(.system(size: 13))
                                .padding(.horizontal, 4)
                        } else {
                            Group {
                                Button(action: {
                                    SCContext.stopRecording()
                                }, label: {
                                    ZStack {
                                        Image(systemName: "circle.fill")
                                            .font(.system(size: 10))
                                            .foregroundStyle(.red)
                                            .frame(width: 10, alignment: .center)
                                        Image(systemName: "stop.circle.fill")
                                            .font(.system(size: 16))
                                            .foregroundStyle(.white)
                                            .frame(width: 16, alignment: .center)
                                    }
                                }).buttonStyle(.plain)
                                Button(action: {
                                    SCContext.pauseRecording()
                                }, label: {
                                    Image(systemName: popoverState.isPaused ? "play.circle.fill" : "pause.circle.fill")
                                        .font(.system(size: 16))
                                        .foregroundStyle(.white)
                                        .frame(width: 16, alignment: .center)
                                }).buttonStyle(.plain)
                                Text(recordingLength)
                                    .foregroundStyle(.white)
                                    .font(.system(size: 15).monospaced())
                                    .offset(x: 0.5)
                            }
                        }
                    }
                }
                .padding([.leading,.trailing], 4)
                .popover(isPresented: $popoverState.isShowing, arrowEdge: .bottom) {
                    CameraPopoverView(closePopover: { popoverState.isShowing = false })
                }
                .onReceive(updateTimer) { t in
                    recordingLength = SCContext.getRecordingLength()
                    stopAtAutomaticLimitIfNeeded(at: t)
                    if let visible = statusBarItem.button?.window?.occlusionState.contains(.visible) {
                        if visible { NSApp.windows.first(where: { $0.title == "Recording Controller".local })?.close(); return }
                        if SCContext.streamType != nil  && !visible && !(NSApp.windows.first(where: { $0.title == "Recording Controller".local })?.isVisible ?? false) {
                            guard let screen = SCContext.getScreenWithMouse() else { return }
                            let width = getStatusBarWidth()
                            let wX = (screen.frame.width - width) / 2
                            let contentView = NSHostingView(rootView: StatusBarItem())
                            contentView.frame = NSRect(x: wX, y: screen.visibleFrame.maxY, width: width, height: 24)
                            controlPanel.setFrame(contentView.frame, display: true)
                            controlPanel.contentView = contentView
                            controlPanel.makeKeyAndOrderFront(nil)
                        }
                    }
                }
                if SCContext.streamType != .systemaudio {
                    Button(action:{
                        popoverState.isShowing = true
                    }, label: {
                        ZStack {
                            Rectangle()
                                .fill(SCContext.isCameraRunning() ? Color.mygreen : .gray)
                                .shadow(color: .black.opacity(0.3), radius: 4)
                                .cornerRadius(4)
                            Image("camera")
                                .foregroundStyle(.white)
                        }.frame(width: 36).padding([.leading,.trailing], 4)
                    }).buttonStyle(.plain)
                }
            }
        }
        .onTapGesture {}
        .onHover { hovering in
            hideMousePointer = hovering
            hideScreenMagnifier = hovering
        }
    }
}

struct DiscreetRecordingStatusBarItem: View {
    var body: some View {
        Button {
            guard !SCContext.isStopping else { return }
            SCContext.stopRecording()
        } label: {
            Image(systemName: SCContext.isStopping ? "ellipsis.circle" : "record.circle.fill")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(SCContext.isStopping ? Color.secondary : Color.red)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(SCContext.isStopping)
        .help(SCContext.isStopping ? "Processing...".local : "Recording — Click to Stop".local)
        .onReceive(updateTimer) { date in
            stopAtAutomaticLimitIfNeeded(at: date)
        }
    }
}

private func stopAtAutomaticLimitIfNeeded(at date: Date) {
    guard !SCContext.isStopping, SCContext.autoStop != 0 else { return }
    let timePassed = Date.now.timeIntervalSince(SCContext.startTime ?? date)
    if timePassed / 60 >= CGFloat(SCContext.autoStop) {
        SCContext.stopRecording()
    }
}

func updateStatusBar() {
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
        guard let button = statusBarItem.button else { return }

        button.subviews
            .filter { $0.identifier == recordingStatusViewIdentifier }
            .forEach { $0.removeFromSuperview() }

        if SCContext.streamType == nil && !ud.bool(forKey: "showMenubar") {
            closeStatusBarPopover()
            statusBarItem.isVisible = false
            return
        }

        if SCContext.streamType == nil {
            configureIdleStatusBarItem(statusBarItem)
            return
        }

        closeStatusBarPopover()
        button.image = nil
        button.title = ""
        button.target = nil
        button.action = nil
        let indicatorStyle = RecordingIndicatorStyle(
            rawValue: ud.string(forKey: "recordingIndicatorStyle") ?? ""
        ) ?? .defaultValue
        let isDiscreet = indicatorStyle == .discreet
        if isDiscreet { controlPanel.close() }
        statusBarItem.length = isDiscreet ? NSStatusItem.squareLength : getStatusBarWidth()
        let rootView = isDiscreet
            ? AnyView(DiscreetRecordingStatusBarItem())
            : AnyView(StatusBarItem().padding(.top, -2))
        let iconView = NSHostingView(rootView: rootView)
        iconView.identifier = recordingStatusViewIdentifier
        iconView.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(iconView)
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: button.leadingAnchor),
            iconView.trailingAnchor.constraint(equalTo: button.trailingAnchor),
            iconView.topAnchor.constraint(equalTo: button.topAnchor),
            iconView.bottomAnchor.constraint(equalTo: button.bottomAnchor)
        ])
        button.setAccessibilityLabel("QuickRecorder")
        statusBarItem.isVisible = true
    }
}
