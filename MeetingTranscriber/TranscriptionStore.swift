//
//  TranscriptionStore.swift
//  MeetingTranscriber
//
//  Created by Codex on 2026/06/13.
//

import Foundation
import Combine

final class TranscriptionStore: ObservableObject {
    @Published private(set) var transcriptions: [String: SavedTranscription] = [:]

    private let userDefaultsKey = "savedTranscriptions"

    func loadSavedTranscriptions() {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey) else {
            return
        }

        do {
            transcriptions = try JSONDecoder().decode([String: SavedTranscription].self, from: data)
        } catch {
            debugPrint("Failed to load transcriptions: \(error.localizedDescription)")
        }
    }

    func transcription(for recordingFile: RecordingFile) -> SavedTranscription? {
        transcriptions[recordingFile.id] ?? transcriptions[recordingFile.name]
    }

    func updateTranscription(text: String, for recordingFile: RecordingFile) {
        let formattedText = TranscriptionFormatter.formattedJapaneseText(from: text)

        transcriptions[recordingFile.id] = SavedTranscription(
            text: formattedText,
            createdAt: Date(),
            rawText: text,
            formattedText: formattedText,
            textBundle: TranscriptionTextBundle(
                recognizedText: text,
                readableText: formattedText,
                formatterVersion: TranscriptionFormatter.currentVersion
            )
        )
    }

    func handleRename(_ result: RecordingRenameResult) {
        let possibleOldKeys = [
            result.oldRecording.id,
            result.oldRecording.name,
            result.newRecording.name
        ]

        for oldKey in possibleOldKeys {
            guard oldKey != result.newRecording.id,
                  let transcription = transcriptions[oldKey] else {
                continue
            }

            transcriptions[oldKey] = nil
            transcriptions[result.newRecording.id] = transcription
            saveTranscriptions()
            return
        }
    }

    func deleteTranscription(for recordingFile: RecordingFile) {
        let possibleKeys = [
            recordingFile.id,
            recordingFile.name
        ]
        var didChange = false

        for key in possibleKeys where transcriptions[key] != nil {
            transcriptions[key] = nil
            didChange = true
        }

        if didChange {
            saveTranscriptions()
        }
    }

    func migrateFilenameKeysIfNeeded(recordingFiles: [RecordingFile]) {
        var didChange = false

        for recordingFile in recordingFiles {
            guard transcriptions[recordingFile.id] == nil,
                  let transcription = transcriptions[recordingFile.name] else {
                continue
            }

            transcriptions[recordingFile.name] = nil
            transcriptions[recordingFile.id] = transcription
            didChange = true
        }

        if didChange {
            saveTranscriptions()
        }
    }

    func deleteOldTranscriptionResults(recordingFiles: [RecordingFile]) {
        let now = Date()
        let validRecordingIDs = Set(recordingFiles.map(\.id))
        var updatedTranscriptions = transcriptions

        for (recordingID, transcription) in transcriptions {
            let isRecordingFileDeleted = !validRecordingIDs.contains(recordingID)
            let isOlderThanOneDay = now.timeIntervalSince(transcription.createdAt) >= DataRetention.duration

            if isRecordingFileDeleted || isOlderThanOneDay {
                updatedTranscriptions[recordingID] = nil

                if isRecordingFileDeleted {
                    debugPrint("Deleted transcription because recording file is missing: \(recordingID)")
                } else {
                    debugPrint("Deleted old transcription: \(recordingID)")
                }
            }
        }

        if updatedTranscriptions.count != transcriptions.count {
            transcriptions = updatedTranscriptions
            saveTranscriptions()
        }
    }

    func saveTranscriptions() {
        do {
            let data = try JSONEncoder().encode(transcriptions)
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        } catch {
            debugPrint("Failed to save transcriptions: \(error.localizedDescription)")
        }
    }
}
