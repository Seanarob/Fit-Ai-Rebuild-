import SwiftUI
import UIKit

struct VoiceLogDictationView: View {
    @ObservedObject var viewModel: VoiceLogFlowViewModel
    let onCancel: () -> Void
    
    @State private var didStartOnce = false
    
    var body: some View {
        ZStack {
            VoiceLogTokens.Color.background
                .ignoresSafeArea()
            
            VStack(alignment: .leading, spacing: VoiceLogTokens.Spacing.lg) {
                header
                
                if viewModel.permissionState == .denied {
                    VoiceLogPermissionHelpView()
                    Button {
                        viewModel.cancelListening()
                        onCancel()
                    } label: {
                        Text("Close")
                            .font(VoiceLogTokens.Typography.body(15, weight: .semibold))
                            .foregroundColor(VoiceLogTokens.Color.textPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(VoiceLogTokens.Color.card)
                            .clipShape(RoundedRectangle(cornerRadius: VoiceLogTokens.Radius.md))
                            .overlay(
                                RoundedRectangle(cornerRadius: VoiceLogTokens.Radius.md)
                                    .stroke(VoiceLogTokens.Color.stroke, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                } else {
                    dictationCard
                    controls
                }
                
                Spacer(minLength: 0)
            }
            .padding(20)
        }
        .task {
            guard !didStartOnce else { return }
            didStartOnce = true
            await viewModel.startListening()
        }
    }
    
    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Voice Log")
                .font(VoiceLogTokens.Typography.title(20))
                .foregroundColor(VoiceLogTokens.Color.textPrimary)
            
            Text("Speak your meal. We'll parse it into foods and macros.")
                .font(VoiceLogTokens.Typography.body(12))
                .foregroundColor(VoiceLogTokens.Color.textSecondary)
        }
    }
    
    private var dictationCard: some View {
        VStack(alignment: .leading, spacing: VoiceLogTokens.Spacing.md) {
            HStack(alignment: .center, spacing: 12) {
                VoiceLogWaveformView(level: viewModel.audioLevel)
                    .frame(height: 36)
                
                if viewModel.showTapDoneHint {
                    Text("Tap Done")
                        .font(VoiceLogTokens.Typography.body(12, weight: .semibold))
                        .foregroundColor(VoiceLogTokens.Color.textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(VoiceLogTokens.Color.card.opacity(0.65))
                        .clipShape(Capsule())
                        .overlay(
                            Capsule().stroke(VoiceLogTokens.Color.stroke, lineWidth: 1)
                        )
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
            }
            
            VStack(alignment: .leading, spacing: 10) {
                Text(viewModel.transcript.isEmpty ? "Listening…" : viewModel.transcript)
                    .font(VoiceLogTokens.Typography.body(15))
                    .foregroundColor(VoiceLogTokens.Color.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(VoiceLogTokens.Color.card.opacity(0.85))
                    .clipShape(RoundedRectangle(cornerRadius: VoiceLogTokens.Radius.md))
                    .overlay(
                        RoundedRectangle(cornerRadius: VoiceLogTokens.Radius.md)
                            .stroke(VoiceLogTokens.Color.stroke, lineWidth: 1)
                    )
                
                if let inlineError = viewModel.inlineErrorMessage {
                    Text(inlineError)
                        .font(VoiceLogTokens.Typography.body(12))
                        .foregroundColor(VoiceLogTokens.Color.textSecondary)
                        .transition(.opacity)
                }
            }
        }
        .padding(14)
        .background(VoiceLogTokens.Color.card)
        .clipShape(RoundedRectangle(cornerRadius: VoiceLogTokens.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: VoiceLogTokens.Radius.lg)
                .stroke(VoiceLogTokens.Color.stroke, lineWidth: 1)
        )
    }
    
    private var controls: some View {
        HStack(spacing: 12) {
            Button {
                viewModel.cancelListening()
                onCancel()
            } label: {
                Text("Cancel")
                    .font(VoiceLogTokens.Typography.body(15, weight: .semibold))
                    .foregroundColor(VoiceLogTokens.Color.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(VoiceLogTokens.Color.card)
                    .clipShape(RoundedRectangle(cornerRadius: VoiceLogTokens.Radius.md))
                    .overlay(
                        RoundedRectangle(cornerRadius: VoiceLogTokens.Radius.md)
                            .stroke(VoiceLogTokens.Color.stroke, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            
            Button {
                Task { await viewModel.doneListeningAndAnalyze() }
            } label: {
                Text("Done")
                    .font(VoiceLogTokens.Typography.body(15, weight: .semibold))
                    .foregroundColor(FitTheme.textOnAccent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(FitTheme.primaryGradient)
                    .clipShape(RoundedRectangle(cornerRadius: VoiceLogTokens.Radius.md))
                    .shadow(color: FitTheme.buttonShadow, radius: 10, x: 0, y: 6)
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 2)
    }
}

private struct VoiceLogWaveformView: View {
    let level: Float
    private let barCount = 14
    
    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(0..<barCount, id: \.self) { idx in
                Capsule()
                    .fill(VoiceLogTokens.Color.accent)
                    .frame(width: 3, height: barHeight(for: idx))
            }
        }
        .animation(.easeOut(duration: 0.12), value: level)
        .accessibilityLabel("Waveform")
    }
    
    private func barHeight(for idx: Int) -> CGFloat {
        let base = CGFloat(max(level, 0.02))
        let weight = CGFloat(0.55 + (Double(idx).truncatingRemainder(dividingBy: 5) * 0.12))
        return max(4, min(36, base * 36 * weight))
    }
}

private struct VoiceLogPermissionHelpView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Permissions needed", systemImage: "exclamationmark.triangle.fill")
                .font(VoiceLogTokens.Typography.body(14, weight: .semibold))
                .foregroundColor(VoiceLogTokens.Color.textPrimary)
            
            Text("Enable Microphone and Speech Recognition to use Voice Log.")
                .font(VoiceLogTokens.Typography.body(12))
                .foregroundColor(VoiceLogTokens.Color.textSecondary)
            
            Button {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(url)
            } label: {
                Text("Enable in Settings")
                    .font(VoiceLogTokens.Typography.body(14, weight: .semibold))
                    .foregroundColor(FitTheme.textOnAccent)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background(FitTheme.primaryGradient)
                    .clipShape(RoundedRectangle(cornerRadius: VoiceLogTokens.Radius.md))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(VoiceLogTokens.Color.card)
        .clipShape(RoundedRectangle(cornerRadius: VoiceLogTokens.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: VoiceLogTokens.Radius.lg)
                .stroke(VoiceLogTokens.Color.stroke, lineWidth: 1)
        )
    }
}

#Preview("Dictation (Mock)") {
    let vm = VoiceLogFlowViewModel(
        userId: "preview",
        mealType: .breakfast,
        logDate: Date(),
        apiClient: MockMealAPIClient()
    )
    vm.permissionState = .authorized
    vm.transcript = "Two eggs, one slice of toast, and a black coffee."
    vm.showTapDoneHint = true
    
    return VoiceLogDictationView(viewModel: vm, onCancel: {})
}
