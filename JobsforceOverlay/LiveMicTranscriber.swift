import AVFoundation
import Speech

final class LiveMicTranscriber {
  private let engine = AVAudioEngine()
  private let recognizer = SFSpeechRecognizer()
  private var request: SFSpeechAudioBufferRecognitionRequest?
  private var task: SFSpeechRecognitionTask?

  /// Call once to request Speech + Microphone permissions.
  func requestPermissions(completion: @escaping (Bool) -> Void) {
    SFSpeechRecognizer.requestAuthorization { status in
      guard status == .authorized else { DispatchQueue.main.async { completion(false) }; return }
      AVCaptureDevice.requestAccess(for: .audio) { granted in
        DispatchQueue.main.async { completion(granted) }
      }
    }
  }

  /// Start live transcription from default mic on macOS.
  func start(onText: @escaping (_ text: String, _ isFinal: Bool) -> Void) throws {
    // Build recognition request
    let req = SFSpeechAudioBufferRecognitionRequest()
    req.shouldReportPartialResults = true
    self.request = req

    // Wire AVAudioEngine (no AVAudioSession on macOS)
    let input = engine.inputNode
    let format = input.outputFormat(forBus: 0)

    // In case of restart
    input.removeTap(onBus: 0)

    input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
      self?.request?.append(buffer)
    }

    engine.prepare()
    try engine.start()

    // Start recognition
    task = recognizer?.recognitionTask(with: req) { [weak self] result, error in
      if let r = result {
        onText(r.bestTranscription.formattedString, r.isFinal)
      }
      if error != nil || (result?.isFinal ?? false) {
        self?.stop()
      }
    }
  }

  func stop() {
    engine.inputNode.removeTap(onBus: 0)
    engine.stop()
    request?.endAudio()
    task?.cancel()
    request = nil
    task = nil
  }
}
