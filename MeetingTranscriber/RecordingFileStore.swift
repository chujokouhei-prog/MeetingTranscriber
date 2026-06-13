//
//  RecordingFileStore.swift
//  MeetingTranscriber
//
//  Created by Codex on 2026/06/13.
//

import Foundation
import Combine

struct RecordingRenameResult {
    let oldRecording: RecordingFile
    let newRecording: RecordingFile
}

final class RecordingFileStore: ObservableObject {
    @Published private(set) var recordingFiles: [RecordingFile] = []

    func loadRecordingFiles() throws {
        try deleteOldRecordingFiles()

        let fileURLs = try FileManager.default.contentsOfDirectory(
            at: documentsFolderURL(),
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        )

        recordingFiles = fileURLs
            .filter { $0.pathExtension.lowercased() == "m4a" }
            .compactMap { recordingFile(from: $0) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func newRecordingURL() -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm"

        let baseFileName = "meeting_\(formatter.string(from: Date()))"
        return uniqueRecordingURL(baseFileName: baseFileName)
    }

    func rename(_ recordingFile: RecordingFile, to newName: String) throws -> RecordingRenameResult {
        let sanitizedName = sanitizedRecordingName(from: newName)

        guard !sanitizedName.isEmpty else {
            throw RecordingFileStoreError.emptyName
        }

        guard FileManager.default.fileExists(atPath: recordingFile.url.path) else {
            throw RecordingFileStoreError.fileNotFound
        }

        let newURL = uniqueRecordingURL(
            baseFileName: sanitizedName,
            excluding: recordingFile.url
        )

        if newURL == recordingFile.url {
            throw RecordingFileStoreError.nameNotChanged
        }

        try FileManager.default.moveItem(at: recordingFile.url, to: newURL)
        try? FileManager.default.setAttributes(
            [.creationDate: recordingFile.createdAt],
            ofItemAtPath: newURL.path
        )

        guard let newRecording = self.recordingFile(from: newURL) else {
            throw RecordingFileStoreError.renamedFileNotFound
        }

        recordingFiles = recordingFiles
            .map { $0.id == recordingFile.id ? newRecording : $0 }
            .sorted { $0.createdAt > $1.createdAt }

        return RecordingRenameResult(
            oldRecording: recordingFile,
            newRecording: newRecording
        )
    }

    func documentsFolderURL() -> URL {
        FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        )[0]
    }

    private func recordingFile(from fileURL: URL) -> RecordingFile? {
        let values = try? fileURL.resourceValues(forKeys: [.creationDateKey])

        guard let createdAt = values?.creationDate else {
            return nil
        }

        return RecordingFile(
            id: recordingID(createdAt: createdAt),
            name: fileURL.lastPathComponent,
            createdAt: createdAt,
            url: fileURL
        )
    }

    private func recordingID(createdAt: Date) -> String {
        String(Int(createdAt.timeIntervalSince1970 * 1000))
    }

    private func uniqueRecordingURL(baseFileName: String) -> URL {
        let documentsFolder = documentsFolderURL()
        var fileURL = documentsFolder.appendingPathComponent("\(baseFileName).m4a")
        var number = 2

        while FileManager.default.fileExists(atPath: fileURL.path) {
            fileURL = documentsFolder.appendingPathComponent("\(baseFileName)_\(number).m4a")
            number += 1
        }

        return fileURL
    }

    private func uniqueRecordingURL(baseFileName: String, excluding excludedURL: URL) -> URL {
        let documentsFolder = documentsFolderURL()
        var fileURL = documentsFolder.appendingPathComponent("\(baseFileName).m4a")
        var number = 2

        while FileManager.default.fileExists(atPath: fileURL.path) && fileURL != excludedURL {
            fileURL = documentsFolder.appendingPathComponent("\(baseFileName)_\(number).m4a")
            number += 1
        }

        return fileURL
    }

    private func sanitizedRecordingName(from name: String) -> String {
        var sanitizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)

        if sanitizedName.lowercased().hasSuffix(".m4a") {
            sanitizedName.removeLast(4)
            sanitizedName = sanitizedName.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let unsafeCharacters = CharacterSet(charactersIn: "/\\:*?\"<>|")
            .union(.newlines)
            .union(.controlCharacters)

        return sanitizedName
            .components(separatedBy: unsafeCharacters)
            .filter { !$0.isEmpty }
            .joined(separator: "_")
    }

    private func deleteOldRecordingFiles() throws {
        let fileURLs = try FileManager.default.contentsOfDirectory(
            at: documentsFolderURL(),
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        )

        let now = Date()
        let oneDay: TimeInterval = 24 * 60 * 60

        for fileURL in fileURLs where fileURL.pathExtension.lowercased() == "m4a" {
            let values = try fileURL.resourceValues(forKeys: [.creationDateKey])

            guard let createdAt = values.creationDate else {
                continue
            }

            if now.timeIntervalSince(createdAt) >= oneDay {
                try FileManager.default.removeItem(at: fileURL)
                debugPrint("Deleted old recording file: \(fileURL.lastPathComponent)")
            }
        }
    }
}

enum RecordingFileStoreError: LocalizedError {
    case emptyName
    case nameNotChanged
    case fileNotFound
    case renamedFileNotFound

    var errorDescription: String? {
        switch self {
        case .emptyName:
            return "録音名を入力してください。"
        case .nameNotChanged:
            return "録音名は変更されていません"
        case .fileNotFound:
            return "録音ファイルが見つかりません。録音一覧を開き直してください。"
        case .renamedFileNotFound:
            return "名前変更後の録音ファイルを確認できませんでした。"
        }
    }
}
