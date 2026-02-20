import SwiftUI

struct VoiceLogCoordinator: View {
    enum Route: Hashable {
        case analyzing
        case review
    }
    
    @Environment(\.dismiss) private var dismiss
    @State private var path: [Route] = []
    @StateObject private var viewModel: VoiceLogFlowViewModel
    
    init(
        userId: String,
        mealType: MealType,
        logDate: Date,
        apiClient: MealAPIClientProtocol = MealAPIClient(),
        onLogged: (() -> Void)? = nil
    ) {
        let vm = VoiceLogFlowViewModel(
            userId: userId,
            mealType: mealType,
            logDate: logDate,
            apiClient: apiClient
        )
        vm.onLogged = onLogged
        _viewModel = StateObject(wrappedValue: vm)
    }
    
    var body: some View {
        NavigationStack(path: $path) {
            VoiceLogDictationView(
                viewModel: viewModel,
                onCancel: { dismiss() }
            )
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .analyzing:
                    VoiceLogAnalyzingView(viewModel: viewModel)
                case .review:
                    VoiceLogReviewView(viewModel: viewModel, onClose: { dismiss() })
                }
            }
        }
        .onChange(of: viewModel.flowState) { newState in
            switch newState {
            case .analyzing:
                if path.last != .analyzing {
                    withAnimation(MotionTokens.springBase) {
                        path = [.analyzing]
                    }
                }
            case .review:
                if path.last != .review {
                    withAnimation(MotionTokens.springBase) {
                        path = [.review]
                    }
                }
            case .idle, .listening:
                if !path.isEmpty {
                    withAnimation(MotionTokens.springBase) { path = [] }
                }
            case .error(_, let action):
                // Keep current screen for retries.
                if action == .retryAnalyze, path.last != .analyzing {
                    withAnimation(MotionTokens.springBase) { path = [.analyzing] }
                }
                if action == .retryLog, path.last != .review {
                    withAnimation(MotionTokens.springBase) { path = [.review] }
                }
            }
        }
    }
}

#Preview("Voice Log Flow") {
    VoiceLogCoordinator(
        userId: "preview",
        mealType: .breakfast,
        logDate: Date(),
        apiClient: MockMealAPIClient()
    )
}

