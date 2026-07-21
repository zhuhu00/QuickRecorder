//
//  ContentView.swift
//  QuickRecorder
//
//  Created by apple on 2024/4/16.
//

import SwiftUI
import AVFoundation
import ScreenCaptureKit

struct ContentViewNew: View {
    @State private var window: NSWindow?
    @State private var xmarkGlowing = false
    @State private var infoGlowing = false
    @State private var micGlowing = false
    @State private var isPopoverShowing = false
    @State private var cameraIsRunning = false
    @State private var cameraList = SCContext.getCameras()
    @State private var micList = SCContext.getMicrophone()
    @AppStorage("enableAEC") private var enableAEC: Bool = false
    @AppStorage("cameraDevice") private var cameraDevice: String = "default"
    @AppStorage("recordMic") private var recordMic: Bool = false
    @AppStorage("micDevice") private var micDevice: String = "default"
    @AppStorage("showMouse") private var showMouse: Bool = true
    @AppStorage("showOnDock") private var showOnDock: Bool = true
    @AppStorage("showMenubar") private var showMenubar: Bool = true

    var appDelegate = AppDelegate.shared
    
    var body: some View {
        ZStack {
            ZStack {
                if isTodayChristmas() && isAllowChristmas() {
                    let images = ["snowflake1", "snowflake2", "snowflake3", "christmasTree1", "christmasTree2"]
                    SurpriseView(snowflakes: images, width: 520, height: 200, velocity: 16, lifetime: 30, alphaSpeed: -0.05)
                } else if isChineseNewYear() && isAllowChineseNewYear() {
                    let images = ["fuzi1", "fuzi2", "fuzi3", "hongbao1", "hongbao2", "hongbao3", "bianpao1", "bianpao2", "bianpao3"]
                    SurpriseView(snowflakes: images, width: 520, height: 200, velocity: 16, lifetime: 30, alphaSpeed: -0.05)
                }
            }.opacity(0.5)
            VStack {
                HStack {
                    Button(action: {
                        closeMainWindow()
                        appDelegate.createNewWindow(view: ScreenSelector(), title: "Screen Selector".local)
                    }, label: {
                        SelectorView(title: "Screen".local, symbol: "tv.inset.filled").cornerRadius(8)
                    }).buttonStyle(.plain)
                    Divider().frame(height: 70)
                    Button(action: {
                        closeMainWindow()
                        SCContext.updateAvailableContent {
                            DispatchQueue.main.async {
                                appDelegate.showAreaSelector(size: NSSize(width: 600, height: 450))
                                var currentDisplay = SCContext.getSCDisplayWithMouse()
                                mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .rightMouseDown, .leftMouseDown, .otherMouseDown]) { event in
                                    let display = SCContext.getSCDisplayWithMouse()
                                    if display != currentDisplay {
                                        currentDisplay = display
                                        closeAllWindow()
                                        appDelegate.showAreaSelector(size: NSSize(width: 600, height: 450))
                                    }
                                }
                            }
                        }
                    }, label: {
                        SelectorView(title: "Screen Area".local, symbol: "viewfinder").cornerRadius(8)
                    }).buttonStyle(.plain)
                    Divider().frame(height: 70)
                    Button(action: {
                        closeMainWindow()
                        appDelegate.createNewWindow(view: AppSelector(), title: "App Selector".local)
                    }, label: {
                        SelectorView(title: "Application".local, symbol: "app", overlayer: "App")
                            .cornerRadius(8)
                    }).buttonStyle(.plain)
                    Divider().frame(height: 70)
                    Button(action: {
                        closeMainWindow()
                        appDelegate.createNewWindow(view: WinSelector(), title: "Window Selector".local)
                    }, label: {
                        SelectorView(title: "Window".local, symbol: "macwindow").cornerRadius(8)
                    }).buttonStyle(.plain)
                }
                HStack(spacing: 27) {
                    VStack { Divider().frame(width: 100) }
                    VStack { Divider().frame(width: 100) }
                    VStack { Divider().frame(width: 100) }
                    VStack { Divider().frame(width: 100) }
                }
                HStack {
                    ZStack(alignment: Alignment(horizontal: .center, vertical: .bottom)) {
                        Button(action: {
                            if let display = SCContext.getSCDisplayWithMouse() {
                                closeMainWindow()
                                appDelegate.createCountdownPanel(screen: display) {
                                    AppDelegate.shared.prepRecord(type: "audio", screens: SCContext.getSCDisplayWithMouse(), windows: nil, applications: nil)
                                }
                            }
                        }, label: {
                            SelectorView(title: "System Audio".local, symbol: "waveform").cornerRadius(8)
                        }).buttonStyle(.plain)
                        Button {} label: {
                            HStack(spacing: -2) {
                                Button {
                                    recordMic.toggle()
                                } label: {
                                    ZStack {
                                        Image(systemName: "square.fill")
                                            .font(.system(size: 15, weight: .medium))
                                            .foregroundColor(.primary)
                                            .colorInvert()
                                            .opacity(0.2)
                                        Image(systemName: recordMic ? "checkmark.square" : "square")
                                            .font(.system(size: 16, weight: .medium))
                                    }
                                }
                                .buttonStyle(.plain)
                                .onChange(of: recordMic) { _ in  Task { await SCContext.performMicCheck() }}
                                if micDevice != "default" && enableAEC && recordMic{
                                    Button {
                                        let alert = createAlert(
                                            title: "Compatibility Warning".local,
                                            message: "The \"Acoustic Echo Cancellation\" is enabled, but it won't work on now.\n\nIf you need to use a specific input with AEC, set it to \"Default\" and select the device you want in System Preferences.\n\nOr you can start recording without AEC.".local,
                                            button1: "OK".local, button2: "System Preferences".local)
                                        if alert.runModal() == .alertSecondButtonReturn {
                                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.sound?input")!)
                                        }
                                    } label: {
                                        ZStack {
                                            Image(systemName: "circle.fill").font(.system(size: 15))
                                            Image(systemName: "exclamationmark")
                                                .font(.system(size: 11.5, weight: .black))
                                                .foregroundColor(.black)
                                                .blendMode(.destinationOut)
                                        }.compositingGroup()
                                    }
                                    .buttonStyle(.plain)
                                    .frame(width: 24).fixedSize()
                                    .padding(.leading, 1)
                                } else {
                                    Image(systemName: "mic.fill")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundColor(recordMic ? .primary : .secondary)
                                        .frame(width: 24)
                                        .padding(.leading, 1)
                                }
                                if #available(macOS 14, *) {
                                    Picker("", selection: $micDevice) {
                                        Text("Default".local).tag("default")
                                        ForEach(micList, id: \.self) { device in
                                            Text(device.localizedName).tag(device.localizedName)
                                        }
                                    }.frame(width: 90)
                                        .background(
                                            ZStack {
                                                Color.primary
                                                    .opacity(0.1)
                                                    .cornerRadius(4)
                                                    .padding(.vertical, -1)
                                                    .padding(.horizontal, 3)
                                                    .padding(.trailing, -16)
                                                Image(systemName: "chevron.up.chevron.down")
                                                    .offset(x: 50)
                                            }
                                        )
                                        .disabled(!recordMic)
                                        .padding(.leading, -10)
                                        .frame(width: 99)
                                        .onAppear{
                                            let list = micList.map({ $0.localizedName })
                                            if !list.contains(micDevice) { micDevice = "default" }
                                        }
                                } else {
                                    Spacer().frame(width: 6)
                                    Picker("", selection: $micDevice) {
                                        Text("Default".local).tag("default")
                                        ForEach(micList, id: \.self) { device in
                                            Text(device.localizedName).tag(device.localizedName)
                                        }
                                    }
                                    .disabled(!recordMic)
                                    .padding(.leading, -7.5)
                                    .frame(width: 100)
                                    .onAppear{
                                        let list = micList.map({ $0.localizedName })
                                        if !list.contains(micDevice) { micDevice = "default" }
                                    }
                                }
                            }.padding(.leading, -5)
                        }
                        .buttonStyle(.plain)
                        .scaleEffect(0.69)
                        .padding(.bottom, 4)
                        .frame(width: 110)
                        .background(.primary.opacity(0.00001))
                    }.frame(height: 80)
                    Divider().frame(height: 70)
                    Button(action: {
                        isPopoverShowing = true
                    }, label: {
                        SelectorView(title: "Mobile Device".local, symbol: "apps.ipad").cornerRadius(8)
                    }).buttonStyle(.plain)
                        .popover(isPresented: $isPopoverShowing, arrowEdge: .bottom) {
                            iDevicePopoverView(closePopover: { isPopoverShowing = false })
                    }
                    Divider().frame(height: 70)
                    PreferencesButton()
                    Divider().frame(height: 70)
                    Button(action: {
                        NSApp.terminate(self)
                    }, label: {
                        SelectorView(title: "Quit".local, symbol: "xmark.circle")
                            .cornerRadius(8)
                            .foregroundStyle(.darkMyRed)
                    }).buttonStyle(.plain)
                }
                Divider()
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        Toggle(isOn: cameraEnabledBinding) {
                            Label("Camera".local, systemImage: "video.fill")
                        }
                        .toggleStyle(.checkbox)
                        .frame(width: 145, alignment: .leading)
                        .disabled(cameraList.isEmpty)

                        Picker("Camera".local, selection: $cameraDevice) {
                            if let preferredCamera {
                                Text("\("Default".local) — \(preferredCamera.localizedName)")
                                    .tag("default")
                            }
                            ForEach(cameraList.filter { $0.uniqueID != preferredCamera?.uniqueID }, id: \.uniqueID) { camera in
                                Text(camera.localizedName).tag(camera.uniqueID)
                            }
                        }
                        .labelsHidden()
                        .disabled(cameraList.isEmpty)
                        .frame(maxWidth: .infinity)
                        .controlSize(.small)
                        .onChange(of: cameraDevice) { _ in switchCameraIfRunning() }
                    }
                    .padding(.vertical, 6)

                    Divider()
                    HStack(spacing: 8) {
                        Toggle(isOn: $recordMic) {
                            Label("Microphone".local, systemImage: "mic.fill")
                        }
                        .toggleStyle(.checkbox)
                        .frame(width: 145, alignment: .leading)
                        .disabled(micList.isEmpty)

                        Picker("Microphone".local, selection: $micDevice) {
                            Text("Default".local).tag("default")
                            ForEach(micList, id: \.uniqueID) { microphone in
                                Text(microphone.localizedName).tag(microphone.localizedName)
                            }
                        }
                        .labelsHidden()
                        .disabled(micList.isEmpty)
                        .frame(maxWidth: .infinity)
                        .controlSize(.small)
                    }
                    .padding(.vertical, 6)

                    Divider()
                    Toggle(isOn: $showMouse) {
                        Label("Record Cursor".local, systemImage: "cursorarrow")
                    }
                    .toggleStyle(.checkbox)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 7)
                }
                .padding(.horizontal, 6)
                .onAppear {
                    refreshDevices()
                    refreshCameraState()
                }
                .onReceive(updateTimer) { _ in refreshCameraState() }
            }.padding(10)
        }
    }

    private var cameraEnabledBinding: Binding<Bool> {
        Binding(
            get: { cameraIsRunning },
            set: { enabled in
                guard enabled != cameraIsRunning else { return }
                toggleCamera()
            }
        )
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

    private var preferredCamera: AVCaptureDevice? {
        cameraList.first(where: { $0.deviceType == .builtInWideAngleCamera }) ?? cameraList.first
    }

    private var selectedCamera: AVCaptureDevice? {
        if cameraDevice == "default" { return preferredCamera }
        return cameraList.first(where: { $0.uniqueID == cameraDevice }) ?? preferredCamera
    }

    private func refreshDevices() {
        cameraList = SCContext.getCameras()
        micList = SCContext.getMicrophone()
        if cameraDevice != "default" && !cameraList.contains(where: { $0.uniqueID == cameraDevice }) {
            cameraDevice = "default"
        }
        if micDevice != "default" && !micList.contains(where: { $0.localizedName == micDevice }) {
            micDevice = "default"
        }
        if micList.isEmpty { recordMic = false }
    }

    private func refreshCameraState() {
        cameraIsRunning = !SCContext.recordCam.isEmpty
        if cameraIsRunning && !appDelegate.isPresenterON && !camWindow.isVisible && camWindow.contentView != nil {
            camWindow.orderFrontRegardless()
        }
    }
}
