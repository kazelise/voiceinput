import AppKit
import Foundation

/// Pauses currently-playing media when the user starts dictating and resumes
/// exactly the thing we paused when they are done.
///
/// macOS 15+ effectively neutered `MRMediaRemoteSendCommand` for unsigned
/// third-party apps, so for Spotify and Apple Music we drive the app directly
/// via AppleScript (synchronous, reliable). MRMediaRemote is kept only as a
/// best-effort fallback for other sources — it may or may not do anything on
/// modern macOS.
///
/// Running Spotify / Music is detected through NSWorkspace first so we never
/// accidentally launch a media app just to query its state.
final class MediaController {

    private(set) var didPauseMedia = false

    private enum Strategy {
        case spotify
        case music
        case mediaRemote
    }
    private var strategy: Strategy?

    private var mrHandle: UnsafeMutableRawPointer?

    init() {
        mrHandle = dlopen(
            "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote",
            RTLD_NOW
        )
    }

    deinit {
        if let mrHandle { dlclose(mrHandle) }
    }

    // MARK: - Public API

    /// Pauses media if something is playing. Only strategies that succeed and
    /// successfully flip the player to "paused" set `didPauseMedia = true`, so
    /// `resumeIfPaused()` only undoes what we actually did.
    func pauseIfPlaying() {
        didPauseMedia = false
        strategy = nil

        if isAppRunning("com.spotify.client"),
           playerState(app: "Spotify") == "playing" {
            if runSimple("tell application \"Spotify\" to pause") {
                strategy = .spotify
                didPauseMedia = true
                Log.app.info("MediaController: paused Spotify")
                return
            }
        }

        if isAppRunning("com.apple.Music"),
           playerState(app: "Music") == "playing" {
            if runSimple("tell application \"Music\" to pause") {
                strategy = .music
                didPauseMedia = true
                Log.app.info("MediaController: paused Music")
                return
            }
        }

        // Last resort: MRMediaRemote. Likely a no-op on recent macOS but
        // cheap to try and harmless if it fails.
        tryMediaRemotePause()
    }

    /// Resumes only the source we actually paused.
    func resumeIfPaused() {
        guard didPauseMedia, let strategy else { return }
        didPauseMedia = false
        self.strategy = nil

        switch strategy {
        case .spotify:
            _ = runSimple("tell application \"Spotify\" to play")
            Log.app.info("MediaController: resumed Spotify")
        case .music:
            _ = runSimple("tell application \"Music\" to play")
            Log.app.info("MediaController: resumed Music")
        case .mediaRemote:
            sendMediaRemoteCommand(0) // kMRPlay
            Log.app.info("MediaController: resumed via MediaRemote")
        }
    }

    // MARK: - AppleScript helpers

    private func isAppRunning(_ bundleID: String) -> Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == bundleID }
    }

    /// Returns "playing", "paused", "stopped", or nil on error.
    private func playerState(app: String) -> String? {
        let source = "tell application \"\(app)\" to return player state as string"
        guard let script = NSAppleScript(source: source) else { return nil }
        var errorInfo: NSDictionary?
        let output = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            Log.app.warning("MediaController \(app) state query error: \(errorInfo)")
            return nil
        }
        return output.stringValue
    }

    /// Runs a one-liner `tell application "X" to Y`. Returns true if no error.
    @discardableResult
    private func runSimple(_ source: String) -> Bool {
        guard let script = NSAppleScript(source: source) else { return false }
        var errorInfo: NSDictionary?
        _ = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            Log.app.warning("MediaController AppleScript error: \(errorInfo)")
            return false
        }
        return true
    }

    // MARK: - MRMediaRemote (best-effort fallback)

    private func tryMediaRemotePause() {
        guard let mrHandle,
              let infoSym = dlsym(mrHandle, "MRMediaRemoteGetNowPlayingInfo")
        else {
            Log.app.info("MediaController: MRMediaRemote unavailable")
            return
        }
        typealias GetInfoType = @convention(c) (
            DispatchQueue,
            @escaping @convention(block) (NSDictionary) -> Void
        ) -> Void
        let getInfo = unsafeBitCast(infoSym, to: GetInfoType.self)

        getInfo(DispatchQueue.main) { [weak self] info in
            guard let self else { return }
            let rate = info["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? Double ?? 0
            if rate > 0 {
                self.sendMediaRemoteCommand(1) // kMRPause
                self.strategy = .mediaRemote
                self.didPauseMedia = true
                Log.app.info("MediaController: MediaRemote paused (rate=\(rate))")
            } else {
                Log.app.info("MediaController: MediaRemote nothing playing (rate=\(rate))")
            }
        }
    }

    private func sendMediaRemoteCommand(_ command: UInt32) {
        guard let mrHandle, let sym = dlsym(mrHandle, "MRMediaRemoteSendCommand") else { return }
        typealias SendType = @convention(c) (UInt32, AnyObject?) -> Bool
        let send = unsafeBitCast(sym, to: SendType.self)
        let ok = send(command, nil)
        Log.app.info("MediaController: MRMediaRemoteSendCommand(\(command)) = \(ok)")
    }
}
