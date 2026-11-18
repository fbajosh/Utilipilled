import AppKit
import ObjectiveC

// Isolate the OS-specific material recipes; never change another app's views.
// Numeric recipe mappings are checked only on the supported macOS 26 build family.
// Setter existence, C ABI argument types and readback are checked before use.
enum NativeSwitcherGlass {
    enum Role: Int { case container = 3, selection = 14 }

    static var isAvailable: Bool {
        guard NativeSwitcherServices.supportedOS, #available(macOS 26.0, *) else { return false }
        return supportsSetter(NSGlassEffectView.self, "set_variant:") &&
            supportsSetter(NSGlassEffectView.self, "set_adaptiveAppearance:") &&
            supportsGetter(NSGlassEffectView.self, "_variant") &&
            supportsGetter(NSGlassEffectView.self, "_adaptiveAppearance")
    }

    @discardableResult
    static func configure(_ view: NSView, role: Role) -> Bool {
        guard isAvailable, #available(macOS 26.0, *), view is NSGlassEffectView else { return false }
        guard supportsSetter(type(of: view), "set_variant:"), supportsSetter(type(of: view), "set_adaptiveAppearance:") else { return false }
        // Dock's backdrop and the focus-border material render their own blur,
        // refraction and specular edges. Leave tint and lensing to the native recipe.
        (view as? NSGlassEffectView)?.tintColor = nil
        view.setValue(NSNumber(value: role.rawValue), forKey: "_variant")
        view.setValue(NSNumber(value: 1), forKey: "_adaptiveAppearance")
        return (view.value(forKey: "_variant") as? NSNumber)?.intValue == role.rawValue &&
            (view.value(forKey: "_adaptiveAppearance") as? NSNumber)?.intValue == 1
    }

    private static func supportsSetter(_ type: AnyClass, _ name: String) -> Bool {
        guard let method = class_getInstanceMethod(type, NSSelectorFromString(name)),
              method_getNumberOfArguments(method) == 3,
              let argument = method_copyArgumentType(method, 2) else { return false }
        let result = method_copyReturnType(method)
        defer { free(argument); free(result) }
        // NSInteger is a signed 64-bit integer on every supported Apple-silicon Mac.
        return String(cString: argument) == "q" && String(cString: result) == "v"
    }

    private static func supportsGetter(_ type: AnyClass, _ name: String) -> Bool {
        guard let method = class_getInstanceMethod(type, NSSelectorFromString(name)),
              method_getNumberOfArguments(method) == 2 else { return false }
        let result = method_copyReturnType(method)
        defer { free(result) }
        return String(cString: result) == "q"
    }
}
