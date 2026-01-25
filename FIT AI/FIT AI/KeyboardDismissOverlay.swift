import SwiftUI
import UIKit

struct KeyboardDismissOverlay: UIViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard context.coordinator.tapGesture == nil,
              let window = uiView.window else { return }
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap))
        tap.cancelsTouchesInView = false
        tap.delegate = context.coordinator
        window.addGestureRecognizer(tap)
        context.coordinator.tapGesture = tap
        context.coordinator.window = window
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        if let tap = coordinator.tapGesture {
            coordinator.window?.removeGestureRecognizer(tap)
            coordinator.tapGesture = nil
        }
        coordinator.window = nil
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        weak var window: UIWindow?
        var tapGesture: UITapGestureRecognizer?

        @objc func handleTap() {
            UIApplication.shared.sendAction(
                #selector(UIResponder.resignFirstResponder),
                to: nil,
                from: nil,
                for: nil
            )
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            var view = touch.view
            while let current = view {
                if current is UITextField || current is UITextView {
                    return false
                }
                view = current.superview
            }
            return true
        }
    }
}

extension View {
    func dismissKeyboardOnTap() -> some View {
        overlay(KeyboardDismissOverlay())
    }
}
