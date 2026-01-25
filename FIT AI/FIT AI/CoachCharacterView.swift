import SwiftUI
import UIKit
import Combine

enum CoachPose: String {
    case idle = "CoachIdle"
    case talking = "CoachTalking"
    case thinking = "CoachThinking"
    case celebration = "CoachCelebration"
    case neutral = "CoachNeutral"

    var assetBaseName: String { rawValue }
}

struct CoachArtView: View {
    let pose: CoachPose
    var blink: Bool = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { proxy in
            if let image = CoachArtAsset.image(for: pose, colorScheme: colorScheme) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: proxy.size.width, height: proxy.size.height)
            } else {
                CoachIllustration(blink: blink)
            }
        }
    }
}

private enum CoachArtAsset {
    static func image(for pose: CoachPose, colorScheme: ColorScheme) -> UIImage? {
        let base = pose.assetBaseName
        let trait = UITraitCollection(userInterfaceStyle: colorScheme == .dark ? .dark : .light)

        if let image = UIImage(named: base, in: .main, compatibleWith: trait) {
            return image
        }

        let variant = colorScheme == .dark ? "\(base)Dark" : "\(base)Light"
        return UIImage(named: variant, in: .main, compatibleWith: trait)
    }
}

struct CoachCharacterView: View {
    var size: CGFloat = 140
    var showBackground: Bool = true
    var pose: CoachPose = .idle
    @State private var isAnimating = false
    @State private var isBlinking = false
    private let blinkTimer = Timer.publish(every: 4.6, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            if showBackground {
                CoachDotBackground()
                    .opacity(0.5)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.2, style: .continuous))
            }

            CoachArtView(pose: pose, blink: isBlinking)
                .scaleEffect(isAnimating ? 1.03 : 0.97)
                .rotationEffect(.degrees(isAnimating ? 1.2 : -1.2))
                .shadow(color: FitTheme.shadow.opacity(0.5), radius: 10, x: 0, y: 6)
        }
        .frame(width: size, height: size)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
        }
        .onReceive(blinkTimer) { _ in
            withAnimation(.easeInOut(duration: 0.12)) {
                isBlinking = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                withAnimation(.easeInOut(duration: 0.12)) {
                    isBlinking = false
                }
            }
        }
    }
}

struct CoachCornerPeek: View {
    var alignment: Alignment = .bottomTrailing
    var title: String = "Coach"
    var pose: CoachPose = .neutral

    var body: some View {
        ZStack(alignment: alignment) {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(FitTheme.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .stroke(FitTheme.cardStroke, lineWidth: 1)
                )

            VStack(alignment: alignment == .bottomTrailing ? .leading : .trailing, spacing: 4) {
                Text(title)
                    .font(FitFont.body(size: 13))
                    .foregroundColor(FitTheme.textSecondary)
                Text("Hey")
                    .font(FitFont.heading(size: 18))
                    .foregroundColor(FitTheme.textPrimary)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment == .bottomTrailing ? .bottomLeading : .bottomTrailing)

            CoachCharacterView(size: 108, showBackground: false, pose: pose)
                .offset(x: alignment == .bottomTrailing ? 26 : -26, y: 22)
        }
        .frame(width: 180, height: 130)
        .shadow(color: FitTheme.shadow, radius: 12, x: 0, y: 8)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
    }
}

private struct CoachDotBackground: View {
    var body: some View {
        GeometryReader { _ in
            Canvas { context, size in
                let dotSize: CGFloat = 2
                let spacing: CGFloat = 16
                let color = FitTheme.cardStroke.opacity(0.35)

                for x in stride(from: 0, through: size.width, by: spacing) {
                    for y in stride(from: 0, through: size.height, by: spacing) {
                        let rect = CGRect(x: x, y: y, width: dotSize, height: dotSize)
                        context.fill(Path(ellipseIn: rect), with: .color(color))
                    }
                }
            }
        }
    }
}

private struct CoachIllustration: View {
    let blink: Bool
    private let shell = Color(red: 0.91, green: 0.92, blue: 0.96)
    private let shellShadow = Color(red: 0.78, green: 0.80, blue: 0.88)
    private let visorDark = Color(red: 0.16, green: 0.18, blue: 0.28)
    private let visorLight = Color(red: 0.24, green: 0.26, blue: 0.38)
    private let glow = Color(red: 0.34, green: 0.84, blue: 0.88)
    private let accent = Color(red: 0.40, green: 0.55, blue: 0.95)

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let headWidth = min(width * 0.62, height * 0.55)
            let headHeight = headWidth * 0.7
            let bodyWidth = headWidth * 0.85
            let bodyHeight = headWidth * 0.78
            let eyeSize = headWidth * 0.18
            let legHeight = headWidth * 0.28

            VStack(spacing: headWidth * 0.08) {
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [glow.opacity(0.35), Color.clear],
                                center: .center,
                                startRadius: 10,
                                endRadius: headWidth * 0.65
                            )
                        )
                        .frame(width: headWidth * 1.3, height: headWidth * 1.3)

                    VStack(spacing: -headWidth * 0.08) {
                        Capsule()
                            .fill(accent)
                            .frame(width: headWidth * 0.08, height: headWidth * 0.18)
                        Circle()
                            .fill(glow)
                            .frame(width: headWidth * 0.12, height: headWidth * 0.12)
                            .shadow(color: glow.opacity(0.45), radius: 6, x: 0, y: 2)
                    }
                    .offset(y: -headHeight * 0.72)

                    RoundedRectangle(cornerRadius: headWidth * 0.2, style: .continuous)
                        .fill(shell)
                        .overlay(
                            RoundedRectangle(cornerRadius: headWidth * 0.2, style: .continuous)
                                .stroke(shellShadow, lineWidth: 2)
                        )
                        .frame(width: headWidth, height: headHeight)

                    RoundedRectangle(cornerRadius: headWidth * 0.18, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [visorDark, visorLight],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: headWidth * 0.82, height: headHeight * 0.52)

                    HStack(spacing: headWidth * 0.14) {
                        Circle()
                            .fill(glow)
                            .frame(width: eyeSize, height: eyeSize)
                            .scaleEffect(x: 1, y: blink ? 0.12 : 1, anchor: .center)
                            .overlay(
                                Circle()
                                    .fill(Color.white.opacity(0.4))
                                    .frame(width: eyeSize * 0.45, height: eyeSize * 0.45)
                                    .offset(x: eyeSize * 0.16, y: -eyeSize * 0.12)
                            )
                        Circle()
                            .fill(glow)
                            .frame(width: eyeSize, height: eyeSize)
                            .scaleEffect(x: 1, y: blink ? 0.12 : 1, anchor: .center)
                            .overlay(
                                Circle()
                                    .fill(Color.white.opacity(0.4))
                                    .frame(width: eyeSize * 0.45, height: eyeSize * 0.45)
                                    .offset(x: eyeSize * 0.16, y: -eyeSize * 0.12)
                            )
                    }
                    .offset(y: -headHeight * 0.02)
                }

                ZStack {
                    HStack(spacing: bodyWidth * 0.86) {
                        Capsule()
                            .fill(shellShadow)
                            .frame(width: bodyWidth * 0.18, height: bodyHeight * 0.16)
                            .rotationEffect(.degrees(-12))
                        Capsule()
                            .fill(shellShadow)
                            .frame(width: bodyWidth * 0.18, height: bodyHeight * 0.16)
                            .rotationEffect(.degrees(12))
                    }

                    RoundedRectangle(cornerRadius: bodyWidth * 0.2, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [shell, shellShadow.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: bodyWidth, height: bodyHeight)

                    RoundedRectangle(cornerRadius: bodyWidth * 0.18, style: .continuous)
                        .fill(glow.opacity(0.3))
                        .frame(width: bodyWidth * 0.54, height: bodyHeight * 0.24)
                        .overlay(
                            RoundedRectangle(cornerRadius: bodyWidth * 0.18, style: .continuous)
                                .stroke(glow.opacity(0.7), lineWidth: 1)
                        )
                        .offset(y: bodyHeight * 0.18)

                    Circle()
                        .fill(accent)
                        .frame(width: bodyWidth * 0.16, height: bodyWidth * 0.16)
                        .overlay(
                            Circle()
                                .fill(glow)
                                .frame(width: bodyWidth * 0.08, height: bodyWidth * 0.08)
                        )
                        .offset(x: bodyWidth * 0.34, y: -bodyHeight * 0.2)
                }

                HStack(spacing: bodyWidth * 0.22) {
                    Capsule()
                        .fill(shellShadow)
                        .frame(width: bodyWidth * 0.2, height: legHeight)
                        .overlay(
                            RoundedRectangle(cornerRadius: bodyWidth * 0.08, style: .continuous)
                                .fill(glow)
                                .frame(width: bodyWidth * 0.12, height: legHeight * 0.24)
                                .offset(y: legHeight * 0.26)
                        )
                    Capsule()
                        .fill(shellShadow)
                        .frame(width: bodyWidth * 0.2, height: legHeight)
                        .overlay(
                            RoundedRectangle(cornerRadius: bodyWidth * 0.08, style: .continuous)
                                .fill(glow)
                                .frame(width: bodyWidth * 0.12, height: legHeight * 0.24)
                                .offset(y: legHeight * 0.26)
                        )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.top, headWidth * 0.12)
        }
    }
}
