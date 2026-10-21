import Observation

/// Runs `apply` now and again whenever an observable property it read changes, until the owner goes away.
@MainActor
func observeContinuously<Owner: AnyObject & Sendable>(_ owner: Owner, _ apply: @escaping @MainActor (Owner) -> Void) {
    withObservationTracking {
        apply(owner)
    } onChange: { [weak owner] in
        Task { @MainActor in
            guard let owner else { return }
            observeContinuously(owner, apply)
        }
    }
}
