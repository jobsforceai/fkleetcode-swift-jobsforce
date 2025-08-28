import Foundation
import AVFoundation
import Speech
import ScreenCaptureKit
import AppKit


final class TranscriptionManager: NSObject {

  private let mic = LiveMicTranscriber()
  private let systemCapture = SCSystemAudioCapture()

  private let systemRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))

  private var systemReq: SFSpeechAudioBufferRecognitionRequest?
  private var systemTask: SFSpeechRecognitionTask?

  override init() {
    super.init()
    systemRecognizer?.delegate = self
  }

  func startAll() {
    mic.requestPermissions { [weak self] granted in
      guard let self else { return }
      guard granted else {
        self.post("Microphone/Speech permission denied.", final: true, src: "system")
        return
      }

      // MIC → Speech
      do {
        try self.mic.start { [weak self] text, isFinal in
          self?.post(text, final: isFinal, src: "mic")
        }
      } catch {
        self.post("Mic start error: \(error.localizedDescription)", final: true, src: "mic")
      }

      // SYSTEM AUDIO → Speech (NO preflight check here!)
      self.startSystemStreamToSpeech()
    }
  }

  func stopAll() {
    mic.stop()
    stopSystemStreamToSpeech()
  }

  // MARK: - System audio → Apple Speech

  private func startSystemStreamToSpeech() {
    guard systemRecognizer?.isAvailable == true else {
      post("Speech not available. Turn on Dictation (Keyboard → Dictation) and ensure “English (US)” is installed.", final: true, src: "system")
      return
    }

    let req = SFSpeechAudioBufferRecognitionRequest()
    req.shouldReportPartialResults = true
    req.requiresOnDeviceRecognition = false
    systemReq = req

    systemTask = systemRecognizer?.recognitionTask(with: req) { [weak self] result, error in
      guard let self else { return }
      if let r = result {
        self.post(r.bestTranscription.formattedString, final: r.isFinal, src: "system")
      }
      if error != nil || (result?.isFinal ?? false) {
        self.stopSystemRecognitionOnly()
      }
    }

    systemCapture.start(onBuffer: { [weak self] pcm, _ in
      guard let self, let req = self.systemReq else { return }
      req.append(pcm)
    }, onReady: {
      // started
    }, onError: { [weak self] err in
      guard let self else { return }
      let e = err as NSError

      // Show permission message ONLY for the true user-declined case
      var isUserDeclined = false
      if e.domain == "com.apple.screencapturekit.error" || e.domain == "com.apple.ScreenCaptureKit.SCStreamErrorDomain" {
        if #available(macOS 14.0, *), let sce = err as? SCStreamError {
          isUserDeclined = (sce.code == .userDeclined)
        } else if e.code == 1003 || e.code == -3801 {
          isUserDeclined = true
        }
      }

      if isUserDeclined {
        self.post("Screen Recording permission required. Enable it for **Xcode** (and your app), then quit & relaunch.", final: true, src: "system")
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
          NSWorkspace.shared.open(url)
        }
      } else {
        self.post("System audio error: \(e.domain)(\(e.code)) \(e.localizedDescription)", final: true, src: "system")
      }
    })
  }

  private func stopSystemRecognitionOnly() {
    systemReq?.endAudio()
    systemTask?.cancel()
    systemReq = nil
    systemTask = nil
  }

  private func stopSystemStreamToSpeech() {
    stopSystemRecognitionOnly()
    systemCapture.stop()
  }

  private func post(_ text: String, final: Bool, src: String) {
    DispatchQueue.main.async {
      NotificationCenter.default.post(
        name: .jfTranscript,
        object: ["text": text, "isFinal": final, "source": src]
      )
    }
  }
}

extension TranscriptionManager: SFSpeechRecognizerDelegate {
  func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool) {
    if available, systemReq == nil, systemTask == nil {
      startSystemStreamToSpeech()
    }
  }
}
