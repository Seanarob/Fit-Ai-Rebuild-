//
//  FitFont.swift
//  FIT AI
//
//  Created by Codex on 2/xx/26.
//

import SwiftUI

enum FitFont {
    static func registerFonts() {
        // Intentionally left blank; system fonts are used for the new visual style.
    }

    static func body(size: CGFloat, weight: Font.Weight = .medium) -> Font {
        Font.system(size: size, weight: weight, design: .rounded)
    }

    static func heading(size: CGFloat, weight: Font.Weight = .bold) -> Font {
        Font.system(size: size, weight: weight, design: .rounded)
    }

    static func mono(size: CGFloat, weight: Font.Weight = .medium) -> Font {
        Font.system(size: size, weight: weight, design: .monospaced)
    }
}
