//
//  BeamHook.swift
//  BorderBeamTweak
//
//  Entry point + focus hooks. Plain Objective-C runtime swizzling, no
//  substitution framework, so the same dylib works on rootless (ElleKit) and
//  roothide loaders alike.
//
//  Three classes are hooked so a custom subclass that forwards to super still
//  gets caught: UITextField, UITextView and UIResponder itself. Every hook is
//  guarded by an `is` check, so the UIResponder pass is a no-op for anything
//  that is not a real text input.
//

import UIKit
import ObjectiveC.runtime

private typealias BoolIMP = @convention(c) (AnyObject, Selector) -> Bool

/// `method_setImplementation` on an inherited method would silently rewrite the
/// superclass for every class in the process. Only swizzle when the class owns
/// the method itself; otherwise add an override.
private func classOwnsInstanceMethod(_ cls: AnyClass, _ sel: Selector) -> Bool {
    var count: UInt32 = 0
    guard let list = class_copyMethodList(cls, &count) else { return false }
    defer { free(list) }
    for i in 0..<Int(count) where method_getName(list[i]) == sel {
        return true
    }
    return false
}

@discardableResult
private func hookBool(_ cls: AnyClass,
                      _ sel: Selector,
                      body: @escaping (AnyObject, @escaping () -> Bool) -> Bool) -> Bool {
    guard let method = class_getInstanceMethod(cls, sel),
          let types = method_getTypeEncoding(method) else { return false }

    let original = unsafeBitCast(method_getImplementation(method), to: BoolIMP.self)
    let block: @convention(block) (AnyObject) -> Bool = { object in
        body(object) { original(object, sel) }
    }
    let imp = imp_implementationWithBlock(block)

    if classOwnsInstanceMethod(cls, sel) {
        method_setImplementation(method, imp)
        return true
    }
    return class_addMethod(cls, sel, imp, types)
}

enum BeamHook {

    static func install() {
        let become = NSSelectorFromString("becomeFirstResponder")
        let resign = NSSelectorFromString("resignFirstResponder")
        let classes: [AnyClass] = [UITextField.self, UITextView.self, UIResponder.self]

        for cls in classes {
            let hookedBecome = hookBool(cls, become) { object, call in
                let result = call()
                if result { BeamOverlay.shared.scheduleAttach(object as? UIView) }
                return result
            }
            let hookedResign = hookBool(cls, resign) { object, call in
                let result = call()
                if result { BeamOverlay.shared.detach(object as? UIView) }
                return result
            }
            NSLog("[BorderBeam] hook %@ become=%d resign=%d",
                  NSStringFromClass(cls),
                  Int32(hookedBecome ? 1 : 0),
                  Int32(hookedResign ? 1 : 0))
        }
    }
}

// MARK: - Overlay management

final class BeamOverlay {

    static let shared = BeamOverlay()

    /// Weak keys: the beam lives as a subview of its field, so nothing has to be
    /// torn down when a field disappears without resigning first.
    private let beams = NSMapTable<UIView, BeamSweepView>(
        keyOptions: [.weakMemory],
        valueOptions: [.strongMemory],
        capacity: 8
    )

    private static let palette: [UIColor] = [
        UIColor(red: 0.26, green: 0.50, blue: 0.96, alpha: 1),   // blue
        UIColor(red: 0.25, green: 0.70, blue: 0.90, alpha: 1),   // sky
        UIColor(red: 0.25, green: 0.82, blue: 0.85, alpha: 1),   // cyan
        UIColor(red: 0.25, green: 0.78, blue: 0.40, alpha: 1),   // green
        UIColor(red: 0.98, green: 0.74, blue: 0.20, alpha: 1),   // yellow
        UIColor(red: 0.98, green: 0.52, blue: 0.22, alpha: 1),   // orange
        UIColor(red: 0.92, green: 0.28, blue: 0.25, alpha: 1),   // red
    ]

    // MARK: Attach

    /// Some apps focus a field before it is in a window; retry briefly instead of
    /// giving up (giving up is what made v1.0 look like "nothing happened").
    func scheduleAttach(_ field: UIView?) {
        guard let field = field, isTextInput(field) else { return }
        DispatchQueue.main.async { self.attachRetrying(field, attemptsLeft: 8) }
    }

    private func attachRetrying(_ field: UIView, attemptsLeft: Int) {
        if field.window == nil {
            guard attemptsLeft > 0 else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.attachRetrying(field, attemptsLeft: attemptsLeft - 1)
            }
            return
        }
        attach(to: field)
    }

    private func attach(to field: UIView) {
        guard field.window != nil else { return }
        guard field.bounds.width >= 24, field.bounds.height >= 14 else { return }
        if field.superview is UISearchBar { return }     // search field internals
        if beams.object(forKey: field) != nil { return } // already lit

        let beam = BeamSweepView(frame: field.bounds,
                                 cornerRadius: Self.cornerRadius(for: field),
                                 palette: Self.palette)
        beam.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        field.addSubview(beam)
        beams.setObject(beam, forKey: field)

        NSLog("[BorderBeam] attach %@ %.0fx%.0f",
              NSStringFromClass(type(of: field)), field.bounds.width, field.bounds.height)
    }

    func detach(_ field: UIView?) {
        guard let field = field, let beam = beams.object(forKey: field) else { return }
        beams.removeObject(forKey: field)
        UIView.performWithoutAnimation { beam.removeFromSuperview() }
        NSLog("[BorderBeam] detach %@", NSStringFromClass(type(of: field)))
    }

    // MARK: Helpers

    private func isTextInput(_ view: UIView) -> Bool {
        view is UITextField || view is UITextView
    }

    private static func cornerRadius(for view: UIView) -> CGFloat {
        let declared = view.layer.cornerRadius
        if declared > 0 { return declared }
        let height = view.bounds.height
        if height <= 64 {
            // Single-line fields read as pills.
            return min(max(height * 0.5, 8), 24)
        }
        return 12
    }
}
