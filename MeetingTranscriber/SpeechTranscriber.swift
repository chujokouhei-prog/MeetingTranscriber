//
//  SpeechTranscriber.swift
//  MeetingTranscriber
//
//  Created by Codex on 2026/06/13.
//

import Foundation
import Speech
import Combine

final class SpeechTranscriber: ObservableObject {
    @Published private(set) var transcribingRecordingURL: URL?

    private var speechRecognitionTask: SFSpeechRecognitionTask?
    private var didFinishCurrentTranscription = false

    func transcribe(
        recordingFile: RecordingFile,
        onResult: @escaping (String, Bool) -> Void,
        onCompletion: @escaping (SpeechTranscriberError?) -> Void
    ) {
        cancelTranscription()
        didFinishCurrentTranscription = false
        transcribingRecordingURL = recordingFile.url

        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                guard let self else {
                    return
                }

                switch status {
                case .authorized:
                    self.startSpeechRecognition(
                        for: recordingFile,
                        onResult: onResult,
                        onCompletion: onCompletion
                    )
                case .denied:
                    self.finish(with: .speechPermissionDenied, onCompletion: onCompletion)
                case .restricted:
                    self.finish(with: .speechRestricted, onCompletion: onCompletion)
                case .notDetermined:
                    self.finish(with: .speechPermissionNotDetermined, onCompletion: onCompletion)
                @unknown default:
                    self.finish(with: .speechAuthorizationFailed, onCompletion: onCompletion)
                }
            }
        }
    }

    func cancelTranscription() {
        speechRecognitionTask?.cancel()
        speechRecognitionTask = nil
        transcribingRecordingURL = nil
        didFinishCurrentTranscription = true
    }

    private func startSpeechRecognition(
        for recordingFile: RecordingFile,
        onResult: @escaping (String, Bool) -> Void,
        onCompletion: @escaping (SpeechTranscriberError?) -> Void
    ) {
        guard let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "ja_JP")) else {
            finish(with: .japaneseRecognizerUnavailable, onCompletion: onCompletion)
            return
        }

        guard speechRecognizer.isAvailable else {
            finish(with: .recognizerUnavailable, onCompletion: onCompletion)
            return
        }

        let request = SFSpeechURLRecognitionRequest(url: recordingFile.url)
        request.shouldReportPartialResults = true

        if speechRecognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

        speechRecognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self else {
                    return
                }

                guard !self.didFinishCurrentTranscription else {
                    return
                }

                if let result {
                    onResult(result.bestTranscription.formattedString, result.isFinal)

                    if result.isFinal {
                        self.finish(with: nil, onCompletion: onCompletion)
                    }
                }

                if error != nil {
                    self.finish(with: .recognitionFailed, onCompletion: onCompletion)
                }
            }
        }
    }

    private func finish(
        with error: SpeechTranscriberError?,
        onCompletion: @escaping (SpeechTranscriberError?) -> Void
    ) {
        guard !didFinishCurrentTranscription else {
            return
        }

        didFinishCurrentTranscription = true
        speechRecognitionTask = nil
        transcribingRecordingURL = nil
        onCompletion(error)
    }
}

enum SpeechTranscriberError: Error {
    case speechPermissionDenied
    case speechRestricted
    case speechPermissionNotDetermined
    case speechAuthorizationFailed
    case japaneseRecognizerUnavailable
    case recognizerUnavailable
    case recognitionFailed
}
