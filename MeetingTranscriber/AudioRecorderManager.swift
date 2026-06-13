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
    @Published private(set) var audioLevel = 0.0

    private var audioRecorder: AVAudioRecorder?
    private var activeRecordingURL: URL?
    private var audioLevelTimer: Timer?

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
        stopAudioLevelMetering()
        audioRecorder?.stop()
        audioRecorder = nil
        activeRecordingURL = nil
        isRecording = false
        audioLevel = 0

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

        try audioSession.setPreferredSampleRate(48_000)
        try audioSession.setCategory(
            .record,
            mode: .videoRecording,
            options: []
        )
        try audioSession.setActive(true)
        preferBuiltInMicrophoneIfAvailable(audioSession)

        let recorder = try AVAudioRecorder(url: fileURL, settings: [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 128_000,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ])
        recorder.isMeteringEnabled = true

        guard recorder.record() else {
            audioRecorder = nil
            activeRecordingURL = nil
            isRecording = false
            throw AudioRecorderError.startFailed
        }

        audioRecorder = recorder
        activeRecordingURL = fileURL
        isRecording = true
        startAudioLevelMetering()
        debugPrint("Started recording: \(fileURL.lastPathComponent)")
    }

    private func preferBuiltInMicrophoneIfAvailable(_ audioSession: AVAudioSession) {
        guard let builtInMicrophone = audioSession.availableInputs?.first(where: { $0.portType == .builtInMic }) else {
            return
        }

        do {
            try audioSession.setPreferredInput(builtInMicrophone)
        } catch {
            debugPrint("Failed to prefer built-in microphone: \(error.localizedDescription)")
        }
    }

    private func startAudioLevelMetering() {
        stopAudioLevelMetering()

        audioLevelTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            guard let self, let audioRecorder = self.audioRecorder else {
                return
            }

            audioRecorder.updateMeters()
            let averagePower = audioRecorder.averagePower(forChannel: 0)
            let normalizedLevel = max(0, min(1, (Double(averagePower) + 60) / 60))
            self.audioLevel = normalizedLevel
        }
    }

    private func stopAudioLevelMetering() {
        audioLevelTimer?.invalidate()
        audioLevelTimer = nil
    }
}

enum AudioRecorderError: Error {
    case microphonePermissionDenied
    case startFailed
    case audioSessionDeactivationFailed
}
