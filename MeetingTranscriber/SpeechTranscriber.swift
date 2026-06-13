//
//  SpeechTranscriber.swift
//  MeetingTranscriber
//
//  Created by Codex on 2026/06/13.
//

import Foundation
import AVFoundation
import Speech
import Combine

final class SpeechTranscriber: ObservableObject {
    @Published private(set) var transcribingRecordingURL: URL?

    private let recognitionLocale = Locale(identifier: "ja_JP")
    private let recognitionSegmentDuration: TimeInterval = 45
    private let meetingContextualStrings = [
        "打ち合わせ", "会議", "議事録", "確認事項", "決定事項", "宿題", "課題", "論点",
        "スケジュール", "見積もり", "納期", "予算", "契約", "資料", "共有", "相談",
        "次回", "担当", "対応", "検討", "確認", "お願いします", "ありがとうございます"
    ]

    private var speechRecognitionTask: SFSpeechRecognitionTask?
    private var audioExportSession: AVAssetExportSession?
    private var modernRecognitionTask: Task<Void, Never>?
    private var temporarySegmentURLs: [URL] = []
    private var collectedSegmentTexts: [String] = []
    private var didFinishCurrentTranscription = false
    private var didReceiveNonEmptyTranscription = false
    private var didReceiveFinalTranscription = false

    func transcribe(
        recordingFile: RecordingFile,
        onResult: @escaping (String, Bool) -> Void,
        onCompletion: @escaping (SpeechTranscriberError?) -> Void
    ) {
        cancelTranscription()
        didFinishCurrentTranscription = false
        didReceiveNonEmptyTranscription = false
        didReceiveFinalTranscription = false
        collectedSegmentTexts = []
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
                    if #available(iOS 26.0, *) {
                        self.startModernDictationRecognition(
                            for: recordingFile,
                            onResult: onResult,
                            onCompletion: onCompletion
                        )
                        return
                    }

                    self.prepareRecognitionSegments(for: recordingFile.url) { result in
                        switch result {
                        case .success(let segmentURLs):
                            self.startSpeechRecognition(
                                for: recordingFile,
                                segmentURLs: segmentURLs,
                                onResult: onResult,
                                onCompletion: onCompletion
                            )
                        case .failure(let error):
                            self.finish(with: error, onCompletion: onCompletion)
                        }
                    }
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
        modernRecognitionTask?.cancel()
        modernRecognitionTask = nil
        audioExportSession?.cancelExport()
        audioExportSession = nil
        speechRecognitionTask?.cancel()
        speechRecognitionTask = nil
        transcribingRecordingURL = nil
        didFinishCurrentTranscription = true
        deleteTemporarySegments()
    }

    @available(iOS 26.0, *)
    private func startModernDictationRecognition(
        for recordingFile: RecordingFile,
        onResult: @escaping (String, Bool) -> Void,
        onCompletion: @escaping (SpeechTranscriberError?) -> Void
    ) {
        modernRecognitionTask?.cancel()
        modernRecognitionTask = Task { [weak self] in
            guard let self else {
                return
            }

            do {
                let transcriptionText = try await self.modernDictationTranscription(for: recordingFile) { text, isFinal in
                    DispatchQueue.main.async {
                        onResult(text, isFinal)
                    }
                }

                await MainActor.run {
                    self.didReceiveNonEmptyTranscription = !transcriptionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    self.finish(
                        with: self.didReceiveNonEmptyTranscription ? nil : .noRecognizableSpeech,
                        onCompletion: onCompletion
                    )
                }
            } catch is CancellationError {
                await MainActor.run {
                    self.finish(with: .recognitionFailed("文字起こしがキャンセルされました。"), onCompletion: onCompletion)
                }
            } catch {
                debugPrint("Modern dictation recognition failed: \(error.localizedDescription)")
                await MainActor.run {
                    guard !self.didFinishCurrentTranscription else {
                        return
                    }

                    self.prepareRecognitionSegments(for: recordingFile.url) { result in
                        switch result {
                        case .success(let segmentURLs):
                            self.startSpeechRecognition(
                                for: recordingFile,
                                segmentURLs: segmentURLs,
                                onResult: onResult,
                                onCompletion: onCompletion
                            )
                        case .failure(let fallbackError):
                            self.finish(with: fallbackError, onCompletion: onCompletion)
                        }
                    }
                }
            }
        }
    }

    @available(iOS 26.0, *)
    private func modernDictationTranscription(
        for recordingFile: RecordingFile,
        onResult: @escaping (String, Bool) -> Void
    ) async throws -> String {
        let transcriber = Speech.DictationTranscriber(
            locale: recognitionLocale,
            contentHints: [.farField],
            transcriptionOptions: [.punctuation, .etiquetteReplacements],
            reportingOptions: [.alternativeTranscriptions, .frequentFinalization],
            attributeOptions: [.audioTimeRange, .transcriptionConfidence]
        )
        let modules: [any SpeechModule] = [transcriber]
        let assetStatus = await Speech.AssetInventory.status(forModules: modules)

        if assetStatus == .unsupported {
            throw SpeechTranscriberError.recognitionFailed("この端末では新しい音声認識モデルを使用できません。")
        }

        if assetStatus < .installed,
           let installationRequest = try await Speech.AssetInventory.assetInstallationRequest(supporting: modules) {
            try await installationRequest.downloadAndInstall()
        }

        let analysisContext = Speech.AnalysisContext()
        analysisContext.contextualStrings[.general] = meetingContextualStrings

        let audioFile = try AVAudioFile(forReading: recordingFile.url)
        let analyzer = try await Speech.SpeechAnalyzer(
            inputAudioFile: audioFile,
            modules: modules,
            options: Speech.SpeechAnalyzer.Options(priority: .userInitiated, modelRetention: .whileInUse),
            analysisContext: analysisContext,
            finishAfterFile: true
        )

        var finalizedTexts: [TimeInterval: String] = [:]

        for try await result in transcriber.results {
            try Task.checkCancellation()

            let text = String(result.text.characters)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard !text.isEmpty else {
                continue
            }

            if result.isFinal {
                finalizedTexts[result.range.start.seconds] = text
            }

            let combinedText = combinedModernTranscription(
                finalizedTexts: finalizedTexts,
                currentText: result.isFinal ? nil : text
            )
            onResult(combinedText, result.isFinal)
        }

        _ = analyzer
        return combinedModernTranscription(finalizedTexts: finalizedTexts, currentText: nil)
    }

    private func combinedModernTranscription(
        finalizedTexts: [TimeInterval: String],
        currentText: String?
    ) -> String {
        var textParts = finalizedTexts
            .sorted { $0.key < $1.key }
            .map(\.value)

        if let currentText,
           !currentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            textParts.append(currentText)
        }

        return textParts.joined(separator: "\n")
    }

    private func prepareRecognitionSegments(
        for recordingURL: URL,
        completion: @escaping (Result<[URL], SpeechTranscriberError>) -> Void
    ) {
        let asset = AVURLAsset(url: recordingURL)
        let duration = CMTimeGetSeconds(asset.duration)

        guard duration.isFinite, duration > recognitionSegmentDuration + 5 else {
            completion(.success([recordingURL]))
            return
        }

        exportSegment(
            from: asset,
            originalURL: recordingURL,
            startTime: 0,
            index: 0,
            segmentURLs: [],
            completion: completion
        )
    }

    private func exportSegment(
        from asset: AVURLAsset,
        originalURL: URL,
        startTime: TimeInterval,
        index: Int,
        segmentURLs: [URL],
        completion: @escaping (Result<[URL], SpeechTranscriberError>) -> Void
    ) {
        guard !didFinishCurrentTranscription else {
            return
        }

        let assetDuration = CMTimeGetSeconds(asset.duration)
        guard startTime < assetDuration else {
            temporarySegmentURLs = segmentURLs
            completion(.success(segmentURLs.isEmpty ? [originalURL] : segmentURLs))
            return
        }

        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            completion(.failure(.audioSegmentPreparationFailed("音声を分割する準備ができませんでした。")))
            return
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MeetingTranscriber-\(UUID().uuidString)-\(index).m4a")
        let segmentDuration = min(recognitionSegmentDuration, assetDuration - startTime)
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .m4a
        exportSession.timeRange = CMTimeRange(
            start: CMTime(seconds: startTime, preferredTimescale: 600),
            duration: CMTime(seconds: segmentDuration, preferredTimescale: 600)
        )
        audioExportSession = exportSession

        exportSession.exportAsynchronously { [weak self] in
            DispatchQueue.main.async {
                guard let self, !self.didFinishCurrentTranscription else {
                    return
                }

                self.audioExportSession = nil

                switch exportSession.status {
                case .completed:
                    var updatedSegmentURLs = segmentURLs
                    updatedSegmentURLs.append(outputURL)
                    self.exportSegment(
                        from: asset,
                        originalURL: originalURL,
                        startTime: startTime + self.recognitionSegmentDuration,
                        index: index + 1,
                        segmentURLs: updatedSegmentURLs,
                        completion: completion
                    )
                case .failed:
                    let detail = exportSession.error?.localizedDescription ?? "不明なエラー"
                    self.deleteTemporarySegments(segmentURLs + [outputURL])
                    completion(.failure(.audioSegmentPreparationFailed(detail)))
                case .cancelled:
                    self.deleteTemporarySegments(segmentURLs + [outputURL])
                    completion(.failure(.audioSegmentPreparationFailed("音声分割がキャンセルされました。")))
                default:
                    self.deleteTemporarySegments(segmentURLs + [outputURL])
                    completion(.failure(.audioSegmentPreparationFailed("音声分割を完了できませんでした。")))
                }
            }
        }
    }

    private func startSpeechRecognition(
        for recordingFile: RecordingFile,
        segmentURLs: [URL],
        onResult: @escaping (String, Bool) -> Void,
        onCompletion: @escaping (SpeechTranscriberError?) -> Void
    ) {
        guard let speechRecognizer = SFSpeechRecognizer(locale: recognitionLocale) else {
            finish(with: .japaneseRecognizerUnavailable, onCompletion: onCompletion)
            return
        }

        guard speechRecognizer.isAvailable else {
            finish(with: .recognizerUnavailable, onCompletion: onCompletion)
            return
        }

        collectedSegmentTexts = Array(repeating: "", count: segmentURLs.count)
        recognizeSegment(
            at: 0,
            segmentURLs: segmentURLs,
            speechRecognizer: speechRecognizer,
            recordingFile: recordingFile,
            onResult: onResult,
            onCompletion: onCompletion
        )
    }

    private func recognizeSegment(
        at index: Int,
        segmentURLs: [URL],
        speechRecognizer: SFSpeechRecognizer,
        recordingFile: RecordingFile,
        onResult: @escaping (String, Bool) -> Void,
        onCompletion: @escaping (SpeechTranscriberError?) -> Void
    ) {
        guard !didFinishCurrentTranscription else {
            return
        }

        guard index < segmentURLs.count else {
            finish(
                with: didReceiveNonEmptyTranscription ? nil : .noRecognizableSpeech,
                onCompletion: onCompletion
            )
            return
        }

        let request = makeRecognitionRequest(for: segmentURLs[index], recordingFile: recordingFile)

        speechRecognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self, !self.didFinishCurrentTranscription else {
                    return
                }

                if let result {
                    let transcriptionText = result.bestTranscription.formattedString
                    let trimmedText = transcriptionText.trimmingCharacters(in: .whitespacesAndNewlines)

                    if !trimmedText.isEmpty {
                        self.didReceiveNonEmptyTranscription = true
                        let combinedText = self.combinedTranscription(
                            replacingSegmentAt: index,
                            with: trimmedText
                        )
                        onResult(combinedText, result.isFinal && index == segmentURLs.count - 1)
                    }

                    if result.isFinal {
                        self.didReceiveFinalTranscription = true
                        self.collectedSegmentTexts[index] = trimmedText
                        self.speechRecognitionTask = nil
                        self.recognizeSegment(
                            at: index + 1,
                            segmentURLs: segmentURLs,
                            speechRecognizer: speechRecognizer,
                            recordingFile: recordingFile,
                            onResult: onResult,
                            onCompletion: onCompletion
                        )
                        return
                    }
                }

                if let error {
                    debugPrint("Speech recognition failed: \(error.localizedDescription)")

                    if self.isNoSpeechDetectedError(error) {
                        self.collectedSegmentTexts[index] = ""
                        self.speechRecognitionTask = nil
                        self.recognizeSegment(
                            at: index + 1,
                            segmentURLs: segmentURLs,
                            speechRecognizer: speechRecognizer,
                            recordingFile: recordingFile,
                            onResult: onResult,
                            onCompletion: onCompletion
                        )
                        return
                    }

                    self.finish(with: .recognitionFailed(error.localizedDescription), onCompletion: onCompletion)
                }
            }
        }
    }

    private func makeRecognitionRequest(
        for segmentURL: URL,
        recordingFile: RecordingFile
    ) -> SFSpeechURLRecognitionRequest {
        let request = SFSpeechURLRecognitionRequest(url: segmentURL)
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        request.contextualStrings = meetingContextualStrings
        request.interactionIdentifier = recordingFile.id
        if #available(iOS 13, *) {
            request.requiresOnDeviceRecognition = false
        }
        if #available(iOS 16, *) {
            request.addsPunctuation = true
        }

        return request
    }

    private func combinedTranscription(replacingSegmentAt index: Int, with text: String) -> String {
        var segmentTexts = collectedSegmentTexts
        if segmentTexts.indices.contains(index) {
            segmentTexts[index] = text
        }

        return segmentTexts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private func isNoSpeechDetectedError(_ error: Error) -> Bool {
        let nsError = error as NSError
        let errorText = "\(nsError.localizedDescription) \(nsError.userInfo)"
            .lowercased()

        return errorText.contains("no speech")
            || errorText.contains("speech not detected")
            || errorText.contains("音声が検出")
    }

    private func finish(
        with error: SpeechTranscriberError?,
        onCompletion: @escaping (SpeechTranscriberError?) -> Void
    ) {
        guard !didFinishCurrentTranscription else {
            return
        }

        didFinishCurrentTranscription = true
        audioExportSession?.cancelExport()
        audioExportSession = nil
        speechRecognitionTask = nil
        transcribingRecordingURL = nil
        deleteTemporarySegments()
        if let error {
            debugPrint("Finished transcription with error: \(error.logDescription)")
        }
        onCompletion(error)
    }

    private func deleteTemporarySegments(_ segmentURLs: [URL]? = nil) {
        let urls = segmentURLs ?? temporarySegmentURLs

        for url in urls where url.path.hasPrefix(FileManager.default.temporaryDirectory.path) {
            try? FileManager.default.removeItem(at: url)
        }

        if segmentURLs == nil {
            temporarySegmentURLs = []
        }
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
    case audioSegmentPreparationFailed(String)
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
        case .audioSegmentPreparationFailed(let detail):
            return "Audio could not be split for recognition: \(detail)"
        case .noRecognizableSpeech:
            return "No recognizable speech was found."
        case .recognitionFailed(let detail):
            return "Recognition failed: \(detail)"
        }
    }
}
