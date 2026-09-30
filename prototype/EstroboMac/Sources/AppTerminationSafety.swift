import Foundation

/// A single conservative exit gate shared by Cmd-Q and the Menu Bar panel.
///
/// Local drafts are useful work, while Sync, apply, Test delivery, or an
/// automatic debounce may be partway through a physical-radio operation.
/// Estrobo therefore keeps running until the photographer resolves those states
/// explicitly. A persisted, derived draft with no legal Apply or Discard path
/// must never trap the app; it can be synchronized from local state next launch.
enum AppTerminationSafety {
    static func blockReason(
        pendingCount: Int,
        canResolvePendingChanges: Bool,
        phase: SessionPhase,
        isInteractiveEditActive: Bool,
        isAutomaticApplyScheduled: Bool,
        isTestPending: Bool,
        hasPendingRestoration: Bool
    ) -> String? {
        if hasPendingRestoration {
            return "No se puede cerrar: recupera el ajuste anterior antes de salir"
        }
        if phase == .synchronizing {
            return "No se puede cerrar mientras se sincronizan valores con el radio"
        }
        if phase == .applying {
            return "No se puede cerrar mientras se aplican cambios al radio"
        }
        if isTestPending {
            return "No se puede cerrar mientras se entrega la orden Test"
        }
        if isInteractiveEditActive {
            return "No se puede cerrar durante un ajuste de potencia"
        }
        if isAutomaticApplyScheduled {
            return "No se puede cerrar mientras el envío automático está pendiente"
        }
        if pendingCount > 0, canResolvePendingChanges {
            return "No se puede cerrar: aplica o descarta los cambios pendientes"
        }
        return nil
    }
}

@MainActor
extension EstroboSessionController {
    var terminationBlockReason: String? {
        AppTerminationSafety.blockReason(
            pendingCount: pendingCount,
            canResolvePendingChanges: canApply || canDiscardPendingChanges,
            phase: phase,
            isInteractiveEditActive: isInteractiveEditActive,
            isAutomaticApplyScheduled: isAutomaticApplyScheduled,
            isTestPending: isTestPending,
            hasPendingRestoration: !restorationPoints.isEmpty
        )
    }
}
