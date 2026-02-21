import Combine
import AVFoundation
import Foundation
import Speech
import SwiftUI
import UIKit

struct CoachChatView: View {
    let userId: String
    let showsCloseButton: Bool
    let onClose: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var guidedTour: GuidedTourCoordinator
    @StateObject private var viewModel: CoachChatViewModel
    @State private var draftMessage = ""
    @State private var showingThreads = false
    @FocusState private var isInputFocused: Bool
    @StateObject private var dictation = CoachDictationController()
    private let starterPrompts = [
        "Build me a 45-min workout for today.",
        "What should I focus on this week?",
        "How do I hit my protein target?",
        "Give me a quick warm-up routine."
    ]

    init(userId: String, showsCloseButton: Bool = true, onClose: (() -> Void)? = nil) {
        self.userId = userId
        self.showsCloseButton = showsCloseButton
        self.onClose = onClose
        _viewModel = StateObject(wrappedValue: CoachChatViewModel(userId: userId))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                FitTheme.backgroundGradient
                    .ignoresSafeArea()

                VStack(spacing: 12) {
                    if !showsCloseButton && !isInputFocused {
                        CoachInlineTopBar(
                            thread: viewModel.activeThread,
                            isLoading: viewModel.isLoading,
                            onNewChat: {
                                Task {
                                    await viewModel.createThread()
                                    Haptics.light()
                                }
                            },
                            onHistory: { openThreadHistory() },
                            onHelp: {
                                guidedTour.startScreenTour(.coach)
                            }
                        )
                        .tourTarget(.coachTopBar)
                        .padding(.horizontal, 20)
                        .padding(.top, 6)
                    }

                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 12) {
                                if viewModel.messages.isEmpty && !viewModel.isStreaming && !isInputFocused {
                                    CoachEmptyStateView(
                                        prompts: starterPrompts,
                                        onPrompt: { prompt in
                                            sendPrompt(prompt)
                                        },
                                        onHistory: { openThreadHistory() }
                                    )
                                    .padding(.top, 16)
                                }

                                ForEach(viewModel.visibleMessages) { message in
                                    CoachMessageRow(message: message)
                                        .id(message.id)
                                }

                                if let workoutCard = viewModel.workoutCard {
                                    CoachWorkoutGenerationCard(card: workoutCard)
                                        .id(workoutCard.id)
                                }

                                if let actionProposal = viewModel.actionProposal {
                                    CoachActionProposalCard(
                                        proposal: actionProposal,
                                        isApplying: viewModel.isApplyingAction,
                                        onApply: {
                                            Task {
                                                await viewModel.applyActionProposal()
                                            }
                                        },
                                        onDismiss: {
                                            viewModel.dismissActionProposal()
                                        }
                                    )
                                    .id(actionProposal.id)
                                }

                                if let actionExecutionStatus = viewModel.actionExecutionStatus {
                                    CoachActionExecutionStatusCard(status: actionExecutionStatus)
                                        .id(actionExecutionStatus.id)
                                }

                                if viewModel.isStreaming,
                                   let last = viewModel.messages.last,
                                   last.role == .assistant,
                                   last.text.isEmpty {
                                    CoachTypingRow()
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 10)
                            .padding(.bottom, 8)
                        }
                        .scrollDismissesKeyboard(.interactively)
                        .onChange(of: viewModel.messages.count) { _ in
                            scrollToLatest(proxy: proxy)
                        }
                        .onChange(of: viewModel.isStreaming) { _ in
                            scrollToLatest(proxy: proxy)
                        }
                        .onChange(of: viewModel.workoutCard?.id) { _ in
                            scrollToLatest(proxy: proxy)
                        }
                        .onChange(of: viewModel.actionProposal?.id) { _ in
                            scrollToLatest(proxy: proxy)
                        }
                        .onChange(of: viewModel.actionExecutionStatus?.id) { _ in
                            scrollToLatest(proxy: proxy)
                        }
                        .onChange(of: isInputFocused) { _ in
                            scrollToLatest(proxy: proxy)
                        }
                    }

                    if let status = viewModel.statusMessage, !isInputFocused {
                        CoachStatusBanner(
                            title: status,
                            showRetry: viewModel.pendingRetry != nil,
                            onRetry: { Task { await viewModel.retryLastMessage() } }
                        )
                        .padding(.horizontal, 20)
                    }
                    
                    // New Chat button - visible when there are messages
                    if !viewModel.messages.isEmpty && !isInputFocused {
                        Button {
                            Task {
                                await viewModel.createThread()
                                Haptics.light()
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "plus.message.fill")
                                    .font(.system(size: 14, weight: .semibold))
                                Text("New Chat")
                                    .font(FitFont.body(size: 14, weight: .semibold))
                            }
                            .foregroundColor(FitTheme.cardCoachAccent)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(FitTheme.cardCoachAccent.opacity(0.12))
                            .clipShape(Capsule())
                        }
                        .padding(.horizontal, 20)
                    }
                }

            }
            .navigationTitle(showsCloseButton ? "Coach" : "")
            .onTapGesture {
                dismissKeyboard()
            }
            .toolbar {
                if showsCloseButton {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Close") {
                            if let onClose {
                                onClose()
                            } else {
                                dismiss()
                            }
                        }
                            .foregroundColor(FitTheme.textPrimary)
                    }
                }
                if showsCloseButton {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        HStack(spacing: 16) {
                            Button {
                                Task {
                                    await viewModel.createThread()
                                    Haptics.light()
                                }
                            } label: {
                                Image(systemName: "plus.message")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(FitTheme.accent)
                            }

                            Button { openThreadHistory() } label: {
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(FitTheme.textPrimary)
                            }
                        }
                    }
                }
            }
            .toolbar(showsCloseButton ? .visible : .hidden, for: .navigationBar)
            .toolbar(isInputFocused ? .hidden : .visible, for: .tabBar)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 0) {
                    Rectangle()
                        .fill(FitTheme.cardStroke.opacity(0.45))
                        .frame(height: 1)
                    CoachInputBar(
                        text: $draftMessage,
                        isSending: viewModel.isStreaming,
                        isFocused: $isInputFocused,
                        dictation: dictation,
                        onSend: handleSend
                    )
                    .tourTarget(.coachInputBar, shape: .roundedRect(cornerRadius: 16), padding: 0)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, isInputFocused ? 8 : 12)
                }
                .background(.ultraThinMaterial)
            }
            .sheet(isPresented: $showingThreads) {
                CoachThreadListView(
                    threads: viewModel.threads,
                    activeThreadId: viewModel.activeThread?.id,
                    onSelect: { thread in
                        Task {
                            await viewModel.selectThread(thread)
                        }
                    },
                    onCreate: {
                        Task {
                            await viewModel.createThread()
                        }
                    }
                )
            }
            .task {
                await viewModel.loadInitialThread()
            }
            .onChange(of: guidedTour.currentStep?.id) { _ in
                ensureGuidedTourTargetVisibility()
            }
        }
        .tint(FitTheme.accent)
    }

    private func handleSend() {
        guard !viewModel.isStreaming else { return }
        let trimmed = draftMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        draftMessage = ""
        Task {
            await viewModel.sendMessage(trimmed)
        }
    }

    private func sendPrompt(_ prompt: String) {
        guard !viewModel.isStreaming else { return }
        Task {
            await viewModel.sendMessage(prompt)
        }
    }

    private func openThreadHistory() {
        showingThreads = true
        Task {
            await viewModel.refreshThreadHistorySilently()
        }
    }

    private func scrollToLatest(proxy: ScrollViewProxy) {
        guard let lastId = viewModel.messages.last?.id else { return }
        proxy.scrollTo(lastId, anchor: .bottom)
    }

    private func ensureGuidedTourTargetVisibility() {
        guard let step = guidedTour.currentStep else { return }
        guard step.screen == .coach else { return }
        if step.target == .coachTopBar {
            isInputFocused = false
        }
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }
}

private struct CoachEmptyStateView: View {
    let prompts: [String]
    let onPrompt: (String) -> Void
    let onHistory: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            CoachHeroCard()

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 10))
                            .foregroundColor(FitTheme.cardCoachAccent)
                        Text("QUICK START")
                            .font(FitFont.body(size: 11, weight: .bold))
                            .foregroundColor(FitTheme.cardCoachAccent)
                            .tracking(1)
                    }

                    Spacer()

                    Button(action: onHistory) {
                        HStack(spacing: 6) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 12, weight: .semibold))
                            Text("History")
                                .font(FitFont.body(size: 12, weight: .semibold))
                        }
                        .foregroundColor(FitTheme.textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(FitTheme.cardHighlight.opacity(0.75))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }

                ForEach(Array(prompts.enumerated()), id: \.offset) { index, prompt in
                    Button(action: { onPrompt(prompt) }) {
                        HStack(alignment: .top, spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(FitTheme.cardCoachAccent.opacity(0.15))
                                    .frame(width: 32, height: 32)
                                Image(systemName: promptIcon(for: index))
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(FitTheme.cardCoachAccent)
                            }
                            
                            Text(prompt)
                                .font(FitFont.body(size: 14))
                                .foregroundColor(FitTheme.textPrimary)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, 3)
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(FitTheme.textSecondary)
                                .padding(.top, 6)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 11)
                        .background(FitTheme.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(FitTheme.cardStroke.opacity(0.6), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }
    
    private func promptIcon(for index: Int) -> String {
        switch index {
        case 0: return "figure.strengthtraining.traditional"
        case 1: return "calendar"
        case 2: return "fork.knife"
        case 3: return "flame.fill"
        default: return "sparkles"
        }
    }
}

private struct CoachHeroCard: View {
    var body: some View {
        VStack(spacing: 14) {
            CoachCharacterView(size: 96, showBackground: false, pose: .neutral)

            VStack(spacing: 8) {
                Text("Your Personal Trainer")
                    .font(FitFont.heading(size: 20))
                    .foregroundColor(FitTheme.textPrimary)
                Text("Get personalized workout plans, form tips, nutrition advice, and recovery strategies.")
                    .font(FitFont.body(size: 14))
                    .foregroundColor(FitTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(
            LinearGradient(
                colors: [FitTheme.cardCoach, FitTheme.cardCoach.opacity(0.8)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(FitTheme.cardCoachAccent.opacity(0.3), lineWidth: 1.5)
        )
        .shadow(color: FitTheme.cardCoachAccent.opacity(0.15), radius: 16, x: 0, y: 8)
    }
}

@MainActor
final class CoachChatViewModel: ObservableObject {
    @Published var threads: [ChatThread] = []
    @Published var messages: [CoachChatMessage] = []
    @Published var activeThread: ChatThread?
    @Published var isLoading = false
    @Published var isStreaming = false
    @Published var statusMessage: String?
    @Published var pendingRetry: String?
    @Published var workoutCard: CoachWorkoutCard?
    @Published var actionProposal: CoachActionProposal?
    @Published var actionExecutionStatus: CoachActionExecutionStatus?
    @Published var isApplyingAction = false

    let userId: String
    private var hiddenAssistantMessageIds: Set<String> = []
    private var autoApplyIncomingActionProposal = false
    private var suppressNextIncomingActionProposal = false
    private var pendingAutoApplyActionType: CoachActionType?

    init(userId: String) {
        self.userId = userId
    }

    private static let assistantHeadingRegex: NSRegularExpression = {
        // Matches markdown headings like "## Title"
        (try? NSRegularExpression(pattern: #"(?m)^\s{0,3}#{1,6}\s+"#)) ?? (try! NSRegularExpression(pattern: #"(?!)"#))
    }()

    private static let assistantListMarkerRegex: NSRegularExpression = {
        // Matches "- item", "• item", "* item", "1. item", "1) item"
        (try? NSRegularExpression(pattern: #"(?m)^\s*(?:[-•*]|\d+\s*[.)])\s+"#)) ?? (try! NSRegularExpression(pattern: #"(?!)"#))
    }()

    private static let assistantWhitespaceRegex: NSRegularExpression = {
        (try? NSRegularExpression(pattern: #"\s+"#)) ?? (try! NSRegularExpression(pattern: #"(?!)"#))
    }()

    private static let isoDateWithFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let isoDateStandard: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private func sanitizeAssistantText(_ value: String) -> String {
        var text = value

        // Drop common markdown tokens that look "computer-y" in chat bubbles.
        text = text.replacingOccurrences(of: "```", with: "")
        text = text.replacingOccurrences(of: "**", with: "")
        text = text.replacingOccurrences(of: "__", with: "")
        text = text.replacingOccurrences(of: "`", with: "")

        let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
        text = Self.assistantHeadingRegex.stringByReplacingMatches(in: text, range: fullRange, withTemplate: "")
        text = Self.assistantListMarkerRegex.stringByReplacingMatches(
            in: text,
            range: NSRange(text.startIndex..<text.endIndex, in: text),
            withTemplate: ""
        )

        // Collapse whitespace/newlines into a single flowing message.
        text = Self.assistantWhitespaceRegex.stringByReplacingMatches(
            in: text,
            range: NSRange(text.startIndex..<text.endIndex, in: text),
            withTemplate: " "
        )

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func loadInitialThread() async {
        guard !userId.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }

        if let activeId = CoachChatSession.shared.activeThreadId {
            await loadThread(threadId: activeId)
        } else {
            await startNewSession()
            CoachChatSession.shared.activeThreadId = activeThread?.id
        }

        _ = await refreshThreads()
    }

    func selectThread(_ thread: ChatThread) async {
        guard !userId.isEmpty else { return }
        isLoading = true
        activeThread = thread
        CoachChatSession.shared.activeThreadId = thread.id
        workoutCard = nil
        actionProposal = nil
        actionExecutionStatus = nil
        autoApplyIncomingActionProposal = false
        suppressNextIncomingActionProposal = false
        hiddenAssistantMessageIds.removeAll()
        do {
            let detail = try await ChatAPIService.shared.fetchThreadDetail(
                userId: userId,
                threadId: thread.id
            )
            upsertThread(detail.thread, placeAtTop: false)
            activeThread = detail.thread
            applyThreadDetail(detail)
        } catch {
            statusMessage = "Unable to load coach messages."
        }
        isLoading = false
    }

    func createThread(title: String? = nil, startEmpty: Bool = false) async {
        guard !userId.isEmpty else { return }
        isLoading = true
        do {
            let thread = try await ChatAPIService.shared.createThread(userId: userId, title: title)
            upsertThread(thread, placeAtTop: true)
            CoachChatSession.shared.activeThreadId = thread.id
            if startEmpty {
                activeThread = thread
                messages = []
                workoutCard = nil
                actionProposal = nil
                actionExecutionStatus = nil
                autoApplyIncomingActionProposal = false
                suppressNextIncomingActionProposal = false
                hiddenAssistantMessageIds.removeAll()
            } else {
                await selectThread(thread)
            }
        } catch {
            statusMessage = "Unable to start a new coach chat."
        }
        isLoading = false
    }

    func startNewSession() async {
        await createThread(title: "AI Coach", startEmpty: true)
    }

    func sendMessage(_ text: String) async {
        guard let thread = activeThread else {
            statusMessage = "Create a thread to start chatting."
            return
        }
        statusMessage = nil
        pendingRetry = nil
        let requestedActionType = Self.detectRequestedActionType(text)
        pendingAutoApplyActionType = requestedActionType
        defer { pendingAutoApplyActionType = nil }
        let wantsActionExecution = Self.isActionExecutionIntent(text)
        let isWorkoutRequest = Self.isWorkoutRequest(text)

        var analyticsProps: [String: Any] = [
            "chat_type": "coach",
            "thread_id": thread.id,
            "message_length": text.count,
            "is_workout_request": isWorkoutRequest,
            "wants_action_execution": wantsActionExecution
        ]
        if let requestedActionType {
            analyticsProps["requested_action_type"] = requestedActionType.rawValue
        }
        PostHogAnalytics.featureUsed(.aiChat, action: "message_sent", properties: analyticsProps)

        let userMessage = CoachChatMessage(
            id: UUID().uuidString,
            role: .user,
            text: text
        )
        messages.append(userMessage)

        autoApplyIncomingActionProposal = wantsActionExecution
        if wantsActionExecution, actionProposal != nil {
            suppressNextIncomingActionProposal = true
            await applyActionProposal()
        }

        let assistantId = UUID().uuidString
        messages.append(CoachChatMessage(id: assistantId, role: .assistant, text: ""))
        if isWorkoutRequest {
            hiddenAssistantMessageIds.insert(assistantId)
            workoutCard = CoachWorkoutCard(state: .generating)
        }
        isStreaming = true

        do {
            try await ChatAPIService.shared.sendMessageStream(
                userId: userId,
                threadId: thread.id,
                content: text
            ) { [weak self] event in
                Task { @MainActor in
                    self?.applyAssistantEvent(event, messageId: assistantId)
                }
            }
            markThreadAsUpdatedLocally(threadId: thread.id)
            let refreshed = await refreshThreads(retries: 2, showStatusOnFailure: false)
            if !refreshed {
                statusMessage = "Chat updated locally. Thread history will sync shortly."
            }
            if isWorkoutRequest {
                updateWorkoutCard(for: assistantId)
            }
            if requestedActionType == .updateMacros {
                await maybeApplyMacroTargetsFromAssistantTextIfNeeded(messageId: assistantId)
            }
        } catch {
            messages.removeAll { $0.id == assistantId }
            hiddenAssistantMessageIds.remove(assistantId)
            if isWorkoutRequest {
                workoutCard = CoachWorkoutCard(state: .failed("Workout failed. Please try again."))
            }
            statusMessage = "Message failed. Tap to retry."
            pendingRetry = text
        }

        autoApplyIncomingActionProposal = false
        suppressNextIncomingActionProposal = false
        isStreaming = false
    }

    func retryLastMessage() async {
        guard let retryText = pendingRetry else { return }
        pendingRetry = nil
        await sendMessage(retryText)
    }

    private func applyAssistantEvent(_ event: ChatStreamEvent, messageId: String) {
        switch event {
        case let .coachAction(proposal):
            if suppressNextIncomingActionProposal {
                suppressNextIncomingActionProposal = false
                return
            }
            actionProposal = proposal
            if shouldAutoApplyActionProposal(proposal) {
                autoApplyIncomingActionProposal = false
                pendingAutoApplyActionType = nil
                Task { @MainActor in
                    await applyActionProposal()
                }
            }
        case let .delta(text):
            guard let index = messages.lastIndex(where: { $0.id == messageId }) else { return }
            messages[index].text += text
            if messages[index].role == .assistant {
                messages[index].text = sanitizeAssistantText(messages[index].text)
            }
        case let .replace(text):
            guard let index = messages.lastIndex(where: { $0.id == messageId }) else { return }
            messages[index].text = messages[index].role == .assistant ? sanitizeAssistantText(text) : text
        }
    }

    private func shouldAutoApplyActionProposal(_ proposal: CoachActionProposal) -> Bool {
        if autoApplyIncomingActionProposal {
            return true
        }

        if pendingAutoApplyActionType == proposal.actionType {
            return true
        }

        let prompt = proposal.confirmationPrompt?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if prompt.isEmpty, proposal.actionType == .updateMacros {
            return true
        }

        return false
    }

    private func maybeApplyMacroTargetsFromAssistantTextIfNeeded(messageId: String) async {
        guard actionProposal == nil else { return }
        guard !isApplyingAction else { return }
        guard actionExecutionStatus == nil else { return }
        guard let assistant = messages.last(where: { $0.id == messageId }), assistant.role == .assistant else { return }
        guard let targets = Self.extractMacroTargets(from: assistant.text) else { return }

        actionProposal = CoachActionProposal(
            actionType: .updateMacros,
            title: "Update macro targets",
            description: "Apply the macro targets from your coach message in the app.",
            confirmationPrompt: nil,
            macros: targets,
            split: nil
        )

        await applyActionProposal()
    }

    func applyActionProposal() async {
        guard !isApplyingAction else { return }
        guard let proposal = actionProposal else { return }
        isApplyingAction = true
        actionExecutionStatus = CoachActionExecutionStatus(
            actionType: proposal.actionType,
            state: .applying
        )
        defer { isApplyingAction = false }

        do {
            let resultMessage = try await CoachActionExecutor.apply(proposal: proposal, userId: userId)
            messages.append(
                CoachChatMessage(
                    id: UUID().uuidString,
                    role: .assistant,
                    text: resultMessage
                )
            )
            actionProposal = nil
            actionExecutionStatus = CoachActionExecutionStatus(
                actionType: proposal.actionType,
                state: .completed
            )
            statusMessage = "Changes applied."
            Haptics.success()
        } catch {
            actionExecutionStatus = CoachActionExecutionStatus(
                actionType: proposal.actionType,
                state: .failed(error.localizedDescription)
            )
            statusMessage = error.localizedDescription
            Haptics.error()
        }
    }

    func dismissActionProposal() {
        actionProposal = nil
    }

    func refreshThreadHistorySilently() async {
        _ = await refreshThreads(retries: 1, showStatusOnFailure: false)
    }

    @discardableResult
    private func refreshThreads(retries: Int = 1, showStatusOnFailure: Bool = true) async -> Bool {
        for attempt in 0...retries {
            do {
                let fetched = try await ChatAPIService.shared.fetchThreads(userId: userId)
                threads = fetched.sorted { threadDate($0) > threadDate($1) }
                if let active = activeThread,
                   let refreshed = threads.first(where: { $0.id == active.id }) {
                    activeThread = refreshed
                }
                return true
            } catch {
                if attempt < retries {
                    let delay = UInt64(attempt + 1) * 300_000_000
                    try? await Task.sleep(nanoseconds: delay)
                    continue
                }
                if showStatusOnFailure {
                    statusMessage = "Chat updated locally. Thread history will sync shortly."
                }
            }
        }
        return false
    }

    private func markThreadAsUpdatedLocally(threadId: String) {
        let current = threads.first(where: { $0.id == threadId }) ?? activeThread
        let now = Self.isoDateWithFractionalSeconds.string(from: Date())
        let updated = ChatThread(
            id: threadId,
            title: current?.title ?? "AI Coach",
            createdAt: current?.createdAt,
            updatedAt: now,
            lastMessageAt: now
        )
        upsertThread(updated, placeAtTop: true)
    }

    private func upsertThread(_ thread: ChatThread, placeAtTop: Bool) {
        if let index = threads.firstIndex(where: { $0.id == thread.id }) {
            threads.remove(at: index)
        }
        if placeAtTop {
            threads.insert(thread, at: 0)
        } else {
            threads.append(thread)
            threads.sort { threadDate($0) > threadDate($1) }
        }
        if activeThread?.id == thread.id {
            activeThread = thread
        }
    }

    private func threadDate(_ thread: ChatThread) -> Date {
        if let value = thread.lastMessageAt ?? thread.updatedAt,
           let date = Self.isoDateWithFractionalSeconds.date(from: value) ?? Self.isoDateStandard.date(from: value) {
            return date
        }
        return Date.distantPast
    }

    private func loadThread(threadId: String) async {
        guard !userId.isEmpty else { return }
        do {
            let detail = try await ChatAPIService.shared.fetchThreadDetail(
                userId: userId,
                threadId: threadId
            )
            upsertThread(detail.thread, placeAtTop: false)
            activeThread = detail.thread
            applyThreadDetail(detail)
        } catch {
            statusMessage = "Unable to load coach messages."
        }
    }

    private func applyThreadDetail(_ detail: ChatThreadDetailResponse) {
        messages = detail.messages.compactMap { payload in
            guard let role = CoachMessageRole(rawValue: payload.role) else { return nil }
            if role == .system {
                return nil
            }
            let displayText = role == .assistant ? sanitizeAssistantText(payload.content) : payload.content
            return CoachChatMessage(
                id: payload.id,
                role: role,
                text: displayText
            )
        }
        hiddenAssistantMessageIds.removeAll()
        workoutCard = nil
        actionProposal = nil
        actionExecutionStatus = nil
        autoApplyIncomingActionProposal = false
        suppressNextIncomingActionProposal = false
    }

    private func updateWorkoutCard(for assistantId: String) {
        guard let message = messages.first(where: { $0.id == assistantId })?.text else {
            workoutCard = CoachWorkoutCard(state: .completed("Workout generated. Check your workout view."))
            return
        }
        let lowered = message.lowercased()
        if lowered.contains("workout failed") {
            workoutCard = CoachWorkoutCard(state: .failed("Workout failed. Tell me your goal and equipment."))
        } else {
            workoutCard = CoachWorkoutCard(state: .completed("Workout generated. Check your workout view."))
        }
    }

    var visibleMessages: [CoachChatMessage] {
        messages.filter { !hiddenAssistantMessageIds.contains($0.id) }
    }

    private static let workoutKeywords = ["workout", "routine", "session"]
    private static let workoutActions = ["build", "create", "make", "generate", "design", "plan"]
    private static let actionExecutionPhrases = [
        "do it", "go ahead", "apply it", "apply them", "update it", "update them",
        "make the change", "please update", "please apply", "can you update", "can you apply",
        "did you update", "did you apply", "sounds good", "lets do it", "let's do it"
    ]
    private static let muscleKeywords = [
        "glute", "glutes", "booty", "hamstring", "hamstrings", "quad", "quads",
        "leg", "legs", "calf", "calves", "chest", "pec", "pecs", "back", "lat",
        "lats", "shoulder", "shoulders", "delt", "delts", "biceps", "triceps",
        "arms", "core", "abs", "upper", "lower", "push", "pull", "full body", "hiit",
    ]

    private static func isWorkoutRequest(_ text: String) -> Bool {
        let lowered = text.lowercased()
        let hasWorkout = workoutKeywords.contains { lowered.contains($0) }
        let hasAction = workoutActions.contains { lowered.contains($0) }
        let hasMuscle = muscleKeywords.contains { lowered.contains($0) }
        return (hasWorkout && hasAction) || (hasWorkout && hasMuscle) || (hasAction && hasMuscle)
    }

    private static func isActionExecutionIntent(_ text: String) -> Bool {
        let lowered = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if ["yes", "yeah", "yep", "sure", "ok", "okay"].contains(lowered) {
            return true
        }
        return actionExecutionPhrases.contains { lowered.contains($0) }
    }

    private static let macroKeywords = ["calorie", "kcal", "macro", "protein", "carb", "fat"]
    private static let macroUpdateVerbs = ["set", "update", "change", "adjust", "increase", "decrease", "lower", "raise", "bump"]

    private static func detectRequestedActionType(_ text: String) -> CoachActionType? {
        if isMacroUpdateRequest(text) {
            return .updateMacros
        }
        return nil
    }

    private static func isMacroUpdateRequest(_ text: String) -> Bool {
        let lowered = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard macroKeywords.contains(where: { lowered.contains($0) }) else { return false }
        guard macroUpdateVerbs.contains(where: { lowered.contains($0) }) else { return false }
        return lowered.range(of: #"\d{2,5}"#, options: .regularExpression) != nil
    }

    private static func extractMacroTargets(from text: String) -> CoachMacroTargets? {
        let lowered = text.lowercased()

        func firstIntMatch(_ pattern: String) -> Int? {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
            let range = NSRange(lowered.startIndex..<lowered.endIndex, in: lowered)
            guard let match = regex.firstMatch(in: lowered, range: range),
                  match.numberOfRanges >= 2,
                  let valueRange = Range(match.range(at: 1), in: lowered) else { return nil }
            return Int(lowered[valueRange])
        }

        let calories =
            firstIntMatch(#"\b(?:calories|kcal)\b[^\d]{0,12}(\d{3,5})\b"#) ??
            firstIntMatch(#"\b(\d{3,5})\b[^\d]{0,6}\b(?:kcal|calories)\b"#)
        let protein =
            firstIntMatch(#"\bprotein\b[^\d]{0,12}(\d{2,4})\b"#) ??
            firstIntMatch(#"\b(\d{2,4})\b\s*g?\s*protein\b"#)
        let carbs =
            firstIntMatch(#"\b(?:carbs?|carbohydrates?)\b[^\d]{0,12}(\d{2,4})\b"#) ??
            firstIntMatch(#"\b(\d{2,4})\b\s*g?\s*(?:carbs?|carbohydrates?)\b"#)
        let fats =
            firstIntMatch(#"\b(?:fats?|fat)\b[^\d]{0,12}(\d{2,4})\b"#) ??
            firstIntMatch(#"\b(\d{2,4})\b\s*g?\s*(?:fats?|fat)\b"#)

        let hasAny = calories != nil || protein != nil || carbs != nil || fats != nil
        guard hasAny else { return nil }

        return CoachMacroTargets(
            calories: calories,
            protein: protein,
            carbs: carbs,
            fats: fats
        )
    }

}

private final class CoachChatSession {
    static let shared = CoachChatSession()
    var activeThreadId: String?
}

struct CoachChatMessage: Identifiable {
    let id: String
    let role: CoachMessageRole
    var text: String
}

struct CoachWorkoutCard: Identifiable {
    enum State: Equatable {
        case generating
        case completed(String)
        case failed(String)
    }

    let id: String = UUID().uuidString
    var state: State
}

struct CoachActionExecutionStatus: Identifiable {
    enum State: Equatable {
        case applying
        case completed
        case failed(String)
    }

    let id: String = UUID().uuidString
    let actionType: CoachActionType
    var state: State
}

enum CoachMessageRole: String {
    case user
    case assistant
    case system
}

private enum CoachActionExecutorError: LocalizedError {
    case missingPayload
    case nothingToUpdate

    var errorDescription: String? {
        switch self {
        case .missingPayload:
            return "I couldn't read the change details."
        case .nothingToUpdate:
            return "No valid changes were found to apply."
        }
    }
}

enum CoachActionExecutor {
    private static let splitPreferencesKey = SplitSchedule.splitPreferencesKey
    private static let onboardingFormKey = "fitai.onboarding.form"

    static func apply(proposal: CoachActionProposal, userId: String) async throws -> String {
        switch proposal.actionType {
        case .updateMacros:
            return try await applyMacroTargets(proposal: proposal, userId: userId)
        case .updateWorkoutSplit:
            return try await applyWorkoutSplit(proposal: proposal, userId: userId)
        }
    }

    private static func applyMacroTargets(proposal: CoachActionProposal, userId: String) async throws -> String {
        guard let macros = proposal.macros else {
            throw CoachActionExecutorError.missingPayload
        }

        let profile = (try? await ProfileAPIService.shared.fetchProfile(userId: userId)) ?? [:]
        var mergedMacros = profile["macros"] as? [String: Any] ?? [:]
        var didUpdate = false

        if let calories = macros.calories, calories > 0 {
            mergedMacros["calories"] = calories
            didUpdate = true
        }
        if let protein = macros.protein, protein >= 0 {
            mergedMacros["protein"] = protein
            didUpdate = true
        }
        if let carbs = macros.carbs, carbs >= 0 {
            mergedMacros["carbs"] = carbs
            didUpdate = true
        }
        if let fats = macros.fats, fats >= 0 {
            mergedMacros["fats"] = fats
            didUpdate = true
        }

        guard didUpdate else {
            throw CoachActionExecutorError.nothingToUpdate
        }

        _ = try await ProfileAPIService.shared.updateProfile(
            userId: userId,
            payload: ["macros": mergedMacros]
        )

        var form = loadOnboardingForm(userId: userId)
        if let calories = mergedMacros["calories"] { form.macroCalories = stringValue(calories) }
        if let protein = mergedMacros["protein"] { form.macroProtein = stringValue(protein) }
        if let carbs = mergedMacros["carbs"] { form.macroCarbs = stringValue(carbs) }
        if let fats = mergedMacros["fats"] { form.macroFats = stringValue(fats) }
        saveOnboardingForm(form)

        NotificationCenter.default.post(name: .fitAIMacrosUpdated, object: nil)
        NotificationCenter.default.post(name: .fitAIProfileUpdated, object: nil)

        let calories = intValue(mergedMacros["calories"])
        let protein = intValue(mergedMacros["protein"])
        let carbs = intValue(mergedMacros["carbs"])
        let fats = intValue(mergedMacros["fats"])
        return "Done. Your macro targets are now \(calories) kcal, \(protein)g protein, \(carbs)g carbs, and \(fats)g fats."
    }

    private static func applyWorkoutSplit(proposal: CoachActionProposal, userId: String) async throws -> String {
        guard let split = proposal.split else {
            throw CoachActionExecutorError.missingPayload
        }

        let current = SplitSchedule.loadSnapshot().snapshot
        let clampedDays = min(max(split.daysPerWeek ?? current.daysPerWeek, 2), 7)
        let normalizedDays = normalizedTrainingDays(split.trainingDays ?? current.trainingDays, targetCount: clampedDays)
        let splitType = SplitType(rawValue: split.splitType ?? current.splitType.rawValue) ?? .smart
        let mode = SplitCreationMode(rawValue: split.mode ?? current.mode.rawValue) ?? .ai
        let focusText = split.focus?.trimmingCharacters(in: .whitespacesAndNewlines)
        let focus = (focusText?.isEmpty == false ? focusText : current.focus) ?? "Strength"

        let validDays = Set(normalizedDays)
        let filteredPlans = current.dayPlans.filter { validDays.contains($0.key) }
        let preferences = SplitSetupPreferences(
            mode: mode.rawValue,
            daysPerWeek: clampedDays,
            trainingDays: normalizedDays,
            splitType: splitType,
            dayPlans: filteredPlans,
            focus: focus,
            isUserConfigured: true
        )
        if let encoded = try? JSONEncoder().encode(preferences) {
            UserDefaults.standard.set(encoded, forKey: splitPreferencesKey)
        }

        var form = loadOnboardingForm(userId: userId)
        form.workoutDaysPerWeek = clampedDays
        form.trainingDaysOfWeek = normalizedDays
        saveOnboardingForm(form)

        let profile = (try? await ProfileAPIService.shared.fetchProfile(userId: userId)) ?? [:]
        var mergedPreferences = profile["preferences"] as? [String: Any] ?? [:]
        mergedPreferences["workout_days_per_week"] = clampedDays
        mergedPreferences["training_days_of_week"] = normalizedDays
        mergedPreferences["split_type"] = splitType.rawValue
        mergedPreferences["split_creation_mode"] = mode.rawValue
        mergedPreferences["split_focus"] = focus

        _ = try await ProfileAPIService.shared.updateProfile(
            userId: userId,
            payload: ["preferences": mergedPreferences]
        )

        NotificationCenter.default.post(name: .fitAISplitUpdated, object: nil)
        NotificationCenter.default.post(name: .fitAIProfileUpdated, object: nil)

        let splitTitle = splitType.title
        return "Done. I updated your split to \(clampedDays) days/week with a \(splitTitle) setup."
    }

    private static func normalizedTrainingDays(_ days: [String], targetCount: Int) -> [String] {
        let availableDays = Calendar.current.weekdaySymbols
        let filtered = days.filter { availableDays.contains($0) }
        var ordered = availableDays.filter { filtered.contains($0) }

        if ordered.count > targetCount {
            ordered = Array(ordered.prefix(targetCount))
        }
        if ordered.count < targetCount {
            for day in availableDays where !ordered.contains(day) {
                ordered.append(day)
                if ordered.count == targetCount {
                    break
                }
            }
        }
        return ordered
    }

    private static func loadOnboardingForm(userId: String) -> OnboardingForm {
        if let data = UserDefaults.standard.data(forKey: onboardingFormKey),
           var form = try? JSONDecoder().decode(OnboardingForm.self, from: data) {
            if form.userId == nil || form.userId?.isEmpty == true {
                form.userId = userId
            }
            return form
        }
        var form = OnboardingForm()
        form.userId = userId
        return form
    }

    private static func saveOnboardingForm(_ form: OnboardingForm) {
        guard let encoded = try? JSONEncoder().encode(form) else { return }
        UserDefaults.standard.set(encoded, forKey: onboardingFormKey)
    }

    private static func intValue(_ value: Any?) -> Int {
        if let intValue = value as? Int { return intValue }
        if let number = value as? NSNumber { return number.intValue }
        if let text = value as? String, let parsed = Int(text) { return parsed }
        return 0
    }

    private static func stringValue(_ value: Any?) -> String {
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        return ""
    }
}

private struct CoachInlineTopBar: View {
    let thread: ChatThread?
    let isLoading: Bool
    let onNewChat: () -> Void
    let onHistory: () -> Void
    let onHelp: () -> Void

    private var title: String {
        if let raw = thread?.title?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
            return raw
        }
        return "Ask Your Coach"
    }

    private var subtitle: String {
        if isLoading {
            return "Syncing your coach context..."
        }
        return "Fast, personalized guidance for training and nutrition."
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(FitFont.body(size: 17, weight: .semibold))
                    .foregroundColor(FitTheme.textPrimary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(FitFont.body(size: 12))
                    .foregroundColor(FitTheme.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            HStack(spacing: 10) {
                Button(action: onNewChat) {
                    Image(systemName: "plus.message")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(FitTheme.textPrimary)
                        .frame(width: 36, height: 36)
                        .background(FitTheme.cardHighlight)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                Button(action: onHistory) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(FitTheme.textPrimary)
                        .frame(width: 36, height: 36)
                        .background(FitTheme.cardHighlight)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                Button(action: onHelp) {
                    Image(systemName: "questionmark.circle.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(FitTheme.textPrimary)
                        .frame(width: 36, height: 36)
                        .background(FitTheme.cardHighlight)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(FitTheme.cardBackground.opacity(0.86))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(FitTheme.cardStroke.opacity(0.55), lineWidth: 1)
        )
    }
}

private struct CoachMessageRow: View {
    let message: CoachChatMessage

    private var isUser: Bool { message.role == .user }

    var body: some View {
        if message.text.isEmpty {
            EmptyView()
        } else {
            HStack(alignment: .top, spacing: 10) {
                if isUser { Spacer(minLength: 60) }
                
                if !isUser {
                    // Coach avatar
                    ZStack {
                        Circle()
                            .fill(FitTheme.cardCoachAccent.opacity(0.15))
                            .frame(width: 32, height: 32)
                        Image(systemName: "sparkles")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(FitTheme.cardCoachAccent)
                    }
                }

                VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                    Text(message.text)
                        .font(FitFont.body(size: 15))
                        .foregroundColor(isUser ? .white : FitTheme.textPrimary)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                        .background(
                            isUser 
                                ? AnyShapeStyle(FitTheme.cardCoachAccent)
                                : AnyShapeStyle(FitTheme.cardCoach)
                        )
                        .clipShape(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(
                                    isUser ? Color.clear : FitTheme.cardCoachAccent.opacity(0.2),
                                    lineWidth: 1
                                )
                        )
                }

                if !isUser { Spacer(minLength: 60) }
            }
            .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
        }
    }
}

private struct CoachTypingRow: View {
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Coach avatar
            ZStack {
                Circle()
                    .fill(FitTheme.cardCoachAccent.opacity(0.15))
                    .frame(width: 32, height: 32)
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(FitTheme.cardCoachAccent)
            }
            
            CoachTypingDots(color: FitTheme.cardCoachAccent)
            .padding(.vertical, 14)
            .padding(.horizontal, 18)
            .background(FitTheme.cardCoach)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(FitTheme.cardCoachAccent.opacity(0.2), lineWidth: 1)
            )
            
            Spacer()
        }
    }
}

private struct CoachWorkoutGenerationCard: View {
    let card: CoachWorkoutCard

    private var title: String {
        switch card.state {
        case .generating:
            return "Generating workout"
        case .completed:
            return "Workout ready"
        case .failed:
            return "Workout failed"
        }
    }

    private var message: String {
        switch card.state {
        case .generating:
            return "Building your plan now."
        case .completed(let text):
            return text
        case .failed(let text):
            return text
        }
    }

    private var accent: Color {
        switch card.state {
        case .failed:
            return Color(red: 0.92, green: 0.30, blue: 0.25)
        default:
            return FitTheme.cardCoachAccent
        }
    }

    private var isFailed: Bool {
        if case .failed = card.state { return true }
        return false
    }

    private var isGenerating: Bool {
        if case .generating = card.state { return true }
        return false
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(accent.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: isFailed ? "exclamationmark.triangle.fill" : "sparkles")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(accent)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(FitFont.body(size: 15, weight: .semibold))
                    .foregroundColor(FitTheme.textPrimary)
                Text(message)
                    .font(FitFont.body(size: 13))
                    .foregroundColor(FitTheme.textSecondary)

                if isGenerating {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: accent))
                        .scaleEffect(0.9)
                        .padding(.top, 4)
                }
            }

            Spacer()
        }
        .padding(14)
        .background(FitTheme.cardCoach)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(accent.opacity(0.3), lineWidth: 1)
        )
        .padding(.horizontal, 4)
    }
}

private struct CoachActionExecutionStatusCard: View {
    let status: CoachActionExecutionStatus

    private var title: String {
        switch status.state {
        case .applying:
            return status.actionType == .updateMacros ? "Updating macro targets" : "Updating workout split"
        case .completed:
            return status.actionType == .updateMacros ? "Macro targets updated" : "Workout split updated"
        case .failed:
            return status.actionType == .updateMacros ? "Macro update failed" : "Split update failed"
        }
    }

    private var message: String {
        switch status.state {
        case .applying:
            return status.actionType == .updateMacros
                ? "Syncing calories and macros in your app now."
                : "Syncing your training split in your app now."
        case .completed:
            return "Done. Changes are live in the app."
        case let .failed(errorText):
            let trimmed = errorText.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "Something went wrong. Please try again." : trimmed
        }
    }

    private var accent: Color {
        switch status.state {
        case .completed:
            return Color(red: 0.21, green: 0.78, blue: 0.43)
        case .failed:
            return Color(red: 0.92, green: 0.30, blue: 0.25)
        case .applying:
            return FitTheme.cardCoachAccent
        }
    }

    private var iconName: String {
        switch status.state {
        case .completed:
            return "checkmark.circle.fill"
        case .failed:
            return "xmark.octagon.fill"
        case .applying:
            return status.actionType == .updateMacros ? "chart.pie.fill" : "calendar.badge.clock"
        }
    }

    private var isApplying: Bool {
        if case .applying = status.state { return true }
        return false
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(accent.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: iconName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(accent)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(FitFont.body(size: 15, weight: .semibold))
                    .foregroundColor(FitTheme.textPrimary)
                Text(message)
                    .font(FitFont.body(size: 13))
                    .foregroundColor(FitTheme.textSecondary)

                if isApplying {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: accent))
                        .scaleEffect(0.9)
                        .padding(.top, 4)
                }
            }

            Spacer()
        }
        .padding(14)
        .background(FitTheme.cardCoach)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(accent.opacity(0.3), lineWidth: 1)
        )
        .padding(.horizontal, 4)
    }
}

private struct CoachActionProposalCard: View {
    let proposal: CoachActionProposal
    let isApplying: Bool
    let onApply: () -> Void
    let onDismiss: () -> Void

    private var iconName: String {
        switch proposal.actionType {
        case .updateMacros:
            return "chart.pie.fill"
        case .updateWorkoutSplit:
            return "calendar.badge.clock"
        }
    }

    private var detailText: String {
        switch proposal.actionType {
        case .updateMacros:
            guard let macros = proposal.macros else { return proposal.description }
            var chunks: [String] = []
            if let calories = macros.calories { chunks.append("\(calories) kcal") }
            if let protein = macros.protein { chunks.append("P \(protein)g") }
            if let carbs = macros.carbs { chunks.append("C \(carbs)g") }
            if let fats = macros.fats { chunks.append("F \(fats)g") }
            return chunks.isEmpty ? proposal.description : chunks.joined(separator: " · ")
        case .updateWorkoutSplit:
            guard let split = proposal.split else { return proposal.description }
            var chunks: [String] = []
            if let days = split.daysPerWeek { chunks.append("\(days) days/week") }
            if let splitType = split.splitType {
                chunks.append(splitTypeLabel(splitType))
            }
            if let focus = split.focus, !focus.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                chunks.append(focus)
            }
            return chunks.isEmpty ? proposal.description : chunks.joined(separator: " · ")
        }
    }

    private var confirmationText: String {
        let fallback = "Do you want me to apply this in your app now?"
        let trimmed = proposal.confirmationPrompt?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? fallback : trimmed
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(FitTheme.cardCoachAccent.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: iconName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(FitTheme.cardCoachAccent)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(proposal.title)
                    .font(FitFont.body(size: 15, weight: .semibold))
                    .foregroundColor(FitTheme.textPrimary)

                if !proposal.description.isEmpty {
                    Text(proposal.description)
                        .font(FitFont.body(size: 13))
                        .foregroundColor(FitTheme.textSecondary)
                }

                Text(detailText)
                    .font(FitFont.body(size: 13, weight: .semibold))
                    .foregroundColor(FitTheme.textPrimary)

                Text(confirmationText)
                    .font(FitFont.body(size: 12))
                    .foregroundColor(FitTheme.textSecondary)

                HStack(spacing: 10) {
                    Button(action: onApply) {
                        HStack(spacing: 6) {
                            if isApplying {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                            }
                            Text(isApplying ? "Applying..." : "Apply")
                                .font(FitFont.body(size: 13, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(FitTheme.primaryGradient)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(isApplying)

                    Button(action: onDismiss) {
                        Text("Not now")
                            .font(FitFont.body(size: 13, weight: .semibold))
                            .foregroundColor(FitTheme.textPrimary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(FitTheme.cardHighlight)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(isApplying)
                }
                .padding(.top, 2)
            }

            Spacer()
        }
        .padding(14)
        .background(FitTheme.cardCoach)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(FitTheme.cardCoachAccent.opacity(0.3), lineWidth: 1)
        )
        .padding(.horizontal, 4)
    }

    private func splitTypeLabel(_ raw: String) -> String {
        switch raw {
        case "fullBody":
            return "Full Body"
        case "upperLower":
            return "Upper/Lower"
        case "pushPullLegs":
            return "Push/Pull/Legs"
        case "hybrid":
            return "Hybrid"
        case "bodyPart":
            return "Body-Part"
        case "arnold":
            return "Arnold"
        default:
            return "Smart Split"
        }
    }
}

private struct CoachInputBar: View {
    @Binding var text: String
    let isSending: Bool
    let isFocused: FocusState<Bool>.Binding
    @ObservedObject var dictation: CoachDictationController
    let onSend: () -> Void

    private var canSend: Bool {
        !isSending && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ZStack {
            if dictation.state == .idle {
                standardBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                dictationBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.92), value: dictation.state)
        .alert(item: $dictation.permissionAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                primaryButton: .default(Text("Open Settings"), action: openSettings),
                secondaryButton: .cancel()
            )
        }
    }

    private var standardBar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Ask your coach...", text: $text, axis: .vertical)
                .font(FitFont.body(size: 15))
                .foregroundColor(FitTheme.textPrimary)
                .textInputAutocapitalization(.sentences)
                .autocorrectionDisabled(false)
                .lineLimit(1...5)
                .focused(isFocused)
                .submitLabel(.send)
                .onSubmit(onSend)
                .padding(.vertical, 11)
                .padding(.leading, 4)
                .layoutPriority(1)

            if isSending || canSend {
                Button(action: onSend) {
                    Image(systemName: isSending ? "ellipsis" : "paperplane.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(canSend ? .white : FitTheme.textSecondary)
                        .frame(width: 44, height: 44)
                        .background(
                            canSend ? AnyShapeStyle(FitTheme.primaryGradient) : AnyShapeStyle(FitTheme.cardHighlight)
                        )
                        .clipShape(Capsule())
                }
                .disabled(!canSend)
            } else {
                Button {
                    startDictation()
                } label: {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                        .background(AnyShapeStyle(FitTheme.primaryGradient))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(FitTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(
                    isFocused.wrappedValue ? FitTheme.cardCoachAccent.opacity(0.85) : FitTheme.cardCoachAccent.opacity(0.24),
                    lineWidth: isFocused.wrappedValue ? 2 : 1
                )
        )
        .shadow(
            color: FitTheme.cardCoachAccent.opacity(isFocused.wrappedValue ? 0.22 : 0.1),
            radius: isFocused.wrappedValue ? 14 : 10,
            x: 0,
            y: isFocused.wrappedValue ? 10 : 6
        )
        .animation(.easeInOut(duration: 0.2), value: isFocused.wrappedValue)
    }

    private var dictationBar: some View {
        HStack(spacing: 10) {
            Button(action: dictation.cancel) {
                Image(systemName: "trash.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color(red: 0.38, green: 0.23, blue: 0.86))
                    .frame(width: 36, height: 36)
                    .background(.white.opacity(0.98))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            CoachWaveformBars(samples: dictation.waveformSamples, barColor: .white.opacity(0.95))
                .frame(height: 20)
                .frame(maxWidth: .infinity)
                .padding(.trailing, 2)

            Text(dictation.formattedElapsed)
                .font(FitFont.body(size: 12, weight: .semibold))
                .monospacedDigit()
                .foregroundColor(.white.opacity(0.92))
                .frame(width: 36, alignment: .trailing)

            if dictation.state == .finalizing {
                ProgressView()
                    .tint(Color(red: 0.38, green: 0.23, blue: 0.86))
                    .frame(width: 36, height: 36)
                    .background(.white.opacity(0.98))
                    .clipShape(Circle())
            } else {
                Button {
                    stopAndSendDictation()
                } label: {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Color(red: 0.38, green: 0.23, blue: 0.86))
                        .frame(width: 36, height: 36)
                        .background(.white.opacity(0.98))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(dictation.state == .finalizing)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.53, green: 0.26, blue: 0.97),
                    Color(red: 0.43, green: 0.20, blue: 0.91)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(.white.opacity(0.35), lineWidth: 1.2)
        )
        .shadow(color: FitTheme.buttonShadow.opacity(0.55), radius: 14, x: 0, y: 10)
    }

    private func startDictation() {
        guard !isSending else { return }
        isFocused.wrappedValue = false
        Haptics.light()
        Task { await dictation.start() }
    }

    private func stopAndSendDictation() {
        Task {
            guard let transcript = await dictation.stopAndTranscribe() else { return }
            let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            let existing = text.trimmingCharacters(in: .whitespacesAndNewlines)
            text = existing.isEmpty ? trimmed : "\(existing) \(trimmed)"
            Haptics.light()
            onSend()
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

@MainActor
private final class CoachDictationController: NSObject, ObservableObject {
    struct PermissionAlert: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    enum State: Equatable {
        case idle
        case listening
        case finalizing
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var waveformSamples: [CGFloat] = Array(repeating: 0.12, count: 34)
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var liveTranscript = ""
    @Published var permissionAlert: PermissionAlert?

    private let audioEngine = AVAudioEngine()
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var inputTapInstalled = false
    private var startedAt: Date?
    private var meterTimer: Timer?
    private var latestTranscript = ""

    var formattedElapsed: String {
        let total = max(0, Int(elapsed.rounded(.down)))
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    func start() async {
        guard state == .idle else { return }

        let micAllowed = await requestMicrophonePermission()
        guard micAllowed else {
            permissionAlert = PermissionAlert(
                title: "Microphone Access Needed",
                message: "Allow microphone access to dictate messages to your coach."
            )
            return
        }

        let speechAllowed = await requestSpeechPermission()
        guard speechAllowed else {
            permissionAlert = PermissionAlert(
                title: "Speech Recognition Needed",
                message: "Allow speech recognition so FIT AI can convert your voice into text."
            )
            return
        }

        do {
            try startListening()
        } catch {
            cleanupSession()
            state = .idle
            permissionAlert = PermissionAlert(
                title: "Dictation Unavailable",
                message: "Could not start dictation right now. Please try again."
            )
        }
    }

    func cancel() {
        cleanupSession()
        state = .idle
        Haptics.light()
    }

    func stopAndTranscribe() async -> String? {
        guard state == .listening else { return nil }
        state = .finalizing
        stopMeterTimer()
        stopListening()
        try? await Task.sleep(nanoseconds: 350_000_000)

        let transcript = latestTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        cleanupSession()
        state = .idle
        return transcript.isEmpty ? nil : transcript
    }

    private func startListening() throws {
        guard let recognizer = SFSpeechRecognizer(locale: Locale.current)
            ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US")),
            recognizer.isAvailable else {
            throw NSError(domain: "CoachDictation", code: 1)
        }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
        try session.setActive(true, options: [.notifyOthersOnDeactivation])

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            self.recognitionRequest?.append(buffer)
            let level = Self.normalizePower(from: buffer)
            Task { @MainActor in
                self.pushWaveSample(level)
            }
        }
        inputTapInstalled = true

        audioEngine.prepare()
        try audioEngine.start()

        speechRecognizer = recognizer
        recognitionRequest = request
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            Task { @MainActor in
                if let result {
                    let transcript = result.bestTranscription.formattedString
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    self.latestTranscript = transcript
                    self.liveTranscript = transcript
                }
                if error != nil, self.state == .listening {
                    self.cleanupSession()
                    self.state = .idle
                }
            }
        }

        latestTranscript = ""
        liveTranscript = ""
        elapsed = 0
        startedAt = Date()
        waveformSamples = Array(repeating: 0.12, count: 34)
        state = .listening
        startMeterTimer()
    }

    private func startMeterTimer() {
        stopMeterTimer()
        meterTimer = Timer.scheduledTimer(timeInterval: 1.0 / 30.0, target: self, selector: #selector(handleMeterTick), userInfo: nil, repeats: true)
        RunLoop.main.add(meterTimer!, forMode: .common)
    }

    @objc private func handleMeterTick() {
        guard (state == .listening || state == .finalizing), let startedAt else { return }
        elapsed = Date().timeIntervalSince(startedAt)
    }

    private func stopMeterTimer() {
        meterTimer?.invalidate()
        meterTimer = nil
    }

    private func stopListening() {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        if inputTapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            inputTapInstalled = false
        }
        recognitionRequest?.endAudio()
    }

    private func cleanupSession() {
        stopMeterTimer()
        stopListening()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        speechRecognizer = nil
        startedAt = nil
        elapsed = 0
        latestTranscript = ""
        liveTranscript = ""
        waveformSamples = Array(repeating: 0.12, count: 34)
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        } catch { }
    }

    private func requestMicrophonePermission() async -> Bool {
        return await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { allowed in
                continuation.resume(returning: allowed)
            }
        }
    }

    private func requestSpeechPermission() async -> Bool {
        let existing = SFSpeechRecognizer.authorizationStatus()
        if existing == .authorized {
            return true
        }
        if existing != .notDetermined {
            return false
        }
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    private func pushWaveSample(_ normalized: CGFloat) {
        let bar = CGFloat(0.12 + normalized * 0.88)
        var next = waveformSamples
        next.append(bar)
        if next.count > 48 {
            next.removeFirst(next.count - 48)
        }
        if next.count < 34 {
            next = Array(repeating: 0.12, count: 34 - next.count) + next
        } else if next.count > 34 {
            next = Array(next.suffix(34))
        }

        withAnimation(.linear(duration: 0.08)) {
            waveformSamples = next
        }
    }

    private static func normalizePower(from buffer: AVAudioPCMBuffer) -> CGFloat {
        CGFloat(AudioLevelMeter.normalizedLevel(from: buffer))
    }
}

private struct CoachWaveformBars: View {
    let samples: [CGFloat]
    let barColor: Color

    var body: some View {
        GeometryReader { proxy in
            let count = max(1, samples.count)
            let spacing: CGFloat = 2
            let totalSpacing = spacing * CGFloat(max(0, count - 1))
            let barWidth = max(2, (proxy.size.width - totalSpacing) / CGFloat(count))
            let maxHeight = max(2, proxy.size.height)

            HStack(alignment: .center, spacing: spacing) {
                ForEach(Array(samples.enumerated()), id: \.offset) { _, value in
                    let height = max(2, min(maxHeight, maxHeight * value))
                    RoundedRectangle(cornerRadius: barWidth / 2, style: .continuous)
                        .fill(barColor)
                        .frame(width: barWidth, height: height)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .center)
        }
    }
}

private struct CoachTypingDots: View {
    let color: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { index in
                    let phase = t * 4.0 + Double(index) * 0.65
                    let v = (sin(phase) + 1) / 2 // 0...1
                    Circle()
                        .fill(color)
                        .frame(width: 8, height: 8)
                        .scaleEffect(0.85 + 0.25 * v)
                        .opacity(0.45 + 0.55 * v)
                        .offset(y: -3 * v)
                }
            }
        }
    }
}

private struct CoachStatusBanner: View {
    let title: String
    let showRetry: Bool
    let onRetry: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(FitFont.body(size: 14))
                    .foregroundColor(FitTheme.textPrimary)
            }

            Spacer()

            if showRetry {
                Button(action: onRetry) {
                    Text("Retry")
                        .font(FitFont.body(size: 14, weight: .semibold))
                        .foregroundColor(FitTheme.buttonText)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 16)
                        .background(FitTheme.primaryGradient)
                        .clipShape(Capsule())
                        .shadow(color: FitTheme.buttonShadow, radius: 8, x: 0, y: 6)
                }
            }
        }
        .padding(12)
        .background(FitTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(FitTheme.cardStroke, lineWidth: 1)
        )
    }
}

private struct CoachThreadListView: View {
    let threads: [ChatThread]
    let activeThreadId: String?
    let onSelect: (ChatThread) -> Void
    let onCreate: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                FitTheme.backgroundGradient
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Button(action: onCreate) {
                            HStack {
                                Text("New Thread")
                                    .font(FitFont.body(size: 16, weight: .semibold))
                                    .foregroundColor(FitTheme.buttonText)
                                Spacer()
                                Image(systemName: "plus")
                                    .foregroundColor(FitTheme.buttonText)
                            }
                            .padding(14)
                            .background(FitTheme.primaryGradient)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .shadow(color: FitTheme.buttonShadow, radius: 12, x: 0, y: 8)
                        }

                        ForEach(threads) { thread in
                            Button(action: {
                                onSelect(thread)
                                dismiss()
                            }) {
                                CoachThreadRow(thread: thread, isActive: thread.id == activeThreadId)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("Chat history")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(FitTheme.textPrimary)
                }
            }
        }
        .tint(FitTheme.accent)
    }
}

private struct CoachThreadRow: View {
    let thread: ChatThread
    let isActive: Bool

    private var subtitle: String {
        if let last = thread.lastMessageAt, last.count >= 10 {
            let datePrefix = String(last.prefix(10))
            return "Last active \(datePrefix)"
        }
        return "Ready for a new question"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(thread.title?.isEmpty == false ? thread.title ?? "" : "AI Coach")
                    .font(FitFont.body(size: 18))
                    .foregroundColor(FitTheme.textPrimary)

                Text(subtitle)
                    .font(FitFont.body(size: 13))
                    .foregroundColor(FitTheme.textSecondary)
            }

            Spacer()

            if isActive {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(FitTheme.accent)
            } else {
                Image(systemName: "chevron.right")
                    .font(FitFont.body(size: 12, weight: .semibold))
                    .foregroundColor(FitTheme.textSecondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isActive ? FitTheme.cardHighlight : FitTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(FitTheme.cardStroke, lineWidth: 1)
        )
    }
}

#Preview {
    CoachChatView(userId: "demo-user")
        .environmentObject(GuidedTourCoordinator())
}
