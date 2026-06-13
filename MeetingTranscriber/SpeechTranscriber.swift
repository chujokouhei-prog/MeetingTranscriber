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
    private var didReceiveNonEmptyTranscription = false

    func transcribe(
        recordingFile: RecordingFile,
        onResult: @escaping (String, Bool) -> Void,
        onCompletion: @escaping (SpeechTranscriberError?) -> Void
    ) {
        cancelTranscription()
        didFinishCurrentTranscription = false
        didReceiveNonEmptyTranscription = false
        transcribingRecordingURL = recordingFile.url

        guard FileManager.default.fileExists(atPath: recordingFile.url.path) else {
            finish(with: .recordingFileNotFound, onCompletion: onCompletion)
            return
        }

        do {
            let resourceValues = try recordingFile.url.resourceValues(forKeys: [.fileSizeKey])
            guard let fileSize = resourceValues.fileSize, fileSize > 0 else {
                finish(with: .recordingFileEmpty, onCompletion: onCompletion)
                return
            }
        } catch {
            finish(with: .recordingFileUnavailable(error.localizedDescription), onCompletion: onCompletion)
            return
        }

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
        request.taskHint = .dictation

        speechRecognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self else {
                    return
                }

                guard !self.didFinishCurrentTranscription else {
                    return
                }

                if let result {
                    let transcriptionText = result.bestTranscription.formattedString
                    let hasText = !transcriptionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

                    if hasText {
                        self.didReceiveNonEmptyTranscription = true
                        onResult(transcriptionText, result.isFinal)
                    }

                    if result.isFinal {
                        self.finish(
                            with: self.didReceiveNonEmptyTranscription ? nil : .noRecognizableSpeech,
                            onCompletion: onCompletion
                        )
                    }
                }

                if let error {
                    debugPrint("Speech recognition failed: \(error.localizedDescription)")

                    self.finish(
                        with: self.didReceiveNonEmptyTranscription ? nil : .recognitionFailed(error.localizedDescription),
                        onCompletion: onCompletion
                    )
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
        if let error {
            debugPrint("Finished transcription with error: \(error.logDescription)")
        }
        onCompletion(error)
    }
}

enum SpeechTranscriberError: Error {
    case recordingFileNotFound
    case recordingFileEmpty
    case recordingFileUnavailable(String)
    case speechPermissionDenied
    case speechRestricted
    case speechPermissionNotDetermined
    case speechAuthorizationFailed
    case japaneseRecognizerUnavailable
    case recognizerUnavailable
    case noRecognizableSpeech
    case recognitionFailed(String)

    var logDescription: String {
        switch self {
        case .recordingFileNotFound:
            return "Recording file was not found."
        case .recordingFileEmpty:
            return "Recording file was empty."
        case .recordingFileUnavailable(let detail):
            return "Recording file could not be checked: \(detail)"
        case .speechPermissionDenied:
            return "Speech recognition permission was denied."
        case .speechRestricted:
            return "Speech recognition is restricted."
        case .speechPermissionNotDetermined:
            return "Speech recognition permission is not determined."
        case .speechAuthorizationFailed:
            return "Speech recognition authorization failed."
        case .japaneseRecognizerUnavailable:
            return "Japanese speech recognizer is unavailable."
        case .recognizerUnavailable:
            return "Speech recognizer is currently unavailable."
        case .noRecognizableSpeech:
            return "No recognizable speech was found."
        case .recognitionFailed(let detail):
            return "Recognition failed: \(detail)"
        }
    }
}
