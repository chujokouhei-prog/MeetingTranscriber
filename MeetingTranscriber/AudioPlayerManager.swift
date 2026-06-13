//
//  AudioPlayerManager.swift
//  MeetingTranscriber
//
//  Created by Codex on 2026/06/13.
//

import AVFoundation
import Combine

final class AudioPlayerManager: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var playingRecordingURL: URL?
    @Published private(set) var activeRecordingURL: URL?
    @Published private(set) var loadedRecordingURL: URL?
    @Published private(set) var playbackState: AudioPlaybackState = .stopped
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0

    private var audioPlayer: AVAudioPlayer?
    private var playbackTimer: Timer?

    func togglePlayback(for recordingFile: RecordingFile) throws {
        if activeRecordingURL == recordingFile.url {
            switch playbackState {
            case .playing:
                pausePlayback()
            case .paused:
                try resumePlayback()
            case .loading, .stopped:
                try startPlayback(for: recordingFile)
            }
        } else {
            try startPlayback(for: recordingFile)
        }
    }

    func pausePlayback() {
        updatePlaybackProgress()
        audioPlayer?.pause()
        playbackState = .paused
        playingRecordingURL = nil
        stopPlaybackTimer()
    }

    func stopPlayback() {
        audioPlayer?.stop()
        audioPlayer = nil
        playingRecordingURL = nil
        activeRecordingURL = nil
        loadedRecordingURL = nil
        playbackState = .stopped
        currentTime = 0
        duration = 0
        stopPlaybackTimer()

        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            debugPrint("Failed to deactivate playback audio session: \(error.localizedDescription)")
        }
    }

    func seek(to time: TimeInterval) {
        if let audioPlayer {
            let boundedTime = min(max(time, 0), audioPlayer.duration)
            audioPlayer.currentTime = boundedTime
            updatePlaybackProgress()
            return
        }

        guard duration > 0 else {
            currentTime = 0
            return
        }

        let boundedTime = min(max(time, 0), duration)
        currentTime = boundedTime
    }

    func loadPlaybackInfo(for recordingFile: RecordingFile) {
        guard activeRecordingURL == nil, loadedRecordingURL != recordingFile.url else {
            return
        }

        guard FileManager.default.fileExists(atPath: recordingFile.url.path),
              let player = try? AVAudioPlayer(contentsOf: recordingFile.url) else {
            currentTime = 0
            duration = 0
            loadedRecordingURL = nil
            return
        }

        currentTime = 0
        duration = player.duration
        loadedRecordingURL = recordingFile.url
    }

    private func resumePlayback() throws {
        guard let audioPlayer else {
            throw AudioPlayerError.playFailed
        }

        try configureAudioSessionForPlayback()

        guard audioPlayer.play() else {
            throw AudioPlayerError.playFailed
        }

        playbackState = .playing
        playingRecordingURL = activeRecordingURL
        startPlaybackTimer()
    }

    private func startPlayback(for recordingFile: RecordingFile) throws {
        let requestedStartTime = loadedRecordingURL == recordingFile.url ? currentTime : 0

        stopPlayback()
        playbackState = .loading
        activeRecordingURL = recordingFile.url
        loadedRecordingURL = recordingFile.url

        guard FileManager.default.fileExists(atPath: recordingFile.url.path) else {
            stopPlayback()
            throw AudioPlayerError.fileNotFound
        }

        do {
            try configureAudioSessionForPlayback()

            let player = try AVAudioPlayer(contentsOf: recordingFile.url)
            player.delegate = self
            player.prepareToPlay()
            duration = player.duration
            player.currentTime = min(max(requestedStartTime, 0), player.duration)
            currentTime = player.currentTime

            guard player.play() else {
                stopPlayback()
                throw AudioPlayerError.playFailed
            }

            audioPlayer = player
            playbackState = .playing
            playingRecordingURL = recordingFile.url
            updatePlaybackProgress()
            startPlaybackTimer()
        } catch {
            stopPlayback()
            throw error
        }
    }

    private func configureAudioSessionForPlayback() throws {
        let audioSession = AVAudioSession.sharedInstance()

        try audioSession.setCategory(
            .playback,
            mode: .default,
            options: []
        )
        try audioSession.setActive(true)
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async {
            self.audioPlayer = nil
            self.playingRecordingURL = nil
            self.activeRecordingURL = nil
            self.loadedRecordingURL = nil
            self.playbackState = .stopped
            self.currentTime = 0
            self.duration = 0
            self.stopPlaybackTimer()
        }
    }

    private func startPlaybackTimer() {
        stopPlaybackTimer()

        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self else {
                return
            }

            self.updatePlaybackProgress()
        }

        RunLoop.main.add(timer, forMode: .common)
        playbackTimer = timer
        updatePlaybackProgress()
    }

    private func stopPlaybackTimer() {
        playbackTimer?.invalidate()
        playbackTimer = nil
    }

    private func updatePlaybackProgress() {
        guard let audioPlayer else {
            return
        }

        currentTime = audioPlayer.currentTime
        duration = audioPlayer.duration
    }
}

enum AudioPlaybackState {
    case stopped
    case loading
    case playing
    case paused
}

enum AudioPlayerError: Error {
    case fileNotFound
    case playFailed
}
