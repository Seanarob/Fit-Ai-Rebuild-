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
                    CoachThreadHeader(thread: viewModel.activeThread, isLoading: viewModel.isLoading)

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

                                ForEach(viewModel.messages) { message in
                                    CoachMessageRow(message: message)
                                        .id(message.id)
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
                    }

                    if let status = viewModel.statusMessage {
                        CoachStatusBanner(
                            title: status,
                            showRetry: viewModel.pendingRetry != nil,
                            onRetry: { Task { await viewModel.retryLastMessage() } }
                        )
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
            .navigationTitle("Coach")
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
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("History") { showingThreads = true }
                        .foregroundColor(FitTheme.textPrimary)
                }
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
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo(lastId, anchor: .bottom)
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
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                CoachCharacterView(size: 88, showBackground: false, pose: .talking)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Talk to your AI coach")
                        .font(FitFont.heading(size: 22))
                        .foregroundColor(FitTheme.textPrimary)
                    Text("Ask anything about workouts, nutrition, or recovery.")
                        .font(FitFont.body(size: 13))
                        .foregroundColor(FitTheme.textSecondary)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Try asking:")
                    .font(FitFont.body(size: 13))
                    .foregroundColor(FitTheme.textSecondary)

                ForEach(prompts, id: \.self) { prompt in
                    Button(action: { onPrompt(prompt) }) {
                        HStack {
                            Text(prompt)
                                .font(FitFont.body(size: 14))
                                .foregroundColor(FitTheme.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .foregroundColor(FitTheme.textSecondary)
                        }
                        .padding(12)
                        .background(FitTheme.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(FitTheme.cardStroke, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            Button(action: onHistory) {
                Text("View past chats")
                    .font(FitFont.body(size: 13))
                    .foregroundColor(FitTheme.accent)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
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

    let userId: String

    init(userId: String) {
        self.userId = userId
    }

    func loadInitialThread() async {
        guard !userId.isEmpty else { return }
        isLoading = true
        do {
            let fetched = try await ChatAPIService.shared.fetchThreads(userId: userId)
            threads = fetched.sorted { threadDate($0) > threadDate($1) }
            if let latest = threads.first {
                await selectThread(latest)
            } else {
                await startNewSession()
            }
        } catch {
            statusMessage = "Unable to load coach threads."
        }
        isLoading = false
    }

    func selectThread(_ thread: ChatThread) async {
        guard !userId.isEmpty else { return }
        isLoading = true
        activeThread = thread
        do {
            let detail = try await ChatAPIService.shared.fetchThreadDetail(
                userId: userId,
                threadId: thread.id
            )
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
            if startEmpty {
                activeThread = thread
                messages = []
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

        let userMessage = CoachChatMessage(
            id: UUID().uuidString,
            role: .user,
            text: text
        )
        messages.append(userMessage)

        let assistantId = UUID().uuidString
        messages.append(CoachChatMessage(id: assistantId, role: .assistant, text: ""))
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
        } catch {
            messages.removeAll { $0.id == assistantId }
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
}

struct CoachChatMessage: Identifiable {
    let id: String
    let role: CoachMessageRole
    var text: String
}

enum CoachMessageRole: String {
    case user
    case assistant
    case system
}

private struct CoachThreadHeader: View {
    let thread: ChatThread?
    let isLoading: Bool

    private var title: String {
        if let title = thread?.title, !title.isEmpty {
            return title
        }
        return "AI Coach"
    }

    private var subtitle: String {
        if isLoading {
            return "Syncing your context..."
        }
        return "Quick answers on workouts, food, and recovery."
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(FitFont.heading(size: 24))
                    .foregroundColor(FitTheme.textPrimary)

                Text(subtitle)
                    .font(FitFont.body(size: 14))
                    .foregroundColor(FitTheme.textSecondary)
            }

            Spacer(minLength: 0)

            CoachCharacterView(size: 68, showBackground: false, pose: .neutral)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }
}

private struct CoachMessageRow: View {
    let message: CoachChatMessage

    private var isUser: Bool { message.role == .user }

    var body: some View {
        if message.text.isEmpty {
            EmptyView()
        } else {
            HStack {
                if isUser { Spacer(minLength: 40) }

                Text(message.text)
                    .font(FitFont.body(size: 15))
                    .foregroundColor(isUser ? FitTheme.buttonText : FitTheme.textPrimary)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 14)
                    .background(isUser ? FitTheme.accent : FitTheme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(isUser ? FitTheme.accent : FitTheme.cardStroke, lineWidth: 1)
                    )

                if !isUser { Spacer(minLength: 40) }
            }
            .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
            .padding(.horizontal, 6)
        }
    }
}

private struct CoachTypingRow: View {
    var body: some View {
        HStack {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(FitTheme.textSecondary)
            Text("Coach is typing...")
                .font(FitFont.body(size: 14))
                .foregroundColor(FitTheme.textSecondary)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
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
                .padding(.vertical, 10)
                .padding(.horizontal, 14)
                .background(FitTheme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(FitTheme.cardStroke, lineWidth: 1)
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
                    }
                }

            Button(action: { isFocused = false }) {
                Image(systemName: "keyboard.chevron.compact.down")
                    .font(FitFont.body(size: 14, weight: .semibold))
                    .foregroundColor(FitTheme.textSecondary)
                    .padding(10)
                    .background(FitTheme.cardBackground)
                    .clipShape(Circle())
            }

            Button(action: onSend) {
                Image(systemName: "paperplane.fill")
                    .font(FitFont.body(size: 16, weight: .semibold))
                    .foregroundColor(FitTheme.buttonText)
                    .padding(12)
                    .background(
                        Group {
                            if isSending {
                                FitTheme.cardHighlight
                            } else {
                                FitTheme.primaryGradient
                            }
                        }
                    )
                    .clipShape(Circle())
            }
            .disabled(isSending || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(12)
        .background(FitTheme.cardHighlight)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(FitTheme.cardStroke, lineWidth: 1)
        )
        .shadow(color: FitTheme.shadow, radius: 10, x: 0, y: 6)
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
