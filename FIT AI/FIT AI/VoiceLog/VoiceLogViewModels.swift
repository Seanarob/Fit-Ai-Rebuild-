import Foundation
import Combine
import Speech
import SwiftUI

enum VoiceLogRetryAction: Equatable {
    case restartListening
    case retryAnalyze
    case retryReprice
    case retryLog
}

enum VoiceLogFlowState: Equatable {
    case idle
    case listening(transcript: String)
    case analyzing(transcript: String)
    case review(payload: VoiceMealAnalyzeResponse)
    case error(message: String, retryAction: VoiceLogRetryAction)
}

enum VoiceLogAnalyticsEvent: String {
    case voiceLogOpened = "voice_log_opened"
    case transcriptDone = "voice_log_transcript_done"
    case analyzeSuccess = "voice_log_analyze_success"
    case editItem = "voice_log_edit_item"
    case logged = "voice_log_logged"
}

@MainActor
final class VoiceLogFlowViewModel: ObservableObject {
    enum PermissionState: Equatable {
        case unknown
        case authorized
        case denied
    }
    
    @Published var flowState: VoiceLogFlowState = .idle
    @Published var transcript: String = ""
    @Published var audioLevel: Float = 0
    @Published var showTapDoneHint: Bool = false
    @Published var permissionState: PermissionState = .unknown
    @Published var isSubmitting: Bool = false
    @Published var inlineErrorMessage: String?
    
    let userId: String
    let mealType: MealType
    let logDate: Date
    
    private let apiClient: MealAPIClientProtocol
    private let transcriber: SpeechTranscriber
    private var liveTask: Task<Void, Never>?
    private var hintTask: Task<Void, Never>?
    
    private var lastFinalTranscript: String?
    private var lastPayload: VoiceMealAnalyzeResponse?
    private var lastAnalyzeContext: VoiceMealContext?
    
    var onLogged: (() -> Void)?
    var trackEvent: (VoiceLogAnalyticsEvent) -> Void = { _ in }
    
    private var didTrackOpen = false
    
    private static let logDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
    
    init(
        userId: String,
        mealType: MealType,
        logDate: Date,
        apiClient: MealAPIClientProtocol,
        transcriber: SpeechTranscriber? = nil
    ) {
        self.userId = userId
        self.mealType = mealType
        self.logDate = logDate
        self.apiClient = apiClient
        self.transcriber = transcriber ?? SpeechTranscriber()
    }
    
    func requestPermissionsIfNeeded() async {
        if permissionState != .unknown { return }
        
        let speechStatus = await SpeechTranscriber.requestSpeechAuthorization()
        let micAllowed = await SpeechTranscriber.requestMicrophoneAuthorization()
        
        if speechStatus == .authorized, micAllowed {
            permissionState = .authorized
        } else {
            permissionState = .denied
        }
    }
    
    func startListening() async {
        if !didTrackOpen {
            didTrackOpen = true
            trackEvent(.voiceLogOpened)
        }
        
        inlineErrorMessage = nil
        showTapDoneHint = false
        audioLevel = 0
        
        await requestPermissionsIfNeeded()
        guard permissionState == .authorized else {
            flowState = .error(message: "Enable Microphone + Speech Recognition in Settings.", retryAction: .restartListening)
            return
        }
        
        Haptics.light()
        flowState = .listening(transcript: "")
        transcript = ""
        
        liveTask?.cancel()
        hintTask?.cancel()
        
        do {
            let stream = try transcriber.start()
            liveTask = Task { [weak self] in
                guard let self else { return }
                for await update in stream {
                    switch update {
                    case .audioLevel(let level):
                        self.audioLevel = level
                    case .transcript(let text):
                        self.transcript = text
                        self.flowState = .listening(transcript: text)
                        self.resetTapDoneHintTimer()
                    case .didDetectSpeech:
                        self.resetTapDoneHintTimer()
                    }
                }
            }
        } catch {
            flowState = .error(message: (error as? LocalizedError)?.errorDescription ?? "Couldn't start listening.", retryAction: .restartListening)
        }
    }
    
    func cancelListening() {
        transcriber.stopIfNeeded()
        liveTask?.cancel()
        hintTask?.cancel()
        flowState = .idle
    }
    
    func doneListeningAndAnalyze() async {
        Haptics.light()
        trackEvent(.transcriptDone)
        showTapDoneHint = false
        hintTask?.cancel()
        
        let result = await transcriber.stopAndFinalize()
        liveTask?.cancel()
        
        let final = result.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !final.isEmpty else {
            inlineErrorMessage = VoiceLogAPIError.noSpeechDetected.localizedDescription
            try? await Task.sleep(nanoseconds: 900_000_000)
            await startListening()
            return
        }
        
        let wordCount = final.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
        guard wordCount >= 3 else {
            inlineErrorMessage = VoiceLogAPIError.shortTranscript.localizedDescription
            try? await Task.sleep(nanoseconds: 900_000_000)
            await startListening()
            return
        }
        
        lastFinalTranscript = final
        flowState = .analyzing(transcript: final)
        await analyzeCurrentTranscript()
    }
    
    func analyzeCurrentTranscript() async {
        guard let transcript = lastFinalTranscript ?? currentTranscriptForAnalyze else {
            flowState = .error(message: "Nothing to analyze.", retryAction: .restartListening)
            return
        }
        
        let request = VoiceMealAnalyzeRequest(
            transcript: transcript,
            locale: Locale.current.identifier,
            timezone: TimeZone.current.identifier,
            timestamp: ISO8601DateFormatter().string(from: Date()),
            userId: userId,
            context: VoiceMealContext(
                mealType: .init(from: mealType),
                dietPrefs: nil,
                defaultUnits: "us"
            )
        )
        lastAnalyzeContext = request.context
        
        do {
            let payload = try await apiClient.analyzeVoiceMeal(request)
            lastPayload = payload
            trackEvent(.analyzeSuccess)
            flowState = .review(payload: payload)
        } catch {
            flowState = .error(message: (error as? LocalizedError)?.errorDescription ?? "Couldn't analyze. Try again.", retryAction: .retryAnalyze)
        }
    }
    
    func retry(from action: VoiceLogRetryAction) async {
        switch action {
        case .restartListening:
            await startListening()
        case .retryAnalyze:
            flowState = .analyzing(transcript: lastFinalTranscript ?? transcript)
            await analyzeCurrentTranscript()
        case .retryReprice:
            await repriceIfPossible()
        case .retryLog:
            await logMeal()
        }
    }
    
    func deleteItem(id: String) {
        guard case .review(let payload) = flowState else { return }
        let items = payload.items.filter { $0.id != id }
        let totals = items.reduce(VoiceMealTotals.zero) { partial, item in
            VoiceMealTotals(
                calories: partial.calories + item.macros.calories,
                proteinG: partial.proteinG + item.macros.proteinG,
                carbsG: partial.carbsG + item.macros.carbsG,
                fatG: partial.fatG + item.macros.fatG
            )
        }
        flowState = .review(payload: VoiceMealAnalyzeResponse(
            transcriptOriginal: payload.transcriptOriginal,
            assumptions: payload.assumptions,
            totals: totals,
            items: items,
            questionsNeeded: payload.questionsNeeded
        ))
    }
    
    func applyEditedItem(_ updatedItem: VoiceMealItem) async {
        trackEvent(.editItem)
        guard case .review(let payload) = flowState else { return }
        var items = payload.items
        guard let idx = items.firstIndex(where: { $0.id == updatedItem.id }) else { return }
        
        let old = items[idx]
        var optimistic = updatedItem
        if old.unit == updatedItem.unit, old.qty > 0, updatedItem.qty > 0 {
            let scale = updatedItem.qty / old.qty
            optimistic.macros = VoiceMealItemMacros(
                calories: old.macros.calories * scale,
                proteinG: old.macros.proteinG * scale,
                carbsG: old.macros.carbsG * scale,
                fatG: old.macros.fatG * scale
            )
        }
        
        items[idx] = optimistic
        
        let optimisticTotals = items.reduce(VoiceMealTotals.zero) { partial, item in
            VoiceMealTotals(
                calories: partial.calories + item.macros.calories,
                proteinG: partial.proteinG + item.macros.proteinG,
                carbsG: partial.carbsG + item.macros.carbsG,
                fatG: partial.fatG + item.macros.fatG
            )
        }
        
        flowState = .review(payload: VoiceMealAnalyzeResponse(
            transcriptOriginal: payload.transcriptOriginal,
            assumptions: payload.assumptions,
            totals: optimisticTotals,
            items: items,
            questionsNeeded: payload.questionsNeeded
        ))
        
        await repriceIfPossible()
    }
    
    func repriceIfPossible() async {
        guard case .review(let payload) = flowState else { return }
        do {
            let request = VoiceMealRepriceRequest(
                locale: Locale.current.identifier,
                timezone: TimeZone.current.identifier,
                timestamp: ISO8601DateFormatter().string(from: Date()),
                userId: userId,
                items: payload.items
            )
            let repriced = try await apiClient.repriceVoiceMeal(request)
            lastPayload = repriced
            flowState = .review(payload: repriced)
        } catch {
            flowState = .error(message: (error as? LocalizedError)?.errorDescription ?? "Couldn't update macros. Try again.", retryAction: .retryReprice)
        }
    }
    
    func reanalyze() async {
        guard case .review(let payload) = flowState else { return }
        lastFinalTranscript = payload.transcriptOriginal
        flowState = .analyzing(transcript: payload.transcriptOriginal)
        await analyzeCurrentTranscript()
    }
    
    func logMeal() async {
        guard case .review(let payload) = flowState else { return }
        guard !isSubmitting else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        
        do {
            let req = VoiceMealLogRequest(
                transcriptOriginal: payload.transcriptOriginal,
                items: payload.items,
                totals: payload.totals,
                timestamp: Self.logDateFormatter.string(from: logDate),
                mealType: .init(from: mealType),
                userId: userId
            )
            let res = try await apiClient.logMeal(req)
            if res.success {
                trackEvent(.logged)
                onLogged?()
            } else {
                flowState = .error(message: "Couldn't log meal. Try again.", retryAction: .retryLog)
            }
        } catch {
            flowState = .error(message: (error as? LocalizedError)?.errorDescription ?? "Couldn't log meal. Try again.", retryAction: .retryLog)
        }
    }
    
    private var currentTranscriptForAnalyze: String? {
        switch flowState {
        case .analyzing(let t): return t
        case .listening(let t): return t
        default: return nil
        }
    }
    
    private func resetTapDoneHintTimer() {
        showTapDoneHint = false
        hintTask?.cancel()
        hintTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_700_000_000)
            guard let self else { return }
            self.showTapDoneHint = true
        }
    }
}
