import Foundation
import VideoToolbox
import CoreMedia
import CoreVideo

final class H264Encoder {
    private var session: VTCompressionSession?
    private let queue = DispatchQueue(label: "h264.encoder")
    private(set) var width: Int32
    private(set) var height: Int32
    var onEncoded: ((Data, Bool) -> Void)?

    init(width: Int32, height: Int32, fps: Int = 60, bitrate: Int = 4_000_000) {
        self.width = width
        self.height = height

        let status = VTCompressionSessionCreate(allocator: kCFAllocatorDefault,
                                                width: width,
                                                height: height,
                                                codecType: kCMVideoCodecType_H264,
                                                encoderSpecification: nil,
                                                imageBufferAttributes: nil,
                                                compressedDataAllocator: nil,
                                                outputCallback: compressionOutputCallback,
                                                refcon: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
                                                compressionSessionOut: &session)
        guard status == noErr, let session = session else {
            print("VTCompressionSessionCreate failed: \(status)")
            return
        }

        // Settings for low-latency, no B-frames (use labeled API)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_MaxKeyFrameInterval, value: NSNumber(value: fps))
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AverageBitRate, value: NSNumber(value: bitrate))

        // Profile level (baseline -> no B-frames)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ProfileLevel, value: kVTProfileLevel_H264_Baseline_AutoLevel)

        VTCompressionSessionPrepareToEncodeFrames(session)
    }

    deinit {
        if let s = session {
            VTCompressionSessionInvalidate(s)
        }
    }

    func encode(pixelBuffer: CVPixelBuffer, presentationTimeStamp: CMTime) {
        queue.async { [weak self] in
            guard let self = self, let session = self.session else { return }
            var flags = VTEncodeInfoFlags()
            let status = VTCompressionSessionEncodeFrame(session,
                                                         imageBuffer: pixelBuffer,
                                                         presentationTimeStamp: presentationTimeStamp,
                                                         duration: CMTime.invalid,
                                                         frameProperties: nil,
                                                         sourceFrameRefcon: nil,
                                                         infoFlagsOut: &flags)
            if status != noErr {
                // ignore error for now
                // print("VTCompressionSessionEncodeFrame failed: \(status)")
            }
            // Note: encoded data will be delivered via callback
        }
    }

    // Convert sampleBuffer (AVCC) to Annex-B and invoke callback
    fileprivate func handleEncodedSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard CMSampleBufferDataIsReady(sampleBuffer) else { return }

        // Check keyframe
        var isKeyframe = false
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [CFDictionary], let attach = attachments.first {
            let dict = attach as NSDictionary
            if let notSync = dict[kCMSampleAttachmentKey_NotSync as NSString] as? Bool {
                isKeyframe = !notSync
            }
        }

        var out = Data()

        // If keyframe, extract SPS/PPS
        if isKeyframe, let fmt = CMSampleBufferGetFormatDescription(sampleBuffer) {
            var spsPointer: UnsafePointer<UInt8>?
            var spsSize: Int = 0
            let spsStatus = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(fmt, parameterSetIndex: 0, parameterSetPointerOut: &spsPointer, parameterSetSizeOut: &spsSize, parameterSetCountOut: nil, nalUnitHeaderLengthOut: nil)
            if spsStatus == noErr, let sps = spsPointer {
                let spsData = Data(bytes: sps, count: spsSize)
                out.append(contentsOf: [0,0,0,1])
                out.append(spsData)
            }

            var ppsPointer: UnsafePointer<UInt8>?
            var ppsSize: Int = 0
            let ppsStatus = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(fmt, parameterSetIndex: 1, parameterSetPointerOut: &ppsPointer, parameterSetSizeOut: &ppsSize, parameterSetCountOut: nil, nalUnitHeaderLengthOut: nil)
            if ppsStatus == noErr, let pps = ppsPointer {
                let ppsData = Data(bytes: pps, count: ppsSize)
                out.append(contentsOf: [0,0,0,1])
                out.append(ppsData)
            }
        }

        // Append NAL units converted from length-prefixed (AVCC) to Annex-B
        if let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) {
            var totalLength = 0
            var dataPointer: UnsafeMutablePointer<Int8>? = nil
            let status = CMBlockBufferGetDataPointer(dataBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &totalLength, dataPointerOut: &dataPointer)
            if status == kCMBlockBufferNoErr, let dataPointer = dataPointer {
                var offset = 0
                while offset < totalLength {
                    if offset + 4 > totalLength { break }
                    // read nal length (big-endian)
                    let nalLengthBytes = UnsafeRawPointer(dataPointer.advanced(by: offset)).assumingMemoryBound(to: UInt32.self).pointee
                    let nalLength = Int(CFSwapInt32BigToHost(nalLengthBytes))
                    let start = offset + 4
                    if start + nalLength > totalLength { break }
                    // start code
                    out.append(contentsOf: [0,0,0,1])
                    out.append(Data(bytes: UnsafeRawPointer(dataPointer.advanced(by: start)), count: nalLength))
                    offset = start + nalLength
                }
            }
        }

        // Deliver
        if !out.isEmpty {
            onEncoded?(out, isKeyframe)
        }
    }
}

// MARK: - Compression Output Callback

private let compressionOutputCallback: VTCompressionOutputCallback = { (outputCallbackRefCon, sourceFrameRefCon, status, infoFlags, sampleBuffer) in
    guard status == noErr, let sampleBuffer = sampleBuffer, CMSampleBufferDataIsReady(sampleBuffer) else { return }
    let encoder: H264Encoder = Unmanaged<H264Encoder>.fromOpaque(outputCallbackRefCon!).takeUnretainedValue()
    encoder.handleEncodedSampleBuffer(sampleBuffer)
}
