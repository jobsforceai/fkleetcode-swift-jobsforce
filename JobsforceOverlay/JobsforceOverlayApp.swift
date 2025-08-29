import SwiftUI
import AppKit   // ← add this

@main
struct JobsforceOverlayApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self)
  var appDelegate: AppDelegate    // ← add explicit type to disambiguate

  var body: some Scene {
    Settings { EmptyView() }
  }
}

//Useful commands:
//tccutil reset ScreenCapture
//tccutil reset Microphone
//tccutil reset SpeechRecognition
