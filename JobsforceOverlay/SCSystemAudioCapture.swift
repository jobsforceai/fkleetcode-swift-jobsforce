import Foundation
import ScreenCaptureKit
import AVFoundation
import CoreMedia
import AudioToolbox

/// Captures app/display audio via ScreenCaptureKit and emits AVAudioPCMBuffer.
/// Works on macOS 12.3+ (Monterey) and newer.
final class SCSystemAudioCapture: NSObject, SCStreamOutput {

  // MARK: - Public API

  /// Start capturing audio from the main display (swap to window/app if you prefer).
  /// - Parameters:
  ///   - onBuffer: called on a background queue with PCM buffers + their PTS.
  ///   - onReady:  called when capture starts.
  ///   - onError:  called if start fails (pass this up; don't assume it's permission).
  func start(onBuffer: @escaping (AVAudioPCMBuffer, CMTime) -> Void,
             onReady: @escaping () -> Void,
             onError: @escaping (Error) -> Void) {
    self.bufferHandler = onBuffer

    Task { [weak self] in
      do {
        guard let self else { return }

        let content = try await SCShareableContent.current

        // Pick the main display (or choose a window/app from `content`).
        let display = content.displays.first(where: { $0.displayID == CGMainDisplayID() })
                   ?? content.displays.first
        guard let targetDisplay = display else {
          onError(NSError(domain: "SCSystemAudioCapture",
                          code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "No display found"]))
          return
        }

        let filter = SCContentFilter(
          display: targetDisplay,
          excludingApplications: [],
          exceptingWindows: []
        )

        let cfg = SCStreamConfiguration()
        cfg.capturesAudio = true
        cfg.excludesCurrentProcessAudio = true  // don’t capture your app’s audio

        let stream = SCStream(filter: filter, configuration: cfg, delegate: nil)
        self.stream = stream

        // Receive audio samples on our queue.
        try stream.addStreamOutput(self,
                                   type: .audio,
                                   sampleHandlerQueue: self.audioQueue)

        // Start capture (async on new SDKs; completion on older).
        if #available(macOS 14.0, *) {
          try await stream.startCapture()
          onReady()
        } else {
            {stream.startCapture { error in
                if let e = error { onError(e) } else { onReady() }
              }}()
        }
      } catch {
        onError(error)
      }
    }
  }

  func stop() {
    guard let stream else { return }
    if #available(macOS 14.0, *) {
      Task { try? await stream.stopCapture() }
    } else {
      stream.stopCapture { _ in }
    }
    self.stream = nil
  }

  // MARK: - SCStreamOutput

  func stream(_ stream: SCStream,
              didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
              of type: SCStreamOutputType) {
    guard type == .audio else { return }
    guard let pcm = Self.makePCMBuffer(from: sampleBuffer) else { return }
    bufferHandler?(pcm, CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
  }

  func stream(_ stream: SCStream, didStopWithError error: Error) {
    // Optional: forward up if you want
    print("SCStream stopped with error:", error.localizedDescription)
  }

  // MARK: - Internals

  private var stream: SCStream?
  private let audioQueue = DispatchQueue(label: "jf.sc.audio")
  private var bufferHandler: ((AVAudioPCMBuffer, CMTime) -> Void)?

  /// Compute bytes needed for an AudioBufferList with `buffers` entries.
  @inline(__always)
  private static func audioBufferListSize(maximumBuffers buffers: Int) -> Int {
    MemoryLayout<AudioBufferList>.size + max(0, buffers - 1) * MemoryLayout<AudioBuffer>.size
  }

  /// Build an AVAudioPCMBuffer from a CMSampleBuffer (interleaved or non-interleaved).
  private static func makePCMBuffer(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
    guard let fmtDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
          let asbdPtr = CMAudioFormatDescriptionGetStreamBasicDescription(fmtDesc) else { return nil }
    var asbd = asbdPtr.pointee
    guard let format = AVAudioFormat(streamDescription: &asbd) else { return nil }

    let frames = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
    guard let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
    pcm.frameLength = frames

    // Allocate raw AudioBufferList.
    let channelCount = max(1, Int(format.channelCount))
    let ablBytes = Self.audioBufferListSize(maximumBuffers: channelCount)
    let ablPtr = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: 1)
    ablPtr.initialize(to: AudioBufferList(mNumberBuffers: 0, mBuffers: AudioBuffer()))
    defer { ablPtr.deinitialize(count: 1); free(ablPtr) }

    // Fill from CMSampleBuffer.
    var blockBuffer: CMBlockBuffer?
    var sizeNeeded = ablBytes
    let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
      sampleBuffer,
      bufferListSizeNeededOut: &sizeNeeded,
      bufferListOut: ablPtr,
      bufferListSize: ablBytes,
      blockBufferAllocator: kCFAllocatorDefault,
      blockBufferMemoryAllocator: kCFAllocatorDefault,
      flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
      blockBufferOut: &blockBuffer
    )
    guard status == noErr else { return nil }

    let list = UnsafeMutableAudioBufferListPointer(ablPtr)

    // Copy into AVAudioPCMBuffer storage.
    if format.isInterleaved {
      guard let dst = pcm.floatChannelData,
            list.count > 0,
            let src = list[0].mData else { return nil }

      // Assume Float32 interleaved; convert if needed for other formats.
      let channels = channelCount
      let bytesPerFrame = Int(asbd.mBytesPerFrame)
      let totalBytes = Int(frames) * bytesPerFrame
      let totalSamples = totalBytes / MemoryLayout<Float>.size
      let srcFloats = src.bindMemory(to: Float.self, capacity: totalSamples)

      for f in 0..<Int(frames) {
        for ch in 0..<channels {
          dst[ch][f] = srcFloats[f * channels + ch]
        }
      }
    } else {
      guard let dst = pcm.floatChannelData else { return nil }
      for ch in 0..<min(channelCount, list.count) {
        if let src = list[ch].mData {
          memcpy(dst[ch], src, Int(list[ch].mDataByteSize))
        }
      }
    }

    return pcm
  }
}
