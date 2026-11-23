import Foundation

/// Holds the work clock until the upcoming exercise has been previewed.
///
/// The preview is not a `SessionEngine` phase. Rest, skip, and the recorded
/// bout length stay exactly as the engine already defines them. A 30-second
/// bout still lasts 30 seconds; the preview only delays the first tick.
struct PreviewGate: Equatable {
    private var acknowledged: Set<Int> = []

    func isPreviewing(phase: SessionPhase, index: Int) -> Bool {
        phase == .work && !acknowledged.contains(index)
    }

    mutating func acknowledge(index: Int) {
        acknowledged.insert(index)
    }
}
