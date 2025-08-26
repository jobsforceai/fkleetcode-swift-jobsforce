import Foundation
import ScreenCaptureKit
import AVFoundation
import CoreImage
import AppKit

/// Minimal one-frame screen capturer using ScreenCaptureKit.
final class SingleFrameCapture: NSObject, SCStreamOutput {
  private var stream: SCStream?
  private var completion: ((URL?) -> Void)?
  private let ci = CIContext()

  func captureFirstFrame(from display: SCDisplay, completion: @escaping (URL?) -> Void) {
    self.completion = completion

    let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
    let config = SCStreamConfiguration()
    config.capturesAudio = false
    // (width/height can be left at 0 to let SC choose; works fine for a still)

    let stream = SCStream(filter: filter, configuration: config, delegate: nil)
    self.stream = stream

    do {
      try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: DispatchQueue(label: "jf.shot"))
      try stream.startCapture()
    } catch {
      finish(with: nil)
    }
  }

  func stream(_ stream: SCStream, didOutputSampleBuffer sb: CMSampleBuffer, of type: SCStreamOutputType) {
    guard type == .screen, let pb = sb.imageBuffer else { return }
    let ciImage = CIImage(cvImageBuffer: pb)
    guard let cg = ci.createCGImage(ciImage, from: ciImage.extent) else { return }
    let rep = NSBitmapImageRep(cgImage: cg)
    guard let data = rep.representation(using: .png, properties: [:]) else { return }
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("jf-shot-\(Int(Date().timeIntervalSince1970)).png")
    do {
      try data.write(to: url)
      // Stop capture ASAP after first frame
      try? stream.stopCapture()
      finish(with: url)
    } catch {
      finish(with: nil)
    }
  }

  func stream(_ stream: SCStream, didStopWithError error: Error) {
    finish(with: nil)
  }

  private func finish(with url: URL?) {
    DispatchQueue.main.async {
      self.completion?(url)
      self.completion = nil
      self.stream = nil
    }
  }
}
