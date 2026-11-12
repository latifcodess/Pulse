import Observation
import PulseCore

/// Un seul popover ouvert à la fois : quand on ouvre celui d'une IA, celui
/// qui était déjà ouvert se ferme.
@MainActor
@Observable
final class PopoverCoordinator {
    /// L'IA dont le popover est ouvert.
    private(set) var active: AiService?

    func opened(_ service: AiService) {
        active = service
    }

    func closed(_ service: AiService) {
        if active == service {
            active = nil
        }
    }
}
