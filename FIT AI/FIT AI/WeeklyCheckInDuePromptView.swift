import SwiftUI

struct WeeklyCheckInDuePromptView: View {
    let isOverdue: Bool
    let statusText: String
    let onStartCheckIn: () -> Void
    let onDismiss: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    @State private var pulseAnimation = false
    
    private var accent: Color {
        isOverdue ? Color(red: 0.92, green: 0.30, blue: 0.25) : FitTheme.cardProgressAccent
    }
    
    private var titleText: String {
        isOverdue ? "Weekly check-in overdue" : "Weekly check-in due today"
    }
    
    private var subtitleText: String {
        isOverdue
            ? "Catch up now so your plan stays accurate."
            : "Log weight, photos, and adherence so your coach can adjust the week."
    }

    private var modalTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.985))
    }
    
    var body: some View {
        ZStack {
            // Dimmed backdrop
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)
            
            // Card
            VStack(spacing: 18) {
                HStack {
                    Spacer()
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(FitTheme.textSecondary)
                            .frame(width: 36, height: 36)
                            .background(FitTheme.cardBackground.opacity(0.85))
                            .clipShape(Circle())
                    }
                }
                
                VStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [accent.opacity(0.35), Color.clear],
                                    center: .center,
                                    startRadius: 0,
                                    endRadius: 80
                                )
                            )
                            .frame(width: 160, height: 160)
                            .scaleEffect(pulseAnimation ? 1.06 : 1.0)
                        
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [accent, accent.opacity(0.75)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 96, height: 96)
                            .shadow(color: accent.opacity(0.35), radius: 18, x: 0, y: 10)
                        
                        Image(systemName: isOverdue ? "exclamationmark.triangle.fill" : "calendar.badge.checkmark")
                            .font(.system(size: 42, weight: .bold))
                            .foregroundColor(.white)
                            .scaleEffect(pulseAnimation ? 1.03 : 1.0)
                    }
                    
                    VStack(spacing: 8) {
                        Text(titleText)
                            .font(FitFont.heading(size: 26))
                            .foregroundColor(FitTheme.textPrimary)
                            .multilineTextAlignment(.center)
                        
                        Text(subtitleText)
                            .font(FitFont.body(size: 14))
                            .foregroundColor(FitTheme.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 6)
                        
                        Text(statusText)
                            .font(FitFont.body(size: 13, weight: .semibold))
                            .foregroundColor(isOverdue ? accent : FitTheme.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.top, 2)
                            .contentTransition(.numericText())
                    }
                }
                
                VStack(spacing: 10) {
                    Button(action: onStartCheckIn) {
                        HStack(spacing: 10) {
                            Image(systemName: "arrow.right.circle.fill")
                                .font(.system(size: 18, weight: .semibold))
                            Text("Start check-in")
                                .font(FitFont.body(size: 16, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            LinearGradient(
                                colors: [accent, accent.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .shadow(color: accent.opacity(0.35), radius: 14, x: 0, y: 8)
                    }
                    
                    Button(action: onDismiss) {
                        Text("Not now")
                            .font(FitFont.body(size: 14))
                            .foregroundColor(FitTheme.textSecondary)
                            .underline()
                            .padding(.vertical, 6)
                    }
                }
            }
            .padding(20)
            .background(
                FitTheme.cardBackground
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(accent.opacity(0.25), lineWidth: 1.5)
            )
            .padding(.horizontal, 22)
            .transition(modalTransition)
        }
        .onAppear {
            runPulseBurst()
        }
        .onChange(of: statusText) { _ in
            runPulseBurst()
        }
    }

    private func runPulseBurst() {
        guard !reduceMotion else {
            pulseAnimation = false
            return
        }
        pulseAnimation = false
        withAnimation(.easeInOut(duration: MotionTokens.slow).repeatCount(2, autoreverses: true)) {
            pulseAnimation = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + (MotionTokens.slow * 2.2)) {
            pulseAnimation = false
        }
    }
}

#Preview {
    ZStack {
        FitTheme.backgroundGradient.ignoresSafeArea()
        WeeklyCheckInDuePromptView(
            isOverdue: false,
            statusText: "Check-in day is today!",
            onStartCheckIn: {},
            onDismiss: {}
        )
    }
}
