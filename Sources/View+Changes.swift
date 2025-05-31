//
//  Copyright 2022 • Sidetrack Tech Limited
//

import SwiftUI

public extension View {
    @warn_unqualified_access
    func pipEvents(
        onWillStart: (() -> Void)? = nil,
        onDidStart: (() -> Void)? = nil,
        onWillStop: (() -> Void)? = nil,
        onDidStop: (() -> Void)? = nil,
        onFailedToStartPip: ((Error) -> Void)? = nil
    ) -> some View {
        modifier(PipifyEventModifier(
            onWillStart: onWillStart,
            onDidStart: onDidStart,
            onWillStop: onWillStop,
            onDidStop: onDidStop,
            onFailedToStartPip: onFailedToStartPip
        ))
    }
    
    /// When the user uses the play/pause button inside the picture-in-picture window, the provided closure is called.
    ///
    /// The `Bool` is true if playing, else paused.
    @warn_unqualified_access
    func onPipPlayPause(closure: @escaping (Bool) -> Void) -> some View {
        modifier(PipifyPlayPauseModifier(closure: closure))
    }
    
    /// When the user uses the skip forward/backward button inside the picture-in-picture window, the provided closure is called.
    ///
    /// The `Bool` is true if forward, else backwards.
    @warn_unqualified_access
    func onPipSkip(closure: @escaping (Bool) -> Void) -> some View {
        modifier(PipifySkipModifier(closure: closure))
    }
    
    /// When picture-in-picture is started, the provided closure is called.
    @warn_unqualified_access
    func onPipStart(closure: @escaping () -> Void) -> some View {
        modifier(PipifyStatusModifier(closure: { newValue in
            if newValue {
                closure()
            }
        }))
    }
    
    /// When picture-in-picture is stopped, the provided closure is called.
    @warn_unqualified_access
    func onPipStop(closure: @escaping () -> Void) -> some View {
        modifier(PipifyStatusModifier(closure: { newValue in
            if newValue == false {
                closure()
            }
        }))
    }
    
    /// When the render size of the picture-in-picture window is changed, the provided closure is called.
    @warn_unqualified_access
    func onPipRenderSizeChanged(closure: @escaping (CGSize) -> Void) -> some View {
        modifier(PipifyRenderSizeModifier(closure: closure))
    }
    
    /// When the application is moved to the foreground, and if picture-in-picture is active, stop it.
    @warn_unqualified_access
    func pipHideOnForeground() -> some View {
        modifier(PipifyForegroundModifier())
    }
    
    /// When the application is moved to the background, activate picture-in-picture.
    @warn_unqualified_access
    func pipShowOnBackground() -> some View {
        modifier(PipifyBackgroundModifier())
    }
    
    /// Provides a binding to a double whose value is used to update the progress bar in the picture-in-picture window.
    @warn_unqualified_access
    func pipBindProgress(progress: Binding<Double>) -> some View {
        modifier(PipifyProgressModifier(progress: progress))
    }
}

internal struct PipifyEventModifier: ViewModifier {
    @EnvironmentObject private var controller: PipifyController
    let onWillStart: (() -> Void)?
    let onDidStart: (() -> Void)?
    let onWillStop: (() -> Void)?
    let onDidStop: (() -> Void)?
    let onFailedToStartPip: ((Error) -> Void)?
    
    func body(content: Content) -> some View {
        content
            .onAppear {
                controller.onWillStartPip = onWillStart
                controller.onDidStartPip = onDidStart
                controller.onWillStopPip = onWillStop
                controller.onDidStopPip = onDidStop
                controller.onFailedToStartPip = onFailedToStartPip
            }
            .onDisappear {
                controller.onWillStartPip = nil
                controller.onDidStartPip = nil
                controller.onWillStopPip = nil
                controller.onDidStopPip = nil
                controller.onFailedToStartPip = nil
            }
    }
}

internal struct PipifyPlayPauseModifier: ViewModifier {
    @EnvironmentObject var controller: PipifyController
    let closure: (Bool) -> Void
    
    func body(content: Content) -> some View {
        content
            .task {
                controller.isPlayPauseEnabled = true
            }
            .onChange(of: controller.isPlaying) { newValue in
                closure(newValue)
            }
    }
}

internal struct PipifyRenderSizeModifier: ViewModifier {
    @EnvironmentObject var controller: PipifyController
    let closure: (CGSize) -> Void
    
    func body(content: Content) -> some View {
        content
            .onChange(of: controller.renderSize) { newValue in
                closure(newValue)
            }
    }
}

internal struct PipifyStatusModifier: ViewModifier {
    @EnvironmentObject var controller: PipifyController
    let closure: (Bool) -> Void
    
    func body(content: Content) -> some View {
        content
            .onChange(of: controller.enabled) { newValue in
                closure(newValue)
            }
    }
}

internal struct PipifySkipModifier: ViewModifier {
    @EnvironmentObject var controller: PipifyController
    let closure: (Bool) -> Void
    
    func body(content: Content) -> some View {
        content
            .task {
                controller.onSkip = { value in
                    closure(value > 0) // isForward
                }
            }
    }
}

internal struct PipifyBackgroundModifier: ViewModifier {
    @EnvironmentObject var controller: PipifyController
    @Environment(\.scenePhase) var scenePhase
    
    func body(content: Content) -> some View {
        content
            .onChange(of: scenePhase) { newPhase in
                if newPhase == .background {
                    controller.isPlaying = true
                }
            }
    }
}

internal struct PipifyForegroundModifier: ViewModifier {
    @EnvironmentObject var controller: PipifyController
    @Environment(\.scenePhase) var scenePhase
    
    func body(content: Content) -> some View {
        content
            .onChange(of: scenePhase) { newPhase in
                if newPhase == .active {
                    controller.isPlaying = false
                }
            }
    }
}

internal struct PipifyProgressModifier: ViewModifier {
    @EnvironmentObject var controller: PipifyController
    @Binding var progress: Double
    
    func body(content: Content) -> some View {
        content
            .onChange(of: progress) { newProgress in
                assert(newProgress >= 0 && newProgress <= 1, "progress value must be between 0 and 1")
                controller.progress = newProgress.clamped(to: 0...1)
            }
    }
}

extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        return min(max(self, limits.lowerBound), limits.upperBound)
    }
}
