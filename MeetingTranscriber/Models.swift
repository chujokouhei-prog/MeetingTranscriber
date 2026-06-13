//
//  Models.swift
//  MeetingTranscriber
//
//  Created by Codex on 2026/06/13.
//

import Foundation

enum DataRetention {
    static let duration: TimeInterval = 24 * 60 * 60
}

struct RecordingFile: Identifiable, Equatable {
    let id: String
    let name: String
    let createdAt: Date
    let url: URL

    var deletionDate: Date {
        createdAt.addingTimeInterval(DataRetention.duration)
    }

    var title: String {
        let fileName = url.deletingPathExtension().lastPathComponent

        if !isDefaultRecordingFileName(fileName) {
            return fileName
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy年M月d日 H:mm"

        return "\(formatter.string(from: createdAt)) の録音"
    }

    private func isDefaultRecordingFileName(_ fileName: String) -> Bool {
        let pattern = #"^meeting_\d{4}-\d{2}-\d{2}_\d{2}-\d{2}(?:_\d+)?$"#
        return fileName.range(of: pattern, options: .regularExpression) != nil
    }
}

struct SavedTranscription: Codable {
    let text: String
    let createdAt: Date
}
