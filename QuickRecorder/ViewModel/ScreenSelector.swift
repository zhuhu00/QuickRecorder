//
//  ScreenSelector.swift
//  QuickRecorder
//
//  Created by apple on 2024/4/18.
//

import SwiftUI
import ScreenCaptureKit

struct ScreenSelector: View {
    @Environment(\.colorScheme) var colorScheme
    @StateObject var viewModel = ScreenSelectorViewModel()
    
    @State private var selected: SCDisplay?
    @State private var isPopoverShowing = false
    @State private var autoStop = 0
    var appDelegate = AppDelegate.shared
    
    var body: some View {
        ZStack {
            VStack(spacing: 15) {
                Text("Please select the screen to record")
                let count = viewModel.screenThumbnails.count
                ScrollView(.vertical) {
                    VStack(spacing: 14){
                        ForEach(0..<viewModel.screenThumbnails.count/2 + 1, id: \.self) { rowIndex in
                            HStack(spacing: 30) {
                                ForEach(0..<2, id: \.self) { columnIndex in
                                    let index = 2 * rowIndex + columnIndex
                                    if index <= viewModel.screenThumbnails.count - 1 {
                                        Button(action: {
                                            selected = viewModel.screenThumbnails[index].screen
                                        }, label: {
                                            ZStack {
                                                VStack(spacing: 4) {
                                                    ZStack{
                                                        if colorScheme == .light {
                                                            Image(nsImage: viewModel.screenThumbnails[index].image)
                                                                .resizable()
                                                                .aspectRatio(contentMode: .fit)
                                                                .colorMultiply(.black)
                                                                .blur(radius: 0.5)
                                                                .opacity(1)
                                                        } else {
                                                            Image(nsImage: viewModel.screenThumbnails[index].image)
                                                                .resizable()
                                                                .aspectRatio(contentMode: .fit)
                                                                .colorMultiply(.black)
                                                                .colorInvert()
                                                                .blur(radius: 0.5)
                                                                .opacity(1)
                                                        }
                                                        Image(nsImage: viewModel.screenThumbnails[index].image)
                                                            .resizable()
                                                            .aspectRatio(contentMode: .fit)
                                                    }.frame(width: count == 1 ? 672 : 320, height: count == 1 ? 378 : 180, alignment: .center)
                                                    let screenName = NSScreen.screens.first(where: { $0.displayID == viewModel.screenThumbnails[index].screen.displayID })?.localizedName ?? "Display ".local + "\(viewModel.screenThumbnails[index].screen.displayID)"
                                                    Text(screenName)
                                                        .foregroundStyle(.secondary)
                                                        .lineLimit(1)
                                                        .truncationMode(.tail)
                                                        .offset(y:count == 1 ? 5 : 2)
                                                }
                                                .padding(count == 1 ? 19 : 10)
                                                .background(
                                                    Rectangle()
                                                        .foregroundStyle(.blue)
                                                        .cornerRadius(5)
                                                        .opacity((selected == viewModel.screenThumbnails[index].screen) ? 0.2 : 0.0)
                                                )
                                                Group {
                                                    Image(systemName: "circle.fill")
                                                        .font(.system(size: count == 1 ? 62 : 31))
                                                        .foregroundStyle(.white)
                                                        .opacity((selected == viewModel.screenThumbnails[index].screen) ? 1.0 : 0.0)
                                                    Image(systemName: "checkmark.circle.fill")
                                                        .font(.system(size: count == 1 ? 54 : 27))
                                                        .foregroundStyle(.green)
                                                        .opacity((selected == viewModel.screenThumbnails[index].screen) ? 1.0 : 0.0)
                                                }.offset(x: count == 1 ? 270 : 120, y: count == 1 ? 130 : 50)
                                            }
                                        }).buttonStyle(.plain)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, 35)
                        }
                    }
                }
                .frame(height: 445)
                
                HStack(spacing: 4) {
                    Button(action: {
                        viewModel.setupStreams()
                    }, label: {
                        VStack{
                            Image(systemName: "arrow.clockwise.circle.fill")
                                .font(.system(size: 36))
                                .foregroundStyle(.blue)
                            Text("Refresh")
                                .foregroundStyle(.secondary)
                                .font(.system(size: 12))
                        }
                        
                    }).buttonStyle(.plain)
                    Spacer()
                    OptionsView().padding(.leading, 18)
                    Spacer()
                    Button(action: {
                        isPopoverShowing = true
                    }, label: {
                        Image(systemName: "timer")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.blue)
                    })
                    .buttonStyle(.plain)
                    .padding(.top, 42.5)
                    .popover(isPresented: $isPopoverShowing, arrowEdge: .bottom, content: {
                        HStack {
                            Text(" Stop after".local)
                            TextField("", value: $autoStop, formatter: NumberFormatter())
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                            Stepper("", value: $autoStop)
                                .padding(.leading, -10)
                            Text("minutes ".local)
                        }
                        .fixedSize()
                        .padding()
                    })
                    Button(action: {
                        startRecording()
                    }, label: {
                        VStack{
                            Image(systemName: "record.circle.fill")
                                .font(.system(size: 36))
                                .foregroundStyle(.red)
                            Text("Start")
                                .foregroundStyle(.secondary)
                                .font(.system(size: 12))
                        }
                    })
                    .buttonStyle(.plain)
                    .disabled(selected == nil)
                }.padding(.horizontal, 40)
                Spacer()
            }
            .padding(.top, -5)
        }
        .frame(width: 780, height:555)
        .onDisappear {
            viewModel.stopAllStreams()
        }
    }
    
    func startRecording() {
        closeAllWindow()
        if let screen = selected {
            appDelegate.createCountdownPanel(screen: screen) {
                SCContext.autoStop = autoStop
                appDelegate.prepRecord(type: "display", screens: screen, windows: nil)
            }
        }
    }
}

class ScreenSelectorViewModel: NSObject, ObservableObject, SCStreamDelegate, SCStreamOutput {
    @Published var screenThumbnails = [ScreenThumbnail]()
    private var allScreens = [SCDisplay]()
    private var streams = [SCStream]()
    private var targets = [ObjectIdentifier: SCDisplay]()
    private var captureGeneration = 0
    private var isStartingStreams = false
    
    override init() {
        super.init()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.setupStreams()
        }
    }
    
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard CMSampleBufferGetImageBuffer(sampleBuffer) != nil,
              let screen = targets[ObjectIdentifier(stream)] else { return }
        let image = sampleBuffer.nsImage
            ?? SCContext.getWallpaper(screen)
            ?? NSImage.unknowScreen
        completeStream(stream, screen: screen, image: image)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        guard let screen = targets[ObjectIdentifier(stream)] else { return }
        print("Screen thumbnail capture stopped: \(error.localizedDescription)")
        completeStream(stream, screen: screen, image: NSImage.unknowScreen, stopCapture: false)
    }

    func setupStreams() {
        stopAllStreams()
        screenThumbnails.removeAll()
        let generation = captureGeneration

        SCContext.updateAvailableContent {
            Task { @MainActor in
                guard generation == self.captureGeneration else { return }
                self.isStartingStreams = true
                defer { self.isStartingStreams = false }
                do {
                    guard let screens = SCContext.availableContent?.displays else { return }
                    self.allScreens = screens
                    let qrSelf = SCContext.getSelf()
                    let contentFilters = self.allScreens.map { SCContentFilter(display: $0, excludingApplications: qrSelf != nil ? [qrSelf!] : [], exceptingWindows: []) }
                    for (index, contentFilter) in contentFilters.enumerated() {
                        guard generation == self.captureGeneration else { return }
                        let streamConfiguration = SCStreamConfiguration()
                        streamConfiguration.width = Int(self.allScreens[index].frame.width)
                        streamConfiguration.height = Int(self.allScreens[index].frame.height)
                        streamConfiguration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(1))
                        streamConfiguration.pixelFormat = kCVPixelFormatType_32BGRA
                        streamConfiguration.capturesAudio = false
                        streamConfiguration.showsCursor = false
                        streamConfiguration.queueDepth = 3
                        let stream = SCStream(filter: contentFilter, configuration: streamConfiguration, delegate: self)
                        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: .main)
                        self.streams.append(stream)
                        self.targets[ObjectIdentifier(stream)] = self.allScreens[index]
                        try await stream.startCapture()
                        guard generation == self.captureGeneration else {
                            try? await stream.stopCapture()
                            return
                        }
                        self.scheduleTimeout(for: stream, generation: generation)
                    }
                } catch {
                    print("Get screenshot error：\(error)")
                    self.stopAllStreams()
                }
            }
        }
    }

    func stopAllStreams() {
        captureGeneration &+= 1
        isStartingStreams = false
        let activeStreams = streams
        streams.removeAll()
        targets.removeAll()
        activeStreams.forEach { $0.stopCapture() }
    }

    private func scheduleTimeout(for stream: SCStream, generation: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self, weak stream] in
            guard let self, let stream,
                  generation == self.captureGeneration,
                  let screen = self.targets[ObjectIdentifier(stream)] else { return }
            self.completeStream(
                stream,
                screen: screen,
                image: SCContext.getWallpaper(screen) ?? NSImage.unknowScreen
            )
        }
    }

    private func completeStream(
        _ stream: SCStream,
        screen: SCDisplay,
        image: NSImage,
        stopCapture: Bool = true
    ) {
        let identifier = ObjectIdentifier(stream)
        guard targets.removeValue(forKey: identifier) != nil else { return }
        streams.removeAll { $0 === stream }
        if stopCapture { stream.stopCapture() }

        let thumbnail = ScreenThumbnail(image: image, screen: screen)
        if !screenThumbnails.contains(where: { $0.screen == screen }) {
            screenThumbnails.append(thumbnail)
        }
    }
}

class ScreenThumbnail {
    let image: NSImage
    let screen: SCDisplay

    init(image: NSImage, screen: SCDisplay) {
        self.image = image
        self.screen = screen
    }
}
