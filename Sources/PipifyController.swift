//
//  Copyright 2022 • Sidetrack Tech Limited
//

import Foundation
import SwiftUI
import AVKit
import Combine
import os.log

public final class PipifyController: NSObject, ObservableObject, AVPictureInPictureControllerDelegate,
                                       AVPictureInPictureSampleBufferPlaybackDelegate {
    
    public static var isSupported: Bool {
        AVPictureInPictureController.isPictureInPictureSupported()
    }
    
    /// https://stackoverflow.com/questions/66983901/how-to-hidden-the-play-pause-buttons-in-the-avpictureinpicturecontroller
    public enum ControlsStyle: Int {
        /// A minimal style where the Play and Pause controls are hidden.
        case minimal = 1

        /// A style where all controls are completely hidden.
        case hidden = 2

        /// A style where the loading indicator is displayed.
        case loading = 3
    }
    
    public var controlsStyle: ControlsStyle? {
        didSet {
            pipController?.setValue(controlsStyle?.rawValue, forKey: "controlsStyle")
        }
    }
    
    var isPlaying: Bool = true
    
    public var onWillStart: (() -> Void)?
    public var onDidStart: (() -> Void)?
    public var onWillStop: (() -> Void)?
    public var onDidStop: (() -> Void)?
    public var onFailedToStart: ((Error) -> Void)?
    
    public var isSetPlayingEnabled = false
    public var onSetPlaying: ((Bool) -> Void)?
    
    public var isSkipEnabled = false {
        didSet {
            // the pip controller is setup by the time the skip modifier changes this value
            // as such we update the pip controller after the fact
            pipController?.requiresLinearPlayback = !isSkipEnabled
            pipController?.invalidatePlaybackState()
        }
    }
    public var onSkip: ((Double) -> Void)?
    
    public var onDidTransitionToRenderSize: ((CGSize) -> Void)?
    
    internal var progress: Double = 1 {
        didSet {
            pipController?.invalidatePlaybackState()
        }
    }
    
    internal let bufferLayer = AVSampleBufferDisplayLayer()
    private var pipController: AVPictureInPictureController?
    private var rendererSubscriptions = Set<AnyCancellable>()
    private var pipPossibleObservation: NSKeyValueObservation?
    
    /// Updates (if necessary) the iOS audio session.
    ///
    /// Even though we don't play (or yet even support playing) audio, an audio session must be active in order
    /// for picture-in-picture to operate.
    static func setupAudioSession() {
        // not needed on macOS
        #if !os(macOS)
        logger.info("configuring audio session")
        let session = AVAudioSession.sharedInstance()
        
        // only update if necessary
        if session.category == .soloAmbient || session.mode == .default {
            try? session.setCategory(.playback, mode: .moviePlayback, options: .mixWithOthers)
        }
        #endif
    }
    
    public override init() {
        super.init()
        Self.setupAudioSession()
        setupController()
    }

    private func setupController() {
        logger.info("creating pip controller")
        
        bufferLayer.frame.size = .init(width: 300, height: 100)
        bufferLayer.videoGravity = .resizeAspect
        
        pipController = AVPictureInPictureController(contentSource: .init(
            sampleBufferDisplayLayer: bufferLayer,
            playbackDelegate: self
        ))
        
        // Combined with a certain time range this makes it so the skip buttons are not visible / interactable.
        // if an `isSkipEnabled` is false then we don't do this
        pipController?.requiresLinearPlayback = !isSkipEnabled
        
        pipController?.delegate = self
    }
    
    @MainActor func setView(_ view: some View, maximumUpdatesPerSecond: Double = 30) {
        let modifiedView = view.environmentObject(self)
        let renderer = ImageRenderer(content: modifiedView)
        
        renderer
            .objectWillChange
            // limit the number of times we redraw per second (performance)
            .throttle(for: .init(1.0 / maximumUpdatesPerSecond), scheduler: RunLoop.main, latest: true)
            .sink { [weak self] _ in
                self?.render(view: modifiedView, using: renderer)
            }
            .store(in: &rendererSubscriptions)
        
        // first draw
        render(view: modifiedView, using: renderer)
    }
    
    // MARK: - Rendering
    
    private func render(view: some View, using renderer: ImageRenderer<some View>) {
        Task {
            do {
                let buffer = try await view.makeBuffer(renderer: renderer)
                render(buffer: buffer)
            } catch {
                logger.error("failed to create buffer: \(error.localizedDescription)")
            }
        }
    }
    
    private func render(buffer: CMSampleBuffer) {
        if bufferLayer.status == .failed {
            bufferLayer.flush()
        }
        
        bufferLayer.enqueue(buffer)
    }
    
    // MARK: - Lifecycle
    
    internal func start() {
        guard let pipController else {
            logger.warning("could not start: no controller")
            return
        }
        
        guard pipController.isPictureInPictureActive == false else {
            logger.warning("could not start: already active")
            return
        }
        
        #if !os(macOS)
        logger.info("activating audio session")
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
        
        // force the timestamp to update
        pipController.invalidatePlaybackState()
        
        if pipController.isPictureInPicturePossible {
            logger.info("starting picture in picture")
            pipController.startPictureInPicture()
        } else {
            logger.info("waiting for pip to be possible")
            
            // not currently possible, so wait until it is.
            let keyPath = \AVPictureInPictureController.isPictureInPicturePossible
            pipPossibleObservation = pipController.observe(keyPath, options: [ .new ]) { [weak self] controller, change in
                if change.newValue ?? false {
                    logger.info("starting picture in picture")
                    controller.startPictureInPicture()
                    self?.pipPossibleObservation = nil
                }
            }
        }
    }
    
    internal func stop() {
        guard let pipController else {
            logger.warning("could not stop: no controller")
            return
        }
        
        logger.info("stopping picture in picture")
        pipController.stopPictureInPicture()
        
        #if !os(macOS)
        logger.info("deactivating audio session")
        try? AVAudioSession.sharedInstance().setActive(false)
        #endif
    }
    
    // MARK: - AVPictureInPictureControllerDelegate
    
    public func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        logger.info("willStart")
        onWillStart?()
    }

    public func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        logger.info("didStart")
        onDidStart?()
    }
    
    public func pictureInPictureControllerWillStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        logger.info("willStop")
        onWillStop?()
    }
    
    public func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        logger.info("didStop")
        onDidStop?()
    }
    
    public func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        logger.error("failed to start: \(error.localizedDescription)")
        onFailedToStart?(error)
    }
    
    public func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
    ) {
        logger.info("restore UI")
        completionHandler(true)
    }
    
    public func pictureInPictureControllerShouldProhibitBackgroundAudioPlayback(_ pictureInPictureController: AVPictureInPictureController) -> Bool {
        // We do not support audio through the pipify controller, as such we will allow other background audio to
        // continue playing
        return false
    }
    
    // MARK: - AVPictureInPictureSampleBufferPlaybackDelegate
    
    public func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, setPlaying playing: Bool) {
        if isSetPlayingEnabled {
            logger.info("setPlaying: \(playing)")
            isPlaying = playing
            onSetPlaying?(playing)
            pictureInPictureController.invalidatePlaybackState()
        }
    }
    
    public func pictureInPictureControllerIsPlaybackPaused(_ pictureInPictureController: AVPictureInPictureController) -> Bool {
        return isSetPlayingEnabled && isPlaying == false
    }
    
    public func pictureInPictureControllerTimeRangeForPlayback(_ pictureInPictureController: AVPictureInPictureController) -> CMTimeRange {
        if !isSkipEnabled && progress == 1 {
            // By returning a positive time range in conjunction with enabling `requiresLinearPlayback`
            // PIP will only show the play/pause button and hide the 'Live' label and skip buttons.
            return CMTimeRange(start: .init(value: 1, timescale: 1), end: .init(value: 2, timescale: 1))
        } else {
            let currentTime = CMTime(
                seconds: CACurrentMediaTime(),
                preferredTimescale: 120
            )
            
            // We use one week as the value needs to be large enough that a user would not feasibly see time pass.
            let oneWeek: Double = 86400 * 7
            
            let multipliers: (Double, Double)
            switch progress {
            case 0: // 0%
                multipliers = (0, 1)
            default:
                multipliers = (1, 1 / progress - 1)
            }
            
            let startScaler = CMTime(seconds: oneWeek * multipliers.0, preferredTimescale: 120)
            
            // the 20 here (can be pretty much any number) ensures that the skip forward button works
            // if we don't add this little extra then Apple believes we're at the end of the clip
            // and as such disables the skip forward button. we don't want that.
            // because our oneWeek number is so large, the 20 here isn't noticeable to users.
            let endScaler = CMTime(seconds: oneWeek * multipliers.1 + 20, preferredTimescale: 120)
            
            return CMTimeRange(start: currentTime - startScaler, end: currentTime + endScaler)
        }
    }
    
    public func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, didTransitionToRenderSize newRenderSize: CMVideoDimensions) {
        logger.trace("window resize: \(newRenderSize.width)x\(newRenderSize.height)")
        onDidTransitionToRenderSize?(CGSize(width: Int(newRenderSize.width), height: Int(newRenderSize.height)))
    }
    
    public func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, skipByInterval skipInterval: CMTime) async {
        logger.info("skip by: \(skipInterval.seconds) seconds")
        onSkip?(skipInterval.seconds)
    }
}

let logger = Logger(subsystem: "com.getsidetrack.pipify", category: "Pipify")
