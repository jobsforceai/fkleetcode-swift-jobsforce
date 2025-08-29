import Foundation
import Speech
import Combine   // ← add this

final class TranscriptionDirector: ObservableObject {
    @Published var micText: String = ""
    @Published var systemText: String = ""
    @Published var isRunning = false

    private var micTrans = LiveTranscriber()
    private var sysTrans = LiveTranscriber()

    private var mic: MicCapture?
    private var sys: SystemAudioCapture?

    init() {
        // bubble updates up on the main thread
        micTrans.$transcript
            .receive(on: DispatchQueue.main)   // ← fix
            .assign(to: &$micText)

        sysTrans.$transcript
            .receive(on: DispatchQueue.main)   // ← fix
            .assign(to: &$systemText)
    }

    func requestSpeechAuth(completion: @escaping (Bool)->Void) {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async { completion(status == .authorized) }
        }
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true

        mic = MicCapture(transcriber: micTrans)
        sys = SystemAudioCapture(transcriber: sysTrans)

        do {
            try mic?.start()
        } catch {
            print("Mic start error:", error)
        }

        Task {
            do { try await sys?.start() }
            catch { print("System start error:", error) }
        }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        mic?.stop()
        mic = nil
        Task { await sys?.stop() }
        sys = nil
    }
}
