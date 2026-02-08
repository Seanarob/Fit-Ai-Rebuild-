import Combine
import Foundation
import SwiftUI
import UIKit

struct CoachChatView: View {
    let userId: String
    let showsCloseButton: Bool
    let onClose: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: CoachChatViewModel
    @State private var draftMessage = ""
    @State private var showingThreads = false
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
                    CoachThreadHeader(
                        thread: viewModel.activeThread,
                        isLoading: viewModel.isLoading,
                        showsActions: !showsCloseButton,
                        onNewChat: {
                            Task {
                                await viewModel.createThread()
                                Haptics.light()
                            }
                        },
                        onHistory: { showingThreads = true }
                    )
                    .padding(.horizontal, 20)
                    .padding(.top, 6)

                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 12) {
                                if viewModel.messages.isEmpty && !viewModel.isStreaming {
                                    CoachEmptyStateView(
                                        prompts: starterPrompts,
                                        onPrompt: { prompt in
                                            sendPrompt(prompt)
                                        },
                                        onHistory: { showingThreads = true }
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

                                if viewModel.isStreaming,
                                   let last = viewModel.messages.last,
                                   last.role == .assistant,
                                   last.text.isEmpty {
                                    CoachTypingRow()
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 10)
                        }
                        .onChange(of: viewModel.messages.count) { _ in
                            scrollToLatest(proxy: proxy)
                        }
                        .onChange(of: viewModel.isStreaming) { _ in
                            scrollToLatest(proxy: proxy)
                        }
                        .onChange(of: viewModel.workoutCard?.id) { _ in
                            scrollToLatest(proxy: proxy)
                        }
                    }

                    if let status = viewModel.statusMessage {
                        CoachStatusBanner(
                            title: status,
                            showRetry: viewModel.pendingRetry != nil,
                            onRetry: { Task { await viewModel.retryLastMessage() } }
                        )
                        .padding(.horizontal, 20)
                    }
                    
                    // New Chat button - visible when there are messages
                    if !viewModel.messages.isEmpty {
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

                    CoachInputBar(
                        text: $draftMessage,
                        isSending: viewModel.isStreaming,
                        onSend: handleSend
                    )
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
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

                            Button { showingThreads = true } label: {
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(FitTheme.textPrimary)
                            }
                        }
                    }
                }
            }
            .toolbar(showsCloseButton ? .visible : .hidden, for: .navigationBar)
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

    private func scrollToLatest(proxy: ScrollViewProxy) {
        guard let lastId = viewModel.messages.last?.id else { return }
        proxy.scrollTo(lastId, anchor: .bottom)
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
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 10))
                        .foregroundColor(FitTheme.cardCoachAccent)
                    Text("QUICK START")
                        .font(FitFont.body(size: 11, weight: .bold))
                        .foregroundColor(FitTheme.cardCoachAccent)
                        .tracking(1)
                }

                ForEach(Array(prompts.enumerated()), id: \.offset) { index, prompt in
                    Button(action: { onPrompt(prompt) }) {
                        HStack(spacing: 12) {
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
                                .fixedSize(horizontal: false, vertical: true)
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(FitTheme.textSecondary)
                        }
                        .padding(12)
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
        VStack(spacing: 16) {
            CoachCharacterView(size: 140, showBackground: false, pose: .neutral)

            VStack(spacing: 8) {
                Text("Your Personal Trainer")
                    .font(FitFont.heading(size: 24))
                    .foregroundColor(FitTheme.textPrimary)
                Text("Get personalized workout plans, form tips, nutrition advice, and recovery strategies.")
                    .font(FitFont.body(size: 14))
                    .foregroundColor(FitTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
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

    let userId: String
    private var hiddenAssistantMessageIds: Set<String> = []

    init(userId: String) {
        self.userId = userId
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

        await refreshThreads()
    }

    func selectThread(_ thread: ChatThread) async {
        guard !userId.isEmpty else { return }
        isLoading = true
        activeThread = thread
        CoachChatSession.shared.activeThreadId = thread.id
        workoutCard = nil
        hiddenAssistantMessageIds.removeAll()
        do {
            let detail = try await ChatAPIService.shared.fetchThreadDetail(
                userId: userId,
                threadId: thread.id
            )
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
            threads.insert(thread, at: 0)
            CoachChatSession.shared.activeThreadId = thread.id
            if startEmpty {
                activeThread = thread
                messages = []
                workoutCard = nil
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
        let isWorkoutRequest = Self.isWorkoutRequest(text)

        let userMessage = CoachChatMessage(
            id: UUID().uuidString,
            role: .user,
            text: text
        )
        messages.append(userMessage)

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
            ) { [weak self] chunk in
                Task { @MainActor in
                    self?.appendAssistantChunk(chunk, messageId: assistantId)
                }
            }
            await refreshThreads()
            if isWorkoutRequest {
                updateWorkoutCard(for: assistantId)
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

        isStreaming = false
    }

    func retryLastMessage() async {
        guard let retryText = pendingRetry else { return }
        pendingRetry = nil
        await sendMessage(retryText)
    }

    private func appendAssistantChunk(_ chunk: String, messageId: String) {
        guard let index = messages.lastIndex(where: { $0.id == messageId }) else { return }
        messages[index].text += chunk
    }

    private func refreshThreads() async {
        do {
            let fetched = try await ChatAPIService.shared.fetchThreads(userId: userId)
            threads = fetched.sorted { threadDate($0) > threadDate($1) }
            if let active = activeThread,
               let refreshed = threads.first(where: { $0.id == active.id }) {
                activeThread = refreshed
            }
        } catch {
            statusMessage = "Chat updated, but threads failed to refresh."
        }
    }

    private func threadDate(_ thread: ChatThread) -> Date {
        let iso = ISO8601DateFormatter()
        if let value = thread.lastMessageAt ?? thread.updatedAt,
           let date = iso.date(from: value) {
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
            return CoachChatMessage(
                id: payload.id,
                role: role,
                text: payload.content
            )
        }
        hiddenAssistantMessageIds.removeAll()
        workoutCard = nil
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

enum CoachMessageRole: String {
    case user
    case assistant
    case system
}

private struct CoachThreadHeader: View {
    let thread: ChatThread?
    let isLoading: Bool
    let showsActions: Bool
    let onNewChat: () -> Void
    let onHistory: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            CoachHeroCard()

            if showsActions {
                HStack(spacing: 12) {
                    Button(action: onNewChat) {
                        Image(systemName: "plus.message")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(FitTheme.textPrimary)
                            .padding(8)
                            .background(FitTheme.cardHighlight)
                            .clipShape(Circle())
                    }

                    Button(action: onHistory) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(FitTheme.textPrimary)
                            .padding(8)
                            .background(FitTheme.cardHighlight)
                            .clipShape(Circle())
                    }
                }
                .padding(12)
            }
        }
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
            
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(FitTheme.cardCoachAccent)
                        .frame(width: 8, height: 8)
                }
            }
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

private struct CoachInputBar: View {
    @Binding var text: String
    let isSending: Bool
    let onSend: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 12) {
            TextField("Ask your coach...", text: $text, axis: .vertical)
                .font(FitFont.body(size: 15))
                .foregroundColor(FitTheme.textPrimary)
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                .background(FitTheme.cardCoach)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(isFocused ? FitTheme.cardCoachAccent : FitTheme.cardCoachAccent.opacity(0.3), lineWidth: isFocused ? 2 : 1)
                )
                .focused($isFocused)
                .submitLabel(.send)
                .onSubmit(onSend)
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Done") {
                            isFocused = false
                        }
                        .foregroundColor(FitTheme.cardCoachAccent)
                    }
                }

            Button(action: onSend) {
                Image(systemName: isSending ? "ellipsis" : "paperplane.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(
                        Group {
                            if isSending {
                                FitTheme.cardCoachAccent.opacity(0.6)
                            } else {
                                FitTheme.cardCoachAccent
                            }
                        }
                    )
                    .clipShape(Circle())
            }
            .disabled(isSending || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(10)
        .background(FitTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(FitTheme.cardCoachAccent.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: FitTheme.cardCoachAccent.opacity(0.1), radius: 12, x: 0, y: 6)
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
}
