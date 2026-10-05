import Observation

/// Re-runs `onChange` every time any observable property read inside `apply` changes.
/// `withObservationTracking` only fires once, so this re-registers after each change.
@MainActor
func observeChanges(of apply: @escaping @MainActor () -> Void, onChange: @escaping @MainActor () -> Void) {
    withObservationTracking {
        apply()
    } onChange: {
        Task { @MainActor in
            onChange()
            observeChanges(of: apply, onChange: onChange)
        }
    }
}
