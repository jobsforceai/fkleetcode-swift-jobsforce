import AVFAudio

final class MicCapture {
    private let engine = AVAudioEngine()
    private let transcriber: LiveTranscriber
    
    // ✅ Speech-friendly target format: mono, Float32, 16 kHz
        private let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                                 sampleRate: 16_000,
                                                 channels: 1,
                                                 interleaved: false)!
    private var converter: AVAudioConverter?

    init(transcriber: LiveTranscriber) {
        self.transcriber = transcriber
    }

    func start() throws {
        // iOS/tvOS only: configure AVAudioSession. Not available on macOS.
        #if !os(macOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
        try session.setActive(true, options: [])
        #endif

        let input = engine.inputNode
        let srcFormat = input.outputFormat(forBus: 0)
        
        // Build converter once (source mic format -> 16k mono float32)
        if converter == nil || converter?.inputFormat != srcFormat || converter?.outputFormat != targetFormat {
            converter = AVAudioConverter(from: srcFormat, to: targetFormat)
        }
        guard let converter else {
            throw NSError(domain: "Mic", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create AVAudioConverter"])
        }

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 2048, format: srcFormat) { [weak self] srcBuffer, when in
            guard let self else { return }
            
            // Compute a reasonable destination capacity (up/downsample)
            let ratio = self.targetFormat.sampleRate / srcBuffer.format.sampleRate
            let dstCapacity = AVAudioFrameCount(Double(srcBuffer.frameLength) * ratio) + 1024
            guard let dstBuffer = AVAudioPCMBuffer(pcmFormat: self.targetFormat, frameCapacity: dstCapacity) else { return }

            var consumed = false
            var convError: NSError?
            let status = converter.convert(to: dstBuffer, error: &convError) { _, outStatus in
                if consumed {
                    outStatus.pointee = .endOfStream
                    return nil
                }
                consumed = true
                outStatus.pointee = .haveData
                return srcBuffer
            }

            if status == .haveData, convError == nil, dstBuffer.frameLength > 0 {
                self.transcriber.append(dstBuffer, when: when)
            }
        }

        // 🔁 Order: start engine first, then recognizer (keeps Speech from timing out waiting for audio)
        try engine.start()
        try transcriber.start()
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        transcriber.stop()
    }
}
