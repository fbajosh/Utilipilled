import AppKit
import ApplicationServices

final class ApplicationActivator {
    private var overviewObserver: NSObjectProtocol?
    private var overviewGeneration = 0

    func activate(_ application: SwitcherApplication, restoreMinimized: Bool = false, completion: @escaping (Bool) -> Void = { _ in }) {
        guard !application.process.isTerminated else { completion(false); return }
        application.process.unhide()
        guard restoreMinimized, let url = application.record.applicationURL else {
            let accepted = application.process.activate(options: [])
            completion(accepted || NativeSwitcherServices.shared.activateApplication(application.pid)); return
        }
        // Ask the app to handle its normal reopen event. The application, rather than
        // Utilipilled, decides how to restore its minimized/document windows.
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.addsToRecentItems = false
        configuration.promptsUserIfNeeded = false
        configuration.allowsRunningApplicationSubstitution = false
        configuration.appleEvent = NSAppleEventDescriptor(eventClass: AEEventClass(kCoreEventClass),
            eventID: AEEventID(kAEReopenApplication),
            targetDescriptor: NSAppleEventDescriptor(processIdentifier: application.pid),
            returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { process, error in
            DispatchQueue.main.async { completion(error == nil && process?.processIdentifier == application.pid) }
        }
    }

    func showOverview(_ application: SwitcherApplication, completion: @escaping (Bool) -> Void) {
        cancelPendingOverview()
        guard NativeSwitcherServices.shared.supportsOverview, !application.process.isTerminated else { completion(false); return }
        let generation = overviewGeneration
        let center = NSWorkspace.shared.notificationCenter
        func showIfCurrent() {
            guard self.overviewGeneration == generation else { return }
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == application.pid else { return }
            self.cancelPendingOverview()
            completion(NativeSwitcherServices.shared.showApplicationOverview())
        }
        overviewObserver = center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { _ in showIfCurrent() }
        activate(application) { [weak self] accepted in
            guard let self, self.overviewGeneration == generation else { return }
            if accepted { showIfCurrent() }
            else { self.cancelPendingOverview(); completion(false) }
        }
        // Never open overview for whichever unrelated application became active later.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) { [weak self] in
            guard let self, self.overviewGeneration == generation else { return }
            showIfCurrent()
            if self.overviewGeneration == generation { self.cancelPendingOverview(); completion(false) }
        }
    }

    func cancelPendingOverview() {
        overviewGeneration += 1
        if let overviewObserver { NSWorkspace.shared.notificationCenter.removeObserver(overviewObserver) }
        overviewObserver = nil
    }

    func open(_ urls: [URL], in application: SwitcherApplication, completion: @escaping (Bool) -> Void) {
        guard !urls.isEmpty, !application.process.isTerminated, let applicationURL = application.record.applicationURL else {
            completion(false); return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.addsToRecentItems = false
        configuration.promptsUserIfNeeded = false
        configuration.allowsRunningApplicationSubstitution = false
        NSWorkspace.shared.open(urls, withApplicationAt: applicationURL, configuration: configuration) { process, error in
            DispatchQueue.main.async { completion(error == nil && process?.processIdentifier == application.pid) }
        }
    }

    func quit(_ application: SwitcherApplication) {
        // Finder has no normal Quit action unless its own user preference enables it.
        if application.record.bundleIdentifier == "com.apple.finder",
           !(UserDefaults.standard.persistentDomain(forName: "com.apple.finder")?["QuitMenuItem"] as? Bool ?? false) {
            return
        }
        application.process.terminate()
    }

    func hide(_ application: SwitcherApplication) { application.process.hide() }
    deinit { cancelPendingOverview() }
}
