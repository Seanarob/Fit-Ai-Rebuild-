import SwiftUI

struct LogActionTile: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(FitTheme.accent)
                
                Text(title)
                    .font(FitFont.body(size: 15))
                    .foregroundColor(FitTheme.textPrimary)
                
                Text(subtitle)
                    .font(FitFont.body(size: 11))
                    .foregroundColor(FitTheme.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
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

struct VoiceLogEntryView: View {
    let action: () -> Void
    
    var body: some View {
        LogActionTile(
            title: "Voice Log",
            subtitle: "Speak your meal",
            systemImage: "mic.fill",
            action: action
        )
    }
}

#Preview("Voice Log Tile") {
    ZStack {
        FitTheme.backgroundGradient.ignoresSafeArea()
        VoiceLogEntryView(action: {})
            .padding()
    }
}

