//
//  AVContext.swift
//  QuickRecorder
//
//  Created by apple on 2024/4/27.
//
import AppKit
import Foundation
import AVFoundation

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
