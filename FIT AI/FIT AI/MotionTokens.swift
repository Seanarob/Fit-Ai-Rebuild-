import SwiftUI

enum MotionTokens {
    static let fast: Double = 0.16
    static let base: Double = 0.24
    static let medium: Double = 0.32
    static let slow: Double = 0.40

    static let springQuick = Animation.spring(response: 0.30, dampingFraction: 0.85, blendDuration: 0.1)
    static let springBase = Animation.spring(response: 0.40, dampingFraction: 0.80, blendDuration: 0.1)
    static let springSoft = Animation.spring(response: 0.55, dampingFraction: 0.75, blendDuration: 0.1)

    static let easeOut = Animation.easeOut(duration: 0.30)
    static let easeInOut = Animation.easeInOut(duration: 0.30)
}
