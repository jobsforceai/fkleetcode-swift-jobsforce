import Speech
import AVFAudio

final class LiveTranscriber: NSObject, ObservableObject {
    @Published var transcript = ""
    @Published var isRunning = false
    
    // NEW: simple callbacks for logging
        var onPartial: ((String) -> Void)?
        var onFinal:   ((String) -> Void)?

    private let recognizer: SFSpeechRecognizer
    private var task: SFSpeechRecognitionTask?
    private var request: SFSpeechAudioBufferRecognitionRequest?

    init(locale: Locale = Locale(identifier: "en-US")) { // stable locale helps during debugging
        self.recognizer = SFSpeechRecognizer(locale: locale)!
        super.init()
    }

    func start() throws {
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            throw NSError(domain: "Speech", code: 1, userInfo: [NSLocalizedDescriptionKey: "Speech not authorized"])
        }
        guard recognizer.isAvailable else {
                    throw NSError(domain: "Speech", code: 2, userInfo: [NSLocalizedDescriptionKey: "Speech recognizer not available"])
                }

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.requiresOnDeviceRecognition = false   // force cloud to avoid kAFAssistantErrorDomain 1101
        req.taskHint = .dictation                  // better for continuous speech
        self.request = req
        self.isRunning = true

        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            guard let self else { return }
            if let result = result {
                let text = result.bestTranscription.formattedString
                self.transcript = text
//                if result.isFinal {
//                    print("FINAL>", text)
//                    self.onFinal?(text)
//                    self.stop()
//                } else {
//                    print("PARTIAL>", text)
//                    self.onPartial?(text)
//                }
            } else if let err = error as NSError? {
                // helpful debug print while you iterate
                print("Speech task error:", err.domain, err.code, err.localizedDescription)
                self.stop()
            }
        }
    }

    func append(_ buffer: AVAudioPCMBuffer, when: AVAudioTime?) {
        request?.append(buffer)
    }

    func stop() {
        isRunning = false
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
    }
    
    func requestSpeechAuth(_ completion: @escaping (Bool) -> Void) {
        let status = SFSpeechRecognizer.authorizationStatus()
        if status == .authorized { completion(true); return }
        SFSpeechRecognizer.requestAuthorization { newStatus in
            DispatchQueue.main.async { completion(newStatus == .authorized) }
        }
    }
}
