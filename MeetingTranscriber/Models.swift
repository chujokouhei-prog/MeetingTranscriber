//
//  Models.swift
//  MeetingTranscriber
//
//  Created by Codex on 2026/06/13.
//

import Foundation

struct RecordingFile: Identifiable, Equatable {
    let id: String
    let name: String
    let createdAt: Date
    let url: URL

    var title: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy年M月d日 H:mm"

        return "\(formatter.string(from: createdAt)) の録音"
    }
}

struct SavedTranscription: Codable {
    let text: String
    let createdAt: Date
}

