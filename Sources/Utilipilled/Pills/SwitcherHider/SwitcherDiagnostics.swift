import Foundation

struct SwitcherEvent {
    enum Kind: String { case invocation, selection, presentation, render, commit, dismissal, activationAccepted, activationRejected, activationConfirmed, activationUnconfirmed, overview, drop }
    let kind: Kind
    let time: UInt64
    let session: Int
    init(_ kind: Kind, session: Int) { self.kind = kind; self.session = session; time = DispatchTime.now().uptimeNanoseconds }
}
