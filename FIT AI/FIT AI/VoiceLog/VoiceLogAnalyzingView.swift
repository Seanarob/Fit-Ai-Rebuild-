import SwiftUI

struct VoiceLogAnalyzingView: View {
    @ObservedObject var viewModel: VoiceLogFlowViewModel
    
    @State private var labelIndex: Int = 0
    @State private var labelTask: Task<Void, Never>?
    
    private let labels = [
        "Transcribing",
        "Identifying foods",
        "Calculating macros",
    ]
    
    var body: some View {
        ZStack {
            VoiceLogTokens.Color.background
                .ignoresSafeArea()
            
            VStack(spacing: 18) {
                Spacer(minLength: 0)
                
                ProgressView()
                    .tint(VoiceLogTokens.Color.accent)
                    .scaleEffect(1.2)
                
                Text("Analyzing your meal…")
                    .font(VoiceLogTokens.Typography.title(18))
                    .foregroundColor(VoiceLogTokens.Color.textPrimary)
                
                Text(currentProgressLabel)
                    .font(VoiceLogTokens.Typography.body(13, weight: .semibold))
                    .foregroundColor(VoiceLogTokens.Color.textSecondary)
                    .padding(.top, 2)
                
                if case .error(let message, let retryAction) = viewModel.flowState {
                    VStack(spacing: 10) {
                        Text(message)
                            .font(VoiceLogTokens.Typography.body(12))
                            .foregroundColor(VoiceLogTokens.Color.textSecondary)
                            .multilineTextAlignment(.center)
                        
                        Button("Retry") {
                            Task { await viewModel.retry(from: retryAction) }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(VoiceLogTokens.Color.accent)
                    }
                    .padding(.top, 12)
                }
                
                Spacer(minLength: 0)
            }
            .padding(20)
        }
        .onAppear {
            labelIndex = 0
            labelTask?.cancel()
            labelTask = Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                while !Task.isCancelled {
                    if case .analyzing = viewModel.flowState {
                        await MainActor.run {
                            labelIndex = (labelIndex + 1) % labels.count
                        }
                    }
                    try? await Task.sleep(nanoseconds: 700_000_000)
                }
            }
        }
        .onDisappear {
            labelTask?.cancel()
            labelTask = nil
        }
    }
    
    private var currentProgressLabel: String {
        labels[min(labelIndex, labels.count - 1)]
    }
}

#Preview("Analyzing") {
    let vm = VoiceLogFlowViewModel(
        userId: "preview",
        mealType: .lunch,
        logDate: Date(),
        apiClient: MockMealAPIClient(artificialDelayMs: 2000)
    )
    vm.flowState = .analyzing(transcript: "Two eggs and toast")
    return VoiceLogAnalyzingView(viewModel: vm)
}
