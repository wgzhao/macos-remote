import Foundation
import AVFoundation
import CoreMedia
import CoreVideo
import AppKit

protocol ScreenCapturer: AnyObject {
    var onFrame: ((CVPixelBuffer, CMTime) -> Void)? { get set }
    func start()
    func stop()
}

/// A simple screen capturer using AVCaptureScreenInput as a stable fallback.
/// Replace this implementation with ScreenCaptureKit-based one if you need.
final class AVScreenCapturer: NSObject, ScreenCapturer {
    var onFrame: ((CVPixelBuffer, CMTime) -> Void)?

    private let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "avscreen.capture")
    private let fps: Int

    init(fps: Int = 60) {
        self.fps = fps
        super.init()
    }

    func start() {
        session.beginConfiguration()
        session.sessionPreset = .high

        let displayID = CGMainDisplayID()
        guard let input = AVCaptureScreenInput(displayID: displayID) else {
            print("AVCaptureScreenInput not available")
            return
        }
        input.minFrameDuration = CMTime(value: 1, timescale: CMTimeScale(fps))
        input.capturesCursor = true
        input.capturesMouseClicks = true

        if session.canAddInput(input) {
            session.addInput(input)
        }

        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)

        if session.canAddOutput(output) {
            session.addOutput(output)
        }

        session.commitConfiguration()
        session.startRunning()
    }

    func stop() {
        session.stopRunning()
    }
}

extension AVScreenCapturer: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        onFrame?(pixelBuffer, pts)
    }
}
