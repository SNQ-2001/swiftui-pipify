//
//  Copyright 2022 • Sidetrack Tech Limited
//

import SwiftUI

public extension View {
    @warn_unqualified_access
    func pipControlsStyle(
        _ style: PipifyController.ControlsStyle
    ) -> some View {
        modifier(PipifyControlsStyleModifier(
            controlsStyle: style
        ))
    }

    @warn_unqualified_access
    func onPipEvents(
        onWillStart: (() -> Void)? = nil,
        onDidStart: (() -> Void)? = nil,
        onWillStop: (() -> Void)? = nil,
        onDidStop: (() -> Void)? = nil,
        onFailedToStart: ((Error) -> Void)? = nil
    ) -> some View {
        modifier(PipifyEventModifier(
            onWillStart: onWillStart,
            onDidStart: onDidStart,
            onWillStop: onWillStop,
            onDidStop: onDidStop,
            onFailedToStart: onFailedToStart
        ))
    }
    
    @warn_unqualified_access
    func onPipTransitionToRenderSize(
        onDidTransitionToRenderSize: ((CGSize) -> Void)? = nil
    ) -> some View {
        modifier(PipifyTransitionToRenderSizeModifier(
            onDidTransitionToRenderSize: onDidTransitionToRenderSize
        ))
    }
    
    /// When the user uses the play/pause button inside the picture-in-picture window, the provided closure is called.
    ///
    /// The `Bool` is true if playing, else paused.
    @warn_unqualified_access
    func onPipSetPlaying(
        isSetPlayingEnabled: Bool,
        onSetPlaying: ((Bool) -> Void)?
    ) -> some View {
        modifier(PipifySetPlayingModifier(
            isSetPlayingEnabled: isSetPlayingEnabled,
            onSetPlaying: onSetPlaying
        ))
    }
    
    /// When the user uses the skip forward/backward button inside the picture-in-picture window, the provided closure is called.
    ///
    /// The `Bool` is true if forward, else backwards.
    @warn_unqualified_access
    func onPipSkip(
        isSkipEnabled: Bool,
        onSkip: ((Double) -> Void)?
    ) -> some View {
        modifier(PipifySkipModifier(
            isSkipEnabled: isSkipEnabled,
            onSkip: onSkip
        ))
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

internal struct PipifyControlsStyleModifier: ViewModifier {
    @EnvironmentObject private var controller: PipifyController
    let controlsStyle: PipifyController.ControlsStyle
    
    func body(content: Content) -> some View {
        content
            .onAppear {
                controller.controlsStyle = controlsStyle
            }
            .onDisappear {
                controller.controlsStyle = nil
            }
    }
}

internal struct PipifyEventModifier: ViewModifier {
    @EnvironmentObject private var controller: PipifyController
    let onWillStart: (() -> Void)?
    let onDidStart: (() -> Void)?
    let onWillStop: (() -> Void)?
    let onDidStop: (() -> Void)?
    let onFailedToStart: ((Error) -> Void)?
    
    func body(content: Content) -> some View {
        content
            .onAppear {
                controller.onWillStart = onWillStart
                controller.onDidStart = onDidStart
                controller.onWillStop = onWillStop
                controller.onDidStop = onDidStop
                controller.onFailedToStart = onFailedToStart
            }
            .onDisappear {
                controller.onWillStart = nil
                controller.onDidStart = nil
                controller.onWillStop = nil
                controller.onDidStop = nil
                controller.onFailedToStart = nil
            }
    }
}

internal struct PipifySetPlayingModifier: ViewModifier {
    @EnvironmentObject var controller: PipifyController
    let isSetPlayingEnabled: Bool
    let onSetPlaying: ((Bool) -> Void)?
    
    func body(content: Content) -> some View {
        content
            .onAppear {
                controller.isSetPlayingEnabled = isSetPlayingEnabled
                controller.onSetPlaying = onSetPlaying
            }
            .onDisappear {
                controller.isSetPlayingEnabled = false
                controller.onSetPlaying = nil
            }
    }
}

internal struct PipifySkipModifier: ViewModifier {
    @EnvironmentObject var controller: PipifyController
    let isSkipEnabled: Bool
    let onSkip: ((Double) -> Void)?
    
    func body(content: Content) -> some View {
        content
            .onAppear {
                controller.isSkipEnabled = isSkipEnabled
                controller.onSkip = onSkip
            }
            .onDisappear {
                controller.isSkipEnabled = false
                controller.onSkip = nil
            }
    }
}

internal struct PipifyTransitionToRenderSizeModifier: ViewModifier {
    @EnvironmentObject private var controller: PipifyController
    let onDidTransitionToRenderSize: ((CGSize) -> Void)?
    
    func body(content: Content) -> some View {
        content
            .onAppear {
                controller.onDidTransitionToRenderSize = onDidTransitionToRenderSize
            }
            .onDisappear {
                controller.onDidTransitionToRenderSize = nil
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
