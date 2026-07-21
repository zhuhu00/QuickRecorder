//
//  AVContext.swift
//  QuickRecorder
//
//  Created by apple on 2024/4/27.
//
import AppKit
import Foundation
import AVFoundation
import UserNotifications

private let cameraSessionQueue = DispatchQueue(
    label: "io.github.zhuhu00.QuickRecorder.camera-session",
    qos: .userInitiated
)

private func handleCameraSetupFailure(for session: AVCaptureSession) {
    DispatchQueue.main.async {
        guard SCContext.captureSession === session else { return }
        print("Failed to set up camera")
        SCContext.recordCam = ""
        camWindow.orderOut(nil)
        SCContext.requestCameraPermission()
    }
}

extension AppDelegate {
    func recordingCamera(with device: AVCaptureDevice) {
        let session = AVCaptureSession()
        SCContext.captureSession = session
        DispatchQueue.main.async {
            guard SCContext.recordCam == device.localizedName else { return }
            self.startCameraOverlayer()
        }
        cameraSessionQueue.async {
            guard SCContext.captureSession === session,
                  SCContext.recordCam == device.localizedName else { return }
            guard let input = try? AVCaptureDeviceInput(device: device) else {
                handleCameraSetupFailure(for: session)
                return
            }

            session.beginConfiguration()
            guard session.canAddInput(input) else {
                session.commitConfiguration()
                handleCameraSetupFailure(for: session)
                return
            }
            session.addInput(input)

            let videoOutput = AVCaptureVideoDataOutput()
            videoOutput.setSampleBufferDelegate(self, queue: .global())
            if session.canAddOutput(videoOutput) { session.addOutput(videoOutput) }
            session.commitConfiguration()

            guard SCContext.captureSession === session,
                  SCContext.recordCam == device.localizedName else { return }
            session.startRunning()
        }
    }
    
    func closeCamera() {
        if camWindow.isVisible { camWindow.orderOut(nil) }
        guard let session = SCContext.captureSession else { return }
        cameraSessionQueue.async {
            if session.isRunning { session.stopRunning() }
        }
    }
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        /* 保留后续以作他用
        if !SCContext.isPaused && ud.string(forKey: "recordCam") != "" {
            if sampleBuffer.isValid { SCContext.isCameraReady = true }
            if sampleBuffer.imageBuffer != nil { SCContext.frameCache = sampleBuffer }
        }*/
    }
}

class AVOutputClass: NSObject, AVCaptureFileOutputRecordingDelegate, AVCaptureVideoDataOutputSampleBufferDelegate {
    static let shared = AVOutputClass()
    var output: AVCaptureMovieFileOutput!
    var dataOutput: AVCaptureVideoDataOutput!
    //var captureSession: AVCaptureSession!
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        //print(sampleBuffer.nsImage?.size)
    }
    
    public func startRecording(with device: AVCaptureDevice, mute: Bool = false, preset: AVCaptureSession.Preset = .high, didOutput: Bool = true) {
        output = AVCaptureMovieFileOutput()
        dataOutput = AVCaptureVideoDataOutput()
        dataOutput.setSampleBufferDelegate(self, queue: .global())
        SCContext.captureSession = AVCaptureSession()
        SCContext.previewSession = AVCaptureSession()
        SCContext.captureSession.sessionPreset = preset
        SCContext.previewSession.sessionPreset = preset
        
        guard let input = try? AVCaptureDeviceInput(device: device),
              let preview = try? AVCaptureDeviceInput(device: device),
              SCContext.captureSession.canAddInput(input),
              SCContext.previewSession.canAddInput(preview),
              SCContext.captureSession.canAddOutput(output),
              SCContext.previewSession.canAddOutput(dataOutput) else {
            print("Failed to set up camera or device")
            SCContext.requestCameraPermission()
            return
        }
        
        SCContext.captureSession.addInput(input)
        SCContext.captureSession.addOutput(output)
        SCContext.previewSession.addInput(preview)
        SCContext.previewSession.addOutput(dataOutput)
        
        if mute {
            if let audioConnection = output.connection(with: .audio) {
                SCContext.captureSession.removeConnection(audioConnection)
                /*DispatchQueue.main.async {
                    let alert = createAlert(title: "No Audio Connection",
                                                               message: "Unable to get audio stream on this device, only screen content will be recorded!",
                                                               button1: "OK")
                    alert.runModal()
                }*/
            }
        }
        
        if didOutput {
            let encoderIsH265 = ud.string(forKey: "encoder") == Encoder.h265.rawValue
            let videoSettings: [String: Any] = [ AVVideoCodecKey: encoderIsH265 ? AVVideoCodecType.hevc : AVVideoCodecType.h264 ]
            guard let connection = output.connection(with: .video) else { return }
            output.setOutputSettings(videoSettings, for: connection)
            let fileEnding = ud.string(forKey: "videoFormat") ?? ""
            SCContext.filePath = "\(SCContext.getFilePath()).\(fileEnding)"
            SCContext.captureSession.startRunning()
            output.startRecording(to: SCContext.filePath.url, recordingDelegate: self)
            SCContext.streamType = StreamType.idevice
            SCContext.startTime = Date.now
        }
        
        SCContext.previewSession.startRunning()
        DispatchQueue.main.async {
            closeAllWindow(except: "Area Overlayer".local)
            updateStatusBar()
            AppDelegate.shared.startDeviceOverlayer(size: NSSize(width: 300, height: 500))
        }
    }

    public func stopRecording() {
        if SCContext.captureSession.isRunning {
            output.stopRecording()
            SCContext.captureSession.stopRunning()
            SCContext.previewSession.stopRunning()
            SCContext.streamType = nil
            SCContext.startTime = nil
            DispatchQueue.main.async {
                controlPanel.close()
                deviceWindow.close()
                updateStatusBar()
            }
        }
    }
    
    func closePreview() {
        if SCContext.isCameraRunning() {
            //SCContext.previewType = nil
            if deviceWindow.isVisible { deviceWindow.close() }
            if let preview = SCContext.previewSession { preview.stopRunning() }
        }
    }

    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        let content = UNMutableNotificationContent()
        content.title = "Recording Completed".local
        content.body = String(format: "File saved to: %@".local, outputFileURL.path)
        content.sound = UNNotificationSound.default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: "quickrecorder.completed.\(UUID().uuidString)", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error { print("Notification failed to send：\(error.localizedDescription)") }
        }
    }
}
