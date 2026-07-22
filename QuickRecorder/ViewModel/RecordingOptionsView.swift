//
//  RecordingOptionsView.swift
//  QuickRecorder
//
//  Shared recording options for screen, area, and window recording.
//

import SwiftUI

struct OptionsView: View {
    @State private var micList = SCContext.getMicrophone()
    
    @AppStorage("frameRate")      private var frameRate: Int = 60
    @AppStorage("videoQuality")   private var videoQuality: Double = 1.0
    @AppStorage("saveDirectory")  private var saveDirectory: String?
    @AppStorage("hideSelf")       private var hideSelf: Bool = false
    @AppStorage("showMouse")      private var showMouse: Bool = true
    @AppStorage("recordMic")      private var recordMic: Bool = false
    @AppStorage("recordWinSound") private var recordWinSound: Bool = true
    @AppStorage("background")     private var background: BackgroundType = .wallpaper
    @AppStorage("highRes")        private var highRes: Int = 2
    @AppStorage("recordHDR")      private var recordHDR: Bool = false
    @AppStorage("micDevice")      private var micDevice: String = "default"
    @AppStorage("enableAEC")      private var enableAEC: Bool = false
    
    var body: some View {
        VStack(spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Resolution")
                    Text("Frame Rate")
                }
                VStack(alignment: .leading, spacing: 10) {
                    Picker("", selection: $highRes) {
                        Text("High (auto)").tag(2)
                        Text("Normal (1x)").tag(1)
                        //Text("Low (0.5x)").tag(0)
                    }
                    .buttonStyle(.borderless)
                    .frame(minWidth: isMacOS12 ? 100 : 10)
                    Picker("", selection: $frameRate) {
                        if ![240, 144, 120, 90, 60, 30, 24, 15 ,10].contains(frameRate) {
                            Text("\(frameRate) FPS").tag(frameRate)
                        }
                        Text("240 FPS").tag(240)
                        Text("144 FPS").tag(144)
                        Text("120 FPS").tag(120)
                        Text("90 FPS").tag(90)
                        Text("60 FPS").tag(60)
                        Text("30 FPS").tag(30)
                        Text("24 FPS").tag(24)
                        Text("15 FPS").tag(15)
                        Text("10 FPS").tag(10)
                    }
                    .buttonStyle(.borderless)
                    .frame(minWidth: isMacOS12 ? 100 : 10)
                }.scaledToFit()
                Divider().frame(height: 50)
                VStack(alignment: .leading, spacing: 10) {
                    Text("Quality")
                    Text("Background")
                }.padding(.leading, isMacOS12 ? 0 : 8)
                VStack(alignment: .leading, spacing: 10) {
                    Picker("", selection: $videoQuality) {
                        Text("High").tag(1.0)
                        Text("Medium").tag(0.7)
                        Text("Low").tag(0.3)
                    }
                    .buttonStyle(.borderless)
                    .frame(minWidth: isMacOS12 ? 100 : 10)
                    Picker("", selection: $background) {
                        Text("Wallpaper").tag(BackgroundType.wallpaper)
                        if ud.bool(forKey: "withAlpha") { Text("Transparent").tag(BackgroundType.clear) }
                        Text("Black").tag(BackgroundType.black)
                        Text("White").tag(BackgroundType.white)
                        Text("Gray").tag(BackgroundType.gray)
                        Text("Yellow").tag(BackgroundType.yellow)
                        Text("Orange").tag(BackgroundType.orange)
                        Text("Green").tag(BackgroundType.green)
                        Text("Blue").tag(BackgroundType.blue)
                        Text("Red").tag(BackgroundType.red)
                        Text("Custom").tag(BackgroundType.custom)
                    }
                    .buttonStyle(.borderless)
                    .frame(minWidth: isMacOS12 ? 100 : 10)
                }.scaledToFit()
                Divider().frame(height: 50)
                VStack(alignment: .leading, spacing: isMacOS12 ? 10 : 2) {
                    if #available(macOS 15, *) {
                        Toggle(isOn: $recordHDR) {
                            HStack(spacing:0){
                                Image(systemName: "sparkles.square.filled.on.square")
                                    .font(.subheadline)
                                    .frame(width: isMacOS12 ? 20 : 16)
                                Text("Record HDR")
                                    .font(.subheadline)
                            }
                        }
                        .fixedSize()
                        .toggleStyle(.checkbox)
                    }
                    Toggle(isOn: $showMouse) {
                        HStack(spacing: 0){
                            Image(systemName: "cursorarrow")
                                .font(isMacOS12 ? .body : .subheadline)
                                .frame(width: isMacOS12 ? 20 : 16)
                            Text("Record Cursor")
                                .font(isMacOS12 ? .body : .subheadline)
                        }
                    }
                    .fixedSize()
                    .toggleStyle(.checkbox)
                    if #available(macOS 13, *) {
                        Toggle(isOn: $recordWinSound) {
                            HStack(spacing: 0){
                                Image(systemName: "speaker.wave.1.fill")
                                    .font(isMacOS12 ? .body : .subheadline)
                                    .frame(width: isMacOS12 ? 20 : 16)
                                Text("App's Audio")
                                    .font(.subheadline)
                            }
                        }
                        .fixedSize()
                        .toggleStyle(.checkbox)
                    }
                    HStack(spacing: 0) {
                        Toggle(isOn: $recordMic) {
                            Image(systemName: "mic.fill")
                                .font(isMacOS12 ? .body : .subheadline)
                                .frame(width: isMacOS12 ? 20 : 16)
                        }
                        .fixedSize()
                        .toggleStyle(.checkbox)
                        .onChange(of: recordMic) { _ in
                            Task { await SCContext.performMicCheck() }
                        }
                        .onAppear{ if micList.isEmpty { recordMic = false } }
                        .disabled(micList.isEmpty)
                        Picker("", selection: $micDevice) {
                            Text("Default".local).tag("default")
                            ForEach(micList, id: \.self) { device in
                                Text(device.localizedName).tag(device.localizedName)
                            }
                        }
                        .disabled(!recordMic)
                        .scaleEffect(isMacOS12 ? 1 : 0.8)
                        .padding(.leading, isMacOS12 ? -7 : -16)
                        .frame(width: 90, height: isMacOS12 ? 20 :12)
                        .onAppear{
                            let list = micList.map({ $0.localizedName })
                            if !list.contains(micDevice) { micDevice = "default" }
                        }
                        Spacer().frame(width: 5)
                        if micDevice != "default" && enableAEC{
                            Button("⚠️", action: {
                                let alert = createAlert(
                                    title: "Compatibility Warning".local,
                                    message: "The \"Acoustic Echo Cancellation\" is enabled, but it won't work on now.\n\nIf you need to use a specific input with AEC, set it to \"Default\" and select the device you want in System Preferences.\n\nOr you can start recording without AEC.".local,
                                    button1: "OK".local, button2: "System Preferences".local)
                                if alert.runModal() == .alertSecondButtonReturn {
                                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.sound?input")!)
                                }
                            }).buttonStyle(.plain).fixedSize()
                        }
                    }
                }.padding(.trailing, isMacOS12 ? 0 : -17)
            }
        }
    }
}

