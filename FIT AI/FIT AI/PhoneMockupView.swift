import SwiftUI
import UIKit

private let phoneMockupAspectRatio: CGFloat = 9 / 19.5

struct PhoneMockupView: View {
    @Environment(\.colorScheme) private var colorScheme

    let image: Image
    var cornerRadius: CGFloat
    var bezelWidth: CGFloat
    var showNotch: Bool
    var shadow: Bool

    init(
        image: Image,
        cornerRadius: CGFloat = 54,
        bezelWidth: CGFloat = 12,
        showNotch: Bool = true,
        shadow: Bool = true
    ) {
        self.image = image
        self.cornerRadius = cornerRadius
        self.bezelWidth = bezelWidth
        self.showNotch = showNotch
        self.shadow = shadow
    }

    init(
        uiImage: UIImage,
        cornerRadius: CGFloat = 54,
        bezelWidth: CGFloat = 12,
        showNotch: Bool = true,
        shadow: Bool = true
    ) {
        self.init(
            image: Image(uiImage: uiImage),
            cornerRadius: cornerRadius,
            bezelWidth: bezelWidth,
            showNotch: showNotch,
            shadow: shadow
        )
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let minSide = min(size.width, size.height)

            let effectiveCornerRadius = min(cornerRadius, minSide * 0.22)
            let effectiveBezelWidth = min(bezelWidth, minSide * 0.065)
            let screenCornerRadius = max(0, effectiveCornerRadius - effectiveBezelWidth)

            ZStack {
                RoundedRectangle(cornerRadius: effectiveCornerRadius, style: .continuous)
                    .fill(deviceFill)

                screen(cornerRadius: screenCornerRadius)
                    .padding(effectiveBezelWidth)

                RoundedRectangle(cornerRadius: effectiveCornerRadius, style: .continuous)
                    .strokeBorder(deviceStroke, lineWidth: 1)

                RoundedRectangle(cornerRadius: effectiveCornerRadius, style: .continuous)
                    .strokeBorder(
                        Color.black.opacity(colorScheme == .dark ? 0.70 : 0.35),
                        lineWidth: 0.5
                    )
                    .blendMode(.overlay)
            }
            .compositingGroup()
            .shadow(
                color: shadow ? shadowColor : .clear,
                radius: shadow ? 18 : 0,
                x: 0,
                y: shadow ? 12 : 0
            )
        }
        .aspectRatio(phoneMockupAspectRatio, contentMode: .fit)
        .accessibilityHidden(true)
    }

    private var deviceFill: LinearGradient {
        let top = colorScheme == .dark ? Color(white: 0.16) : Color(white: 0.14)
        let mid = colorScheme == .dark ? Color(white: 0.07) : Color(white: 0.09)
        let bottom = colorScheme == .dark ? Color(white: 0.02) : Color(white: 0.04)

        return LinearGradient(
            colors: [top, mid, bottom],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var deviceStroke: LinearGradient {
        let a = Color.white.opacity(colorScheme == .dark ? 0.22 : 0.30)
        let b = Color.white.opacity(colorScheme == .dark ? 0.08 : 0.10)

        return LinearGradient(
            colors: [a, b, .clear],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var shadowColor: Color {
        colorScheme == .dark ? Color.black.opacity(0.70) : Color.black.opacity(0.22)
    }

    private func screen(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.black)
            .overlay(
                image
                    .resizable()
                    .scaledToFill()
                    .clipped()
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        Color.white.opacity(colorScheme == .dark ? 0.08 : 0.06),
                        lineWidth: 1
                    )
            )
            .overlay(alignment: .top) {
                if showNotch {
                    GeometryReader { proxy in
                        let width = proxy.size.width
                        let height = proxy.size.height

                        let islandWidth = min(max(width * 0.38, 90), 140)
                        let islandHeight = min(max(width * 0.05, 10), 16)
                        let topPadding = max(height * 0.02, 10)

                        Capsule()
                            .fill(Color.black.opacity(0.92))
                            .frame(width: islandWidth, height: islandHeight)
                            .padding(.top, topPadding)
                            .frame(maxWidth: .infinity, alignment: .top)
                            .shadow(
                                color: Color.black.opacity(colorScheme == .dark ? 0.45 : 0.25),
                                radius: 4,
                                x: 0,
                                y: 1
                            )
                    }
                }
            }
    }
}

struct PhoneMockupContainerView<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    var cornerRadius: CGFloat
    var bezelWidth: CGFloat
    var showNotch: Bool
    var shadow: Bool
    let content: Content

    init(
        cornerRadius: CGFloat = 54,
        bezelWidth: CGFloat = 12,
        showNotch: Bool = true,
        shadow: Bool = true,
        @ViewBuilder content: () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.bezelWidth = bezelWidth
        self.showNotch = showNotch
        self.shadow = shadow
        self.content = content()
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let minSide = min(size.width, size.height)

            let effectiveCornerRadius = min(cornerRadius, minSide * 0.22)
            let effectiveBezelWidth = min(bezelWidth, minSide * 0.065)
            let screenCornerRadius = max(0, effectiveCornerRadius - effectiveBezelWidth)

            ZStack {
                RoundedRectangle(cornerRadius: effectiveCornerRadius, style: .continuous)
                    .fill(deviceFill)

                screen(cornerRadius: screenCornerRadius)
                    .padding(effectiveBezelWidth)

                RoundedRectangle(cornerRadius: effectiveCornerRadius, style: .continuous)
                    .strokeBorder(deviceStroke, lineWidth: 1)

                RoundedRectangle(cornerRadius: effectiveCornerRadius, style: .continuous)
                    .strokeBorder(
                        Color.black.opacity(colorScheme == .dark ? 0.70 : 0.35),
                        lineWidth: 0.5
                    )
                    .blendMode(.overlay)
            }
            .compositingGroup()
            .shadow(
                color: shadow ? shadowColor : .clear,
                radius: shadow ? 18 : 0,
                x: 0,
                y: shadow ? 12 : 0
            )
        }
        .aspectRatio(phoneMockupAspectRatio, contentMode: .fit)
        .accessibilityHidden(true)
    }

    private var deviceFill: LinearGradient {
        let top = colorScheme == .dark ? Color(white: 0.16) : Color(white: 0.14)
        let mid = colorScheme == .dark ? Color(white: 0.07) : Color(white: 0.09)
        let bottom = colorScheme == .dark ? Color(white: 0.02) : Color(white: 0.04)

        return LinearGradient(
            colors: [top, mid, bottom],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var deviceStroke: LinearGradient {
        let a = Color.white.opacity(colorScheme == .dark ? 0.22 : 0.30)
        let b = Color.white.opacity(colorScheme == .dark ? 0.08 : 0.10)

        return LinearGradient(
            colors: [a, b, .clear],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var shadowColor: Color {
        colorScheme == .dark ? Color.black.opacity(0.70) : Color.black.opacity(0.22)
    }

    private func screen(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.black)
            .overlay(
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        Color.white.opacity(colorScheme == .dark ? 0.08 : 0.06),
                        lineWidth: 1
                    )
            )
            .overlay(alignment: .top) {
                if showNotch {
                    GeometryReader { proxy in
                        let width = proxy.size.width
                        let height = proxy.size.height

                        let islandWidth = min(max(width * 0.38, 90), 140)
                        let islandHeight = min(max(width * 0.05, 10), 16)
                        let topPadding = max(height * 0.02, 10)

                        Capsule()
                            .fill(Color.black.opacity(0.92))
                            .frame(width: islandWidth, height: islandHeight)
                            .padding(.top, topPadding)
                            .frame(maxWidth: .infinity, alignment: .top)
                            .shadow(
                                color: Color.black.opacity(colorScheme == .dark ? 0.45 : 0.25),
                                radius: 4,
                                x: 0,
                                y: 1
                            )
                    }
                }
            }
    }
}

#Preview("PhoneMockupView") {
    VStack {
        PhoneMockupView(image: Image("OnboardingFeatureCoach"))
            .frame(maxWidth: 260)
    }
    .padding()
    .background(Color(white: 0.96))
}
