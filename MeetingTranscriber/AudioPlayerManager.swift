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

    private var audioPlayer: AVAudioPlayer?

    func togglePlayback(for recordingFile: RecordingFile) throws {
        if playingRecordingURL == recordingFile.url {
            stopPlayback()
        } else {
            try startPlayback(for: recordingFile)
        }
    }

    func stopPlayback() {
        audioPlayer?.stop()
        audioPlayer = nil
        playingRecordingURL = nil

        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            debugPrint("Failed to deactivate playback audio session: \(error.localizedDescription)")
        }
    }

    private func startPlayback(for recordingFile: RecordingFile) throws {
        stopPlayback()

        guard FileManager.default.fileExists(atPath: recordingFile.url.path) else {
            throw AudioPlayerError.fileNotFound
        }

        try configureAudioSessionForPlayback()

        let player = try AVAudioPlayer(contentsOf: recordingFile.url)
        player.delegate = self
        player.prepareToPlay()

        guard player.play() else {
            throw AudioPlayerError.playFailed
        }

        audioPlayer = player
        playingRecordingURL = recordingFile.url
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
        audioPlayer = nil
        playingRecordingURL = nil
    }
}

enum AudioPlayerError: Error {
    case fileNotFound
    case playFailed
}
