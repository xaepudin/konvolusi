import Foundation
import SwiftUI

/// High-rate values the panel displays.
///
/// These deliberately live outside `AppModel`: the `MenuBarExtra` scene observes
/// `AppModel`, and every `@Published` change there invalidates the whole scene.
/// Updating meter levels twenty times a second through the app model made SwiftUI
/// re-lay-out and re-render the panel twenty times a second *even while it was
/// closed* — which cost several times more energy than the audio DSP itself.
final class MeterStore: ObservableObject {
    @Published var input: Double = 0
    @Published var output: Double = 0
}

/// Rarely-changing status, so the menu bar icon can update without dragging the
/// rest of the scene with it.
final class StatusStore: ObservableObject {
    @Published var isRunning = false
}
