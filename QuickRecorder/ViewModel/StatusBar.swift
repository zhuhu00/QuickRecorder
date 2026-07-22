//
//  StatusBarItem.swift
//  QuickRecorder
//
//  Created by apple on 2024/4/16.
//

import SwiftUI

private let statusBarPopover = NSPopover()

private final class StatusBarActionTarget: NSObject {
    static let shared = StatusBarActionTarget()

    @objc func togglePopover(_ sender: NSStatusBarButton) {
        if statusBarPopover.isShown {
            statusBarPopover.performClose(nil)
            return
        }

        statusBarPopover.behavior = .transient
        statusBarPopover.contentViewController = NSHostingController(rootView: AnyView(ContentViewNew()))
        statusBarPopover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        DispatchQueue.main.async { restoreCameraOverlayerIfNeeded() }
    }
}

private func restoreCameraOverlayerIfNeeded() {
    guard !SCContext.recordCam.isEmpty,
          !AppDelegate.shared.isPresenterON,
          camWindow.contentView != nil else { return }
    camWindow.orderFrontRegardless()
}

class PopoverState: ObservableObject {
    static let shared = PopoverState()
    @Published var isShowing: Bool = false
    @Published var isPaused: Bool = false
}

struct StatusBarItem: View {
    @State private var isMainMenuShowing = false
    @State private var isHovering = false
    @State private var recordingLength = "00:00"
    //@State private var isPassed = SCContext.isPaused
    @StateObject private var popoverState = PopoverState.shared
    //@NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @AppStorage("miniStatusBar") private var miniStatusBar: Bool = false
    //@AppStorage("highlightMouse") private var highlightMouse: Bool = false
    private var appDelegate = AppDelegate.shared
    
    var body: some View {
        HStack(spacing: 0) {
            if SCContext.streamType != nil {
                ZStack {
                    Rectangle()
                        .fill(Color.mypurple)
                        .shadow(color: .black.opacity(0.3), radius: 4)
                        .cornerRadius(4)
                    HStack(spacing: 4) {
                        if miniStatusBar {
                            if isHovering && !SCContext.isStopping {
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
                                if SCContext.streamType != .systemaudio && SCContext.streamType != .window {
                                    Button(action:{
                                        popoverState.isShowing = true
                                    }, label: {
                                        Image(systemName: "camera.circle.fill")
                                            .font(.system(size: 16))
                                            .foregroundStyle(.white)
                                            .frame(width: 16, alignment: .center)
                                    }).buttonStyle(.plain)
                                }
                            } else {
                                Text(SCContext.isStopping ? "Processing...".local : recordingLength)
                                    .foregroundStyle(.white)
                                    .font(.system(size: 15).monospaced())
                                    .offset(x: 0.5)
                            }
                        } else if SCContext.isStopping {
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
                    let timePassed = Date.now.timeIntervalSince(SCContext.startTime ?? t)
                    if SCContext.autoStop != 0 && timePassed / 60 >= CGFloat(SCContext.autoStop) { SCContext.stopRecording() }
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
                if !miniStatusBar {
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
            } else if ud.bool(forKey: "showMenubar") {
                Button(action: {
                    popoverState.isShowing = true
                }, label: {
                    ZStack {
                        Color.white.opacity(0.0001)
                        Image(systemName: "dot.circle.and.hand.point.up.left.fill")
                            .font(.system(size: 14, weight: .medium))
                            .offset(y: 1)
                    }
                })
                .buttonStyle(.plain)
                .popover(isPresented: $popoverState.isShowing, arrowEdge: .bottom) {
                    ContentViewNew().onAppear { restoreCameraOverlayerIfNeeded() }
                }
            }
        }
        .onTapGesture {}
        .onHover { hovering in
            isHovering = hovering
            hideMousePointer = hovering
            hideScreenMagnifier = hovering
        }
    }
}

func updateStatusBar() {
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
        if SCContext.streamType == nil && !ud.bool(forKey: "showMenubar") {
            statusBarPopover.performClose(nil)
            statusBarItem.isVisible = false
            return
        }
        guard let button = statusBarItem.button else { return }

        button.subviews.forEach { $0.removeFromSuperview() }
        button.image = nil
        button.title = ""

        if SCContext.streamType == nil {
            statusBarItem.length = NSStatusItem.squareLength
            let configuration = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
            let image = NSImage(systemSymbolName: "record.circle", accessibilityDescription: "QuickRecorder")?
                .withSymbolConfiguration(configuration)
            image?.isTemplate = true
            button.image = image
            button.imagePosition = .imageOnly
            button.target = StatusBarActionTarget.shared
            button.action = #selector(StatusBarActionTarget.togglePopover(_:))
            button.toolTip = "QuickRecorder"
            button.setAccessibilityLabel("QuickRecorder")
            statusBarItem.isVisible = true
            return
        }

        statusBarPopover.performClose(nil)
        button.target = nil
        button.action = nil
        statusBarItem.length = getStatusBarWidth()
        let iconView = NSHostingView(rootView: StatusBarItem().padding(.top, -2))
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
