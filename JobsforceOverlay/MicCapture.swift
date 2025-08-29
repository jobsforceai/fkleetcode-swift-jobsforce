import AVFAudio

final class MicCapture {
    private let engine = AVAudioEngine()
    private let transcriber: LiveTranscriber

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
        let format = input.outputFormat(forBus: 0)

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, when in
            self?.transcriber.append(buffer, when: when)
        }

        try transcriber.start()
        try engine.start()
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        transcriber.stop()
    }
}
