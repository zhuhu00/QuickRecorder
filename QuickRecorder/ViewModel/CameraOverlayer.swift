//
//  CameraOverlayer.swift
//  QuickRecorder
//
//  Created by apple on 2024/4/29.
//

import SwiftUI
import AppKit
import Foundation
import AVFoundation

extension AppDelegate {
    func startCameraOverlayer(size: NSSize = NSSize(width: 200, height: 200)){
        guard let screen = SCContext.getScreenWithMouse() else { return }
        let shouldCenterWindow = camWindow.contentView == nil
        camWindow.isOpaque = false
        camWindow.contentAspectRatio = NSSize(width: 1, height: 1)
        camWindow.contentMinSize = NSSize(width: 100, height: 100)
        camWindow.contentView = NSHostingView(rootView: SwiftCameraView())
        if shouldCenterWindow {
            let frame = NSRect(x: (screen.visibleFrame.width-size.width)/2+screen.frame.minX, y: (screen.visibleFrame.height-size.height)/2+screen.frame.minY, width: size.width, height: size.height)
            camWindow.setFrame(frame, display: true)
        }
        camWindow.orderFrontRegardless()
    }
}

struct CameraView: NSViewRepresentable {
    func makeNSView(context: Context) -> CameraNSView {
        let cameraView = CameraNSView(frame: .zero)
        return cameraView
    }

    func updateNSView(_ nsView: CameraNSView, context: Context) {
        // Update the view
    }
}

class CameraNSView: NSView {
    var session = SCContext.captureSession
    var previewLayer: AVCaptureVideoPreviewLayer? = nil
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setupCaptureSession()
    }
        
    required init?(coder decoder: NSCoder) {
        super.init(coder: decoder)
        wantsLayer = true
        setupCaptureSession()
    }
    
    private func setupCaptureSession() {
        guard let session = session else { return }
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer!.frame = bounds
        previewLayer!.videoGravity = AVLayerVideoGravity.resizeAspectFill
        previewLayer!.setAffineTransform(CGAffineTransform(scaleX: -1, y: 1))
        layer?.addSublayer(previewLayer!)
    }
    
    override func layout() {
        super.layout()
        previewLayer?.frame = bounds
        layer?.cornerRadius = min(bounds.width, bounds.height) / 2
        layer?.masksToBounds = true
    }
}

struct SwiftCameraView: View {
    @State private var hover = false
    @State private var isFlipped = false
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ZStack(alignment: Alignment(horizontal: .trailing, vertical: .bottom)) {
                    CameraView()
                        .rotation3DEffect(.degrees(isFlipped ? 180 : 0), axis: (x: 0, y: 1, z: 0))
                    Button(action: {
                        isFlipped.toggle()
                    }, label: {
                        ZStack {
                            Circle().frame(width: 30)
                                .foregroundStyle(hover ? .blue : .gray)
                            Image(systemName: "arrow.left.and.right.righttriangle.left.righttriangle.right.fill")
                                .foregroundStyle(.white)
                                .offset(y: -1)
                        }
                        .opacity(hover ? 0.8 : 0.2)
                        .onHover{ hovering in hover = hovering }
                    })
                    .buttonStyle(.plain)
                    .padding(25)
                }.frame(width: geometry.size.width, height: geometry.size.height)
                if SCContext.streamType == .window {
                    Text("Unable to use camera overlayer when recording a single window!".local
                         + " Please use \"Presenter Overlay\"".local)
                    .padding()
                    .colorInvert()
                    .background(.secondary)
                }
            }
            .clipShape(Circle())
            .overlay {
                Circle()
                    .strokeBorder(.white.opacity(0.75), lineWidth: 2)
            }
        }
        .frame(minWidth: 100, minHeight: 100)
        .onHover { hovering in
            hideMousePointer = hovering
            hideScreenMagnifier = hovering
        }
    }
}


struct CameraPopoverView: View {
    var closePopover: () -> Void
    @State private var cameras = SCContext.getCameras()
    @State private var hoverIndex = -1
    @State private var disabled = false
    //@NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var appDelegate = AppDelegate.shared
    
    var body: some View {
        VStack( alignment: .leading, spacing: 0) {
            if cameras.count < 1 {
                HStack {
                    ZStack {
                        Circle().frame(width: 26)
                            .foregroundStyle(.primary)
                            .opacity(0.2)
                        Image(systemName:"video.slash.fill")
                            .foregroundStyle(.primary)
                            .font(.system(size: 12))
                    }.padding(.leading, 9)
                    Text("No Cameras Found!".local)
                        .padding(.vertical, 8).padding(.trailing, 10)
                }.frame(maxWidth: .infinity)
            }
            ForEach(cameras.indices, id: \.self) { index in
                Button(action: {
                    closePopover()
                    if SCContext.recordCam == cameras[index].localizedName {
                        SCContext.recordCam = ""
                        appDelegate.closeCamera()
                        return
                    }
                    SCContext.recordCam = cameras[index].localizedName
                    appDelegate.closeCamera()
                    appDelegate.recordingCamera(with: cameras[index])
                }, label: {
                    HStack {
                        ZStack {
                            Circle().frame(width: 26)
                                .foregroundStyle(SCContext.recordCam == cameras[index].localizedName ? .blue : .primary)
                                .opacity(SCContext.recordCam == cameras[index].localizedName ? 1.0 : 0.2)
                            Image(systemName: "video.fill")
                                .foregroundStyle(SCContext.recordCam == cameras[index].localizedName ? .white : .primary)
                                .font(.system(size: 12))
                        }.padding(.leading, 9)
                        Text(cameras[index].localizedName)
                            .padding(.vertical, 8).padding(.trailing, 10)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .foregroundStyle(.primary)
                            .opacity(hoverIndex == index ? 0.2 : 0.0)
                    )
                    .onHover{ hovering in
                        if hoverIndex != index { hoverIndex = index }
                        if !hovering { hoverIndex = -1 }
                    }
                }).buttonStyle(.plain)
            }
        }.padding(5)
    }
}
