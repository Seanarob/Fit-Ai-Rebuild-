import AVFoundation
import Foundation
import Speech

enum AudioLevelMeter {
    static func normalizedLevel(from buffer: AVAudioPCMBuffer) -> Float {
        guard let rms = rms(from: buffer), rms > 0 else { return 0 }
        
        let db = 20 * log10f(rms)
        let clamped = max(-55, min(-5, db))
        let linear = (clamped + 55) / 50
        let curved = powf(linear, 1.6)
        return max(0, min(1, curved))
    }
    
    private static func rms(from buffer: AVAudioPCMBuffer) -> Float? {
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return nil }
        
        let channelCount = max(1, Int(buffer.format.channelCount))
        let isInterleaved = buffer.format.isInterleaved
        
        switch buffer.format.commonFormat {
        case .pcmFormatFloat32:
            if !isInterleaved, let channels = buffer.floatChannelData {
                var sum: Float = 0
                for ch in 0..<channelCount {
                    let data = channels[ch]
                    for i in 0..<frameLength {
                        let s = data[i]
                        sum += s * s
                    }
                }
                return sqrt(sum / Float(frameLength * channelCount))
            }
            
            // Interleaved float32
            let audioBuffer = buffer.audioBufferList.pointee.mBuffers
            guard let mData = audioBuffer.mData else { return nil }
            let sampleCount = min(
                Int(audioBuffer.mDataByteSize) / MemoryLayout<Float>.size,
                frameLength * channelCount
            )
            guard sampleCount > 0 else { return nil }
            let samples = mData.assumingMemoryBound(to: Float.self)
            var sum: Float = 0
            for i in 0..<sampleCount {
                let s = samples[i]
                sum += s * s
            }
            return sqrt(sum / Float(sampleCount))
            
        case .pcmFormatInt16:
            if !isInterleaved, let channels = buffer.int16ChannelData {
                var sum: Float = 0
                for ch in 0..<channelCount {
                    let data = channels[ch]
                    for i in 0..<frameLength {
                        let s = Float(data[i]) / Float(Int16.max)
                        sum += s * s
                    }
                }
                return sqrt(sum / Float(frameLength * channelCount))
            }
            
            // Interleaved int16
            let audioBuffer = buffer.audioBufferList.pointee.mBuffers
            guard let mData = audioBuffer.mData else { return nil }
            let sampleCount = min(
                Int(audioBuffer.mDataByteSize) / MemoryLayout<Int16>.size,
                frameLength * channelCount
            )
            guard sampleCount > 0 else { return nil }
            let samples = mData.assumingMemoryBound(to: Int16.self)
            var sum: Float = 0
            for i in 0..<sampleCount {
                let s = Float(samples[i]) / Float(Int16.max)
                sum += s * s
            }
            return sqrt(sum / Float(sampleCount))
            
        default:
            return nil
        }
    }
}

final class SpeechTranscriber: NSObject {
    struct Word: Hashable, Identifiable {
        var id: String { "\(substring)-\(timestamp)-\(duration)" }
        var substring: String
        var confidence: Float
        var timestamp: TimeInterval
        var duration: TimeInterval
    }
    
    struct FinalResult: Hashable {
        var transcript: String
        var words: [Word]
    }
    
    enum LiveUpdate: Hashable {
        case transcript(String)
        case audioLevel(Float)
        case didDetectSpeech
    }
    
    enum TranscriberError: LocalizedError, Equatable {
        case recognizerUnavailable
        case notAuthorized
        case audioEngineFailure
        
        var errorDescription: String? {
            switch self {
            case .recognizerUnavailable:
                return "Speech recognition isn't available on this device."
            case .notAuthorized:
                return "Speech recognition permission is not enabled."
            case .audioEngineFailure:
                return "We couldn't start the microphone. Please try again."
            }
        }
    }
    
    private let audioSessionManager: AudioSessionManager
    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var liveContinuation: AsyncStream<LiveUpdate>.Continuation?
    
    private var lastTranscript: String = ""
    private var lastWords: [Word] = []
    private var didDetectSpeechOnce = false
    private var interruptionObserver: NSObjectProtocol?
    private var routeObserver: NSObjectProtocol?
    
    init(audioSessionManager: AudioSessionManager = AudioSessionManager()) {
        self.audioSessionManager = audioSessionManager
    }
    
    static func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }
    
    static func requestMicrophoneAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { allowed in
                continuation.resume(returning: allowed)
            }
        }
    }
    
    func start(locale: Locale = .current) throws -> AsyncStream<LiveUpdate> {
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            throw TranscriberError.notAuthorized
        }
        
        guard let recognizer = SFSpeechRecognizer(locale: locale) else {
            throw TranscriberError.recognizerUnavailable
        }
        guard recognizer.isAvailable else {
            throw TranscriberError.recognizerUnavailable
        }
        
        stopIfNeeded()
        lastTranscript = ""
        lastWords = []
        didDetectSpeechOnce = false
        
        try audioSessionManager.activateForRecording()
        
        let engine = AVAudioEngine()
        audioEngine = engine
        
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if #available(iOS 16.0, *) {
            request.addsPunctuation = true
        }
        recognitionRequest = request
        
        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        let stream = AsyncStream<LiveUpdate> { continuation in
            self.liveContinuation = continuation
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.stopIfNeeded()
                }
            }
        }
        
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            guard let self else { return }
            self.recognitionRequest?.append(buffer)
            self.liveContinuation?.yield(.audioLevel(AudioLevelMeter.normalizedLevel(from: buffer)))
        }
        
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result {
                let transcript = result.bestTranscription.formattedString
                self.lastTranscript = transcript
                self.lastWords = result.bestTranscription.segments.map { seg in
                    Word(
                        substring: seg.substring,
                        confidence: seg.confidence,
                        timestamp: seg.timestamp,
                        duration: seg.duration
                    )
                }
                if !self.didDetectSpeechOnce, !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    self.didDetectSpeechOnce = true
                    self.liveContinuation?.yield(.didDetectSpeech)
                }
                self.liveContinuation?.yield(.transcript(transcript))
            }
            if error != nil {
                // End-of-stream is handled by stop(); no need to surface noisy Speech errors.
            }
        }
        
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            guard let userInfo = notification.userInfo,
                  let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
            if type == .began {
                Task { @MainActor [weak self] in
                    self?.stopIfNeeded()
                }
            }
        }
        
        routeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            guard let userInfo = notification.userInfo,
                  let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else { return }

            switch reason {
            case .oldDeviceUnavailable, .noSuitableRouteForCategory:
                Task { @MainActor [weak self] in
                    self?.stopIfNeeded()
                }
            default:
                break
            }
        }
        
        do {
            engine.prepare()
            try engine.start()
        } catch {
            stopIfNeeded()
            throw TranscriberError.audioEngineFailure
        }
        
        return stream
    }
    
    func stop() -> FinalResult {
        let final = FinalResult(
            transcript: lastTranscript.trimmingCharacters(in: .whitespacesAndNewlines),
            words: lastWords
        )
        stopIfNeeded()
        return final
    }
    
    func stopAndFinalize(finalizationDelayNs: UInt64 = 300_000_000) async -> FinalResult {
        // Give Speech a moment to deliver a final result after endAudio; otherwise we can
        // frequently end up with an empty transcript if the user taps Done quickly.
        recognitionRequest?.endAudio()
        recognitionTask?.finish()
        stopAudioEngineIfNeeded()
        
        try? await Task.sleep(nanoseconds: finalizationDelayNs)
        
        let final = FinalResult(
            transcript: lastTranscript.trimmingCharacters(in: .whitespacesAndNewlines),
            words: lastWords
        )
        stopIfNeeded()
        return final
    }
    
    func stopIfNeeded() {
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        
        recognitionTask?.cancel()
        recognitionTask = nil
        
        stopAudioEngineIfNeeded()
        
        liveContinuation?.finish()
        liveContinuation = nil
        
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
            self.interruptionObserver = nil
        }
        if let routeObserver {
            NotificationCenter.default.removeObserver(routeObserver)
            self.routeObserver = nil
        }
        
        audioSessionManager.deactivate()
    }
    
    private func stopAudioEngineIfNeeded() {
        if let engine = audioEngine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        audioEngine = nil
    }
}
