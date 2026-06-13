//
//  AudioRecorderManager.swift
//  MeetingTranscriber
//
//  Created by Codex on 2026/06/13.
//

import AVFoundation
import Combine

final class AudioRecorderManager: ObservableObject {
    @Published private(set) var isRecording = false

    private var audioRecorder: AVAudioRecorder?
    private var activeRecordingURL: URL?

    func startRecording(to fileURL: URL, completion: @escaping (Result<Void, AudioRecorderError>) -> Void) {
        AVAudioApplication.requestRecordPermission { [weak self] granted in
            DispatchQueue.main.async {
                guard let self else {
                    return
                }

                guard granted else {
                    completion(.failure(.microphonePermissionDenied))
                    return
                }

                do {
                    try self.beginRecording(to: fileURL)
                    completion(.success(()))
                } catch {
                    debugPrint("Failed to start recording: \(error.localizedDescription)")
                    completion(.failure(.startFailed))
                }
            }
        }
    }

    func stopRecording() -> Result<Void, AudioRecorderError> {
        audioRecorder?.stop()
        audioRecorder = nil
        activeRecordingURL = nil
        isRecording = false

        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            return .success(())
        } catch {
            debugPrint("Failed to deactivate recording audio session: \(error.localizedDescription)")
            return .failure(.audioSessionDeactivationFailed)
        }
    }

    private func beginRecording(to fileURL: URL) throws {
        let audioSession = AVAudioSession.sharedInstance()

        try audioSession.setCategory(
            .playAndRecord,
            mode: .default,
            options: [.allowBluetoothHFP, .defaultToSpeaker]
        )
        try audioSession.setActive(true)

        let recorder = try AVAudioRecorder(url: fileURL, settings: [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ])

        guard recorder.record() else {
            audioRecorder = nil
            activeRecordingURL = nil
            isRecording = false
            throw AudioRecorderError.startFailed
        }

        audioRecorder = recorder
        activeRecordingURL = fileURL
        isRecording = true
        debugPrint("Started recording: \(fileURL.lastPathComponent)")
    }
}

enum AudioRecorderError: Error {
    case microphonePermissionDenied
    case startFailed
    case audioSessionDeactivationFailed
}
