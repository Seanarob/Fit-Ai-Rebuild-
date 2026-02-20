import SwiftUI

struct HoloBadgeView: View {
    let image: Image
    let cornerRadius: CGFloat
    let isEarned: Bool

    @State private var touchPoint: CGPoint = CGPoint(x: 0.5, y: 0.5)
    @State private var touchAmount: CGFloat = 0.0

    init(image: Image, cornerRadius: CGFloat, isEarned: Bool = true) {
        self.image = image
        self.cornerRadius = cornerRadius
        self.isEarned = isEarned
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let touch = touchPoint
            let touching = Float(touchAmount)

            ZStack {
                image
                    .resizable()
                    .scaledToFit()
                    .saturation(isEarned ? 1.0 : 0.0)
                    .opacity(isEarned ? 1.0 : 0.65)
                    .overlay {
                        if isEarned {
                            if #available(iOS 17.0, *) {
                                let shader = HoloBadgeShader.make(
                                    size: size,
                                    touch: touch,
                                    touching: touching
                                )

                                Rectangle()
                                    .fill(Color.white)
                                    .colorEffect(shader)
                                    .blendMode(.plusLighter)
                                    .opacity(0.9)
                            } else {
                                Rectangle()
                                    .fill(Color.white.opacity(0.12))
                                    .blendMode(.plusLighter)
                                    .opacity(0.6)
                            }
                        }
                    }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .allowsHitTesting(isEarned)
            .gesture(dragGesture(in: size))
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func dragGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                touchPoint = normalizedPoint(from: value.location, in: size)
                if touchAmount < 1.0 {
                    withAnimation(.easeOut(duration: 0.12)) {
                        touchAmount = 1.0
                    }
                }
            }
            .onEnded { _ in
                withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                    touchPoint = CGPoint(x: 0.5, y: 0.5)
                }
                withAnimation(.easeOut(duration: 0.25)) {
                    touchAmount = 0.0
                }
            }
    }

    private func normalizedPoint(from location: CGPoint, in size: CGSize) -> CGPoint {
        let safeWidth = max(size.width, 1)
        let safeHeight = max(size.height, 1)
        let x = min(max(location.x / safeWidth, 0), 1)
        let y = min(max(location.y / safeHeight, 0), 1)
        return CGPoint(x: x, y: y)
    }
}

@available(iOS 17.0, *)
private enum HoloBadgeShader {
    static func make(size: CGSize, touch: CGPoint, touching: Float) -> Shader {
        let arguments: [Shader.Argument] = [
            .float2(size),
            .float2(touch),
            .float(touching)
        ]
        return Shader(
            function: .init(library: .default, name: "holoBadge"),
            arguments: arguments
        )
    }
}

#Preview {
    VStack(spacing: 20) {
        HoloBadgeView(image: Image("StreakBadge01"), cornerRadius: 18, isEarned: true)
            .frame(width: 140, height: 140)
        HoloBadgeView(image: Image("StreakBadge02"), cornerRadius: 18, isEarned: false)
            .frame(width: 140, height: 140)
    }
    .padding()
    .background(Color.black.opacity(0.85))
}
