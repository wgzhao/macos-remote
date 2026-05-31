import Foundation
import VideoToolbox
import AVFoundation
import CoreMedia
import CoreVideo

final class H264Decoder {
    private var sps: Data?
    private var pps: Data?
    fileprivate var formatDesc: CMFormatDescription?
    private var session: VTDecompressionSession?
    fileprivate var displayLayer: AVSampleBufferDisplayLayer

    private var buffer = Data()

    init(displayLayer: AVSampleBufferDisplayLayer) {
        self.displayLayer = displayLayer
    }

    func parseAndDecode(nalData: Data) {
        // Append and split into NAL units by start codes
        buffer.append(nalData)
        let nalUnits = extractNALUnits(from: &buffer)
        for nal in nalUnits {
            if nal.count < 1 { continue }
            let nalType = nal[0] & 0x1F
            if nalType == 7 {
                sps = nal
            } else if nalType == 8 {
                pps = nal
            }
            if formatDesc == nil, let sps = sps, let pps = pps {
                createFormatDescription(sps: sps, pps: pps)
            }
            // Once formatDesc exists, feed each NAL as a compressed sample to decoder
            if let _ = formatDesc {
                decode(nal: nal)
            }
        }
    }

    private func extractNALUnits(from buffer: inout Data) -> [Data] {
        var units: [Data] = []
        // Search for start codes (0x00000001 or 0x000001)
        var start = 0
        let bytes = [UInt8](buffer)
        let len = bytes.count
        func isStartCode(_ i: Int) -> (Int)? {
            if i + 3 < len && bytes[i] == 0 && bytes[i+1] == 0 && bytes[i+2] == 0 && bytes[i+3] == 1 {
                return 4
            }
            if i + 2 < len && bytes[i] == 0 && bytes[i+1] == 0 && bytes[i+2] == 1 {
                return 3
            }
            return nil
        }

        var i = 0
        var positions: [Int] = []
        while i < len {
            if let sc = isStartCode(i) {
                positions.append(i)
                i += sc
            } else {
                i += 1
            }
        }
        // If no start code found, nothing to do
        if positions.isEmpty { return [] }
        // For each start position, find next start and extract NAL
        for idx in 0..<positions.count {
            let pos = positions[idx]
            let scLen = isStartCode(pos) ?? 0
            let nalStart = pos + scLen
            let end: Int
            if idx + 1 < positions.count {
                end = positions[idx+1]
            } else {
                end = len
            }
            if nalStart < end {
                let slice = Array(bytes[nalStart..<end])
                let nal = Data(slice)
                units.append(nal)
            }
        }
        // Remove consumed bytes from buffer
        if let lastPos = positions.last {
            buffer.removeFirst(lastPos)
        }
        return units
    }

    private func createFormatDescription(sps: Data, pps: Data) {
        sps.withUnsafeBytes { spsPtr in
            pps.withUnsafeBytes { ppsPtr in
                let spsP = spsPtr.bindMemory(to: UInt8.self).baseAddress!
                let ppsP = ppsPtr.bindMemory(to: UInt8.self).baseAddress!

                var parameterSetPointers: [UnsafePointer<UInt8>?] = [UnsafePointer<UInt8>(spsP), UnsafePointer<UInt8>(ppsP)]
                var parameterSetSizes: [Int] = [sps.count, pps.count]
                var fmt: CMFormatDescription? = nil
                let status = CMVideoFormatDescriptionCreateFromH264ParameterSets(allocator: kCFAllocatorDefault,
                                                                                 parameterSetCount: 2,
                                                                                 parameterSetPointers: &parameterSetPointers,
                                                                                 parameterSetSizes: &parameterSetSizes,
                                                                                 nalUnitHeaderLength: 4,
                                                                                 extensions: nil,
                                                                                 formatDescriptionOut: &fmt)
                if status == noErr, let fmt = fmt {
                    self.formatDesc = fmt
                    print("Created format description")
                    createDecompressionSession()
                } else {
                    print("Failed to create format desc: \(status)")
                }
            }
        }
    }

    private func createDecompressionSession() {
        guard let fmt = formatDesc else { return }
        var callback = VTDecompressionOutputCallbackRecord(decompressionOutputCallback: decompressionOutputCallback, decompressionOutputRefCon: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()))
        var sessionOut: VTDecompressionSession?

        let decoderParameters = NSMutableDictionary()
        let destinationAttrs = NSMutableDictionary();
        destinationAttrs[kCVPixelBufferPixelFormatTypeKey] = NSNumber(value: kCVPixelFormatType_32BGRA)

        let status = VTDecompressionSessionCreate(allocator: kCFAllocatorDefault,
                                                  formatDescription: fmt,
                                                  decoderSpecification: nil,
                                                  imageBufferAttributes: destinationAttrs,
                                                  outputCallback: &callback,
                                                  decompressionSessionOut: &sessionOut)
        if status == noErr, let s = sessionOut {
            self.session = s
            print("Created decompression session")
        } else {
            print("Failed to create decompression session: \(status)")
        }
    }

    private func decode(nal: Data) {
        guard let fmt = formatDesc, let session = session else { return }

        // Convert Annex-B NAL to length-prefixed (AVCC) for CMSampleBuffer creation: prefix with 4-byte big-endian length
        var avcc = Data()
        var nalLen = UInt32(nal.count).bigEndian
        withUnsafeBytes(of: &nalLen) { avcc.append(contentsOf: $0) }
        avcc.append(nal)

        var block: CMBlockBuffer?
        let status = CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault,
                                                        memoryBlock: UnsafeMutableRawPointer(mutating: (avcc as NSData).bytes),
                                                        blockLength: avcc.count,
                                                        blockAllocator: kCFAllocatorNull,
                                                        customBlockSource: nil,
                                                        offsetToData: 0,
                                                        dataLength: avcc.count,
                                                        flags: 0,
                                                        blockBufferOut: &block)
        if status != kCMBlockBufferNoErr {
            print("CMBlockBufferCreateWithMemoryBlock failed: \(status)")
            return
        }

        var sampleBuffer: CMSampleBuffer?
        var sampleTiming = CMSampleTimingInfo(duration: CMTime.invalid, presentationTimeStamp: CMTime.invalid, decodeTimeStamp: CMTime.invalid)
        let sbStatus = CMSampleBufferCreateReady(allocator: kCFAllocatorDefault,
                                                 dataBuffer: block,
                                                 formatDescription: fmt,
                                                 sampleCount: 1,
                                                 sampleTimingEntryCount: 1,
                                                 sampleTimingArray: &sampleTiming,
                                                 sampleSizeEntryCount: 0,
                                                 sampleSizeArray: nil,
                                                 sampleBufferOut: &sampleBuffer)
        if sbStatus != noErr || sampleBuffer == nil {
            print("CMSampleBufferCreateReady failed: \(sbStatus)")
            return
        }

        let decodeFlags: VTDecodeFrameFlags = VTDecodeFrameFlags._EnableAsynchronousDecompression
        var infoFlags = VTDecodeInfoFlags()
        let decodeStatus = VTDecompressionSessionDecodeFrame(session,
                                                             sampleBuffer: sampleBuffer!,
                                                             flags: decodeFlags,
                                                             frameRefcon: nil,
                                                             infoFlagsOut: &infoFlags)
        if decodeStatus != noErr {
            print("VTDecompressionSessionDecodeFrame failed: \(decodeStatus)")
        }
    }
}

// MARK: - Decompression callback

private func decompressionOutputCallback(refCon: UnsafeMutableRawPointer?, sourceFrameRefCon: UnsafeMutableRawPointer?, status: OSStatus, infoFlags: VTDecodeInfoFlags, imageBuffer: CVImageBuffer?, presentationTimeStamp: CMTime, presentationDuration: CMTime) -> Void {
    guard status == noErr, let imageBuffer = imageBuffer, let ref = refCon else { return }
    let decoder: H264Decoder = Unmanaged<H264Decoder>.fromOpaque(ref).takeUnretainedValue()

    var sampleBuffer: CMSampleBuffer?
    var tim = CMSampleTimingInfo(duration: presentationDuration, presentationTimeStamp: presentationTimeStamp, decodeTimeStamp: CMTime.invalid)
    let createStatus = CMSampleBufferCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: imageBuffer, dataReady: true, makeDataReadyCallback: nil, refcon: nil, formatDescription: decoder.formatDesc!, sampleTiming: &tim, sampleBufferOut: &sampleBuffer)
    if createStatus == noErr, let sb = sampleBuffer {
        DispatchQueue.main.async {
            decoder.displayLayer.enqueue(sb)
        }
    }
}
