//
//  BeamHook.swift
//  BorderBeamTweak
//
//  Hooks UITextField / UITextView focus and puts a beam overlay on whichever
//  field the user is typing in. No substrate dependency: plain ObjC runtime
//  swizzling, so the dylib works on rootless and roothide alike.
//
import UIKit
import ObjectiveC.runtime

private typealias BoolIMP = @convention(c) (AnyObject, Selector) -> Bool

/// Adds an override on `cls` itself (never on the superclass) that wraps the
/// original implementation. `body` gets the receiver plus a call-through.
@discardableResult
private func hookBool(_ cls: AnyClass,
                      _ selector: Selector,
                      body: @escaping (AnyObject, @escaping () -> Bool) -> Bool) -> Bool {
    guard let method = class_getInstanceMethod(cls, selector),
          let types = method_getTypeEncoding(method) else { return false }

    let original = unsafeBitCast(method_getImplementation(method), to: BoolIMP.self)
    let block: @convention(block) (AnyObject) -> Bool = { object in
        body(object) { original(object, selector) }
    }
    let imp = imp_implementationWithBlock(block)

    // class_addMethod succeeds only when cls has no own implementation yet, in
    // which case the inherited (superclass) implementation stays untouched.
    if !class_addMethod(cls, selector, imp, types) {
        method_setImplementation(method, imp)
    }
    return true
}

enum BeamHook {

    static func install() {
        let become = NSSelectorFromString("becomeFirstResponder")
        let resign = NSSelectorFromString("resignFirstResponder")

        hookBool(UITextField.self, become) { object, call in
            let became = call()
            if became, let view = object as? UIView {
                DispatchQueue.main.async { BeamOverlay.shared.attach(to: view) }
            }
            return became
        }

        hookBool(UITextField.self, resign) { object, call in
            let resigned = call()
            if let view = object as? UIView {
                DispatchQueue.main.async { BeamOverlay.shared.detach(from: view) }
            }
            return resigned
        }

        hookBool(UITextView.self, become) { object, call in
            let became = call()
            if became, let view = object as? UIView {
                DispatchQueue.main.async { BeamOverlay.shared.attach(to: view) }
            }
            return became
        }

        hookBool(UITextView.self, resign) { object, call in
            let resigned = call()
            if let view = object as? UIView {
                DispatchQueue.main.async { BeamOverlay.shared.detach(from: view) }
            }
            return resigned
        }
    }
}

// MARK: - Overlay management

final class BeamOverlay {

    static let shared = BeamOverlay()

    private var beams: [ObjectIdentifier: BeamMetalView] = [:]

    /// Same ramp as `BeamPalette.spectrum` in the library, but as UIColors so
    /// nothing here needs SwiftUI.
    private static let palette: [UIColor] = [
        UIColor(red: 0.26, green: 0.50, blue: 0.96, alpha: 1),   // blue
        UIColor(red: 0.25, green: 0.70, blue: 0.90, alpha: 1),   // teal-blue
        UIColor(red: 0.25, green: 0.82, blue: 0.85, alpha: 1),   // cyan
        UIColor(red: 0.25, green: 0.78, blue: 0.40, alpha: 1),   // green
        UIColor(red: 0.98, green: 0.74, blue: 0.20, alpha: 1),   // yellow
        UIColor(red: 0.98, green: 0.52, blue: 0.22, alpha: 1),   // orange
        UIColor(red: 0.92, green: 0.28, blue: 0.25, alpha: 1),   // red
    ]

    func attach(to view: UIView) {
        // Skip things that are not really visible inputs (search bar internals,
        // offscreen fields, the tiny text field inside a UISearchBar's cancel).
        guard view.window != nil else { return }
        guard view.bounds.width >= 40, view.bounds.height >= 18 else { return }
        guard !(view.superview is UISearchBar) else { return }

        let key = ObjectIdentifier(view)
        if beams[key] != nil { return }

        let beam = BeamMetalView(frame: view.bounds)
        beam.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        beam.isUserInteractionEnabled = false

        var config = BeamRenderConfig()
        config.style = .large
        config.shape = .rounded(Self.cornerRadius(for: view))
        config.direction = .leftToRight
        config.colors = Self.palette
        config.intensity = 0.9
        beam.config = config

        view.addSubview(beam)
        beams[key] = beam
    }

    func detach(from view: UIView) {
        let key = ObjectIdentifier(view)
        guard let beam = beams.removeValue(forKey: key) else { return }
        UIView.performWithoutAnimation { beam.removeFromSuperview() }
    }

    private static func cornerRadius(for view: UIView) -> CGFloat {
        let declared = view.layer.cornerRadius
        if declared > 0 { return declared }
        // Plain fields have no radius; half the height reads as a pill, which
        // is what chat composers look like.
        return min(max(view.bounds.height * 0.5, 6), 22)
    }
}
