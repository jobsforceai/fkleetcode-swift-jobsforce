// THIS ONE IS NOT BEING USED RIGHT NOW
import SwiftUI
import Speech

struct DualTranscribeView: View {
    @StateObject private var mic = LiveTranscriber()
    @StateObject private var sys = LiveTranscriber()

    @State private var micCapture: MicCapture?
    @State private var sysCapture: SystemAudioCapture?

    @State private var speechAuth: SFSpeechRecognizerAuthorizationStatus = .notDetermined

    var body: some View {
        VStack(spacing: 16) {
            Text("Microphone").font(.headline)
            ScrollView { Text(mic.transcript).frame(maxWidth: .infinity, alignment: .leading) }
                .frame(height: 140).padding().background(.ultraThinMaterial).clipShape(RoundedRectangle(cornerRadius: 12))

            Text("System Audio").font(.headline)
            ScrollView { Text(sys.transcript).frame(maxWidth: .infinity, alignment: .leading) }
                .frame(height: 140).padding().background(.ultraThinMaterial).clipShape(RoundedRectangle(cornerRadius: 12))

            HStack {
                Button("Start Both") { Task { try? await startAll() } }
                Button("Stop Both")  { Task { await stopAll() } }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .task { await requestSpeechPermission() }
    }

    private func requestSpeechPermission() async {
        await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { status in
                self.speechAuth = status
                cont.resume()
            }
        }
    }

    private func startAll() async throws {
        guard speechAuth == .authorized else { return }

        // Use existing @StateObject instances:
        let mc = MicCapture(transcriber: mic)
        let sc = SystemAudioCapture(transcriber: sys)

        micCapture = mc
        sysCapture = sc

        try mc.start()
        try await sc.start()
    }

    private func stopAll() async {
        micCapture?.stop()
        await sysCapture?.stop()
        micCapture = nil
        sysCapture = nil
    }
}
