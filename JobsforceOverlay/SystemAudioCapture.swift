import ScreenCaptureKit
import AVFAudio
import CoreMedia
import Speech   // ← needed for SFSpeech* types

final class SystemAudioCapture: NSObject, SCStreamOutput {
    private var stream: SCStream?
    private let transcriber: LiveTranscriber

    private var converter: AVAudioConverter?
    // Speech handles multiple rates; 16k mono is a safe target
//    private let targetFormat = AVAudioFormat(commonFormat: .pcmFormatInt16,
//                                             sampleRate: 16_000,
//                                             channels: 1,
//                                             interleaved: false)!
    private let targetFormat = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                             sampleRate: 44_100,
                                             channels: 1,
                                             interleaved: false)!

    init(transcriber: LiveTranscriber) {
        self.transcriber = transcriber
        super.init()
    }

    func start() async throws {
        // Ask once for Speech permission (you can move this to a central place if you want)
        let status = await withCheckedContinuation { (cont: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0) }
        }
        guard status == .authorized else {
            throw NSError(domain: "Speech", code: 2, userInfo: [NSLocalizedDescriptionKey: "Speech not authorized"])
        }

        // Pick a display (main display preferred)
        let content = try await SCShareableContent.current
        let mainID = CGMainDisplayID()
        let display = content.displays.first(where: { $0.displayID == mainID }) ?? content.displays.first
        guard let display else { throw NSError(domain: "SC", code: 1, userInfo: [NSLocalizedDescriptionKey: "No display"]) }

        // Your SDK may not have the 'exceptingApps'/'excludingApplications' parameter. This works broadly:
        let filter = SCContentFilter(display: display, excludingWindows: [])

        // Configure stream for audio
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        
        // 🖼️ VIDEO: keep enabled internally but super tiny to suppress heavy logging
        // (SCKit may still push video frames; we just won't register a video output)
        config.width = 2
        config.height = 2
        config.showsCursor = false

        // You don't need to be the SCStreamDelegate; pass nil unless you want delegate callbacks
        let stream = SCStream(filter: filter, configuration: config, delegate: nil)
        self.stream = stream

        try transcriber.start()

        // Add as audio output
        try await stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: .main)
        try await stream.startCapture()    // triggers Screen Recording/System Audio permission if needed
        try await stream.addStreamOutput(DummyVideoDropper.shared, type: .screen, sampleHandlerQueue: .main)

        final class DummyVideoDropper: NSObject, SCStreamOutput {
            static let shared = DummyVideoDropper()
            func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
                // drop video frames on the floor
            }
        }
        print("SCStream started (audio only)")
    }

    func stop() async {
        try? await stream?.stopCapture()
        stream = nil
        transcriber.stop()
    }

    // MARK: - SCStreamOutput
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, CMSampleBufferIsValid(sampleBuffer) else { return }

        // DEBUG: confirm audio flow
        let framesIn = CMSampleBufferGetNumSamples(sampleBuffer)
        // if framesIn > 0 { print("System audio samples:", framesIn) }

        // Use the simple, robust copier
        guard let (srcBuffer, srcFormat) = sampleBuffer.makePCMBufferAndFormat() else { return }

        if converter == nil {
            converter = AVAudioConverter(from: srcFormat, to: targetFormat)
        }
        guard let converter else { return }

        // Prepare destination
        let ratio = targetFormat.sampleRate / srcFormat.sampleRate
        let dstCapacity = AVAudioFrameCount(Double(srcBuffer.frameLength) * ratio) + 1024
        guard let dstBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: dstCapacity) else { return }

        var error: NSError?
        let status = converter.convert(to: dstBuffer, error: &error) { _, outStatus in
            outStatus.pointee = .haveData
            return srcBuffer
        }

        if status == .haveData, error == nil, dstBuffer.frameLength > 0 {
            transcriber.append(dstBuffer, when: nil)
            // Optional: print RMS to confirm non-silence
            // print("RMS:", rms(dstBuffer))
        }
    }
}

// MARK: - CMSampleBuffer → AVAudioPCMBuffer
extension CMSampleBuffer {
    /// Returns an AVAudioPCMBuffer and its source AVAudioFormat, or nil if sample buffer isn't PCM.
    func makePCMBufferAndFormat() -> (AVAudioPCMBuffer, AVAudioFormat)? {
        guard
            let fmtDesc = self.formatDescription,
            let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(fmtDesc),
            let srcFormat = AVAudioFormat(streamDescription: asbd)
        else { return nil }

        let frames = AVAudioFrameCount(CMSampleBufferGetNumSamples(self))
        guard let dst = AVAudioPCMBuffer(pcmFormat: srcFormat, frameCapacity: frames) else { return nil }
        dst.frameLength = frames

        // ✅ Let CoreMedia copy PCM into our AVAudioPCMBuffer's AudioBufferList
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            self,
            at: 0,
            frameCount: Int32(frames),
            into: dst.mutableAudioBufferList
        )
        guard status == noErr else { return nil }

        return (dst, srcFormat)
    }
}


private func rms(_ buf: AVAudioPCMBuffer) -> Float {
    guard let ch = buf.floatChannelData?.pointee else { return 0 }
    let n = Int(buf.frameLength)
    var acc: Float = 0
    for i in 0..<n { acc += ch[i] * ch[i] }
    return sqrt(acc / Float(max(n, 1)))
}
