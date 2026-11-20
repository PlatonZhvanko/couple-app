import SwiftUI
import UIKit

/// Закрывает клавиатуру нажатием на пустое место в любом экране приложения.
/// Нажатие на поле ввода клавиатуру не закрывает.
@MainActor
final class KeyboardDismisser: NSObject, UIGestureRecognizerDelegate {
    static let shared = KeyboardDismisser()
    private var installed = false

    /// Ставит распознаватель нажатий на окно. Безопасно вызывать много раз.
    func install() {
        guard !installed else { return }
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
        guard let window else { return }
        let tap = UITapGestureRecognizer(target: self, action: #selector(dismiss))
        tap.cancelsTouchesInView = false
        tap.delegate = self
        window.addGestureRecognizer(tap)
        installed = true
    }

    @objc private func dismiss() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    nonisolated func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        var view: UIView? = touch.view
        while let current = view {
            if current is UITextField || current is UITextView || current is UISearchBar {
                return false
            }
            view = current.superview
        }
        return true
    }

    nonisolated func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
        true
    }
}
