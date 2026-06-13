//
//  TranscriptionFormatter.swift
//  MeetingTranscriber
//
//  Created by Codex on 2026/06/13.
//

import Foundation

enum TranscriptionFormatter {
    static let currentVersion = 1

    static func formattedJapaneseText(from rawText: String) -> String {
        let normalizedText = rawText
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedText.isEmpty else {
            return ""
        }

        let punctuatedText = addSentencePunctuation(to: addCommas(to: normalizedText))
        return addParagraphBreaks(to: punctuatedText)
    }

    private static func addCommas(to text: String) -> String {
        let connectors = [
            "まず", "次に", "一方で", "ただし", "また", "そして", "それで", "なので",
            "つまり", "例えば", "なお", "ちなみに", "では", "はい", "えー", "えっと"
        ]
        var formattedText = text

        for connector in connectors {
            formattedText = formattedText.replacingOccurrences(
                of: "\(connector)(?![、。！？!?\\s])",
                with: "\(connector)、",
                options: .regularExpression
            )
        }

        return formattedText
    }

    private static func addSentencePunctuation(to text: String) -> String {
        var sentences: [String] = []
        var currentSentence = ""
        var characterCountSinceBreak = 0
        let sentenceEndings = [
            "お願いします", "ありがとうございました", "かと思います", "と思います",
            "してください", "していきます", "になっています", "となっています",
            "しています", "しました", "しましたね", "しましたよ", "でした",
            "ですね", "ですよ", "でしょう", "ください", "あります", "なります",
            "します", "です", "ます", "ません"
        ]
        let hardPunctuation = CharacterSet(charactersIn: "。！？!?")

        for character in text {
            currentSentence.append(character)
            characterCountSinceBreak += 1

            if String(character).rangeOfCharacter(from: hardPunctuation) != nil {
                appendSentence(&currentSentence, to: &sentences)
                characterCountSinceBreak = 0
                continue
            }

            guard characterCountSinceBreak >= 18 else {
                continue
            }

            let shouldBreakAtEnding = sentenceEndings.contains { currentSentence.hasSuffix($0) }
            let shouldBreakLongPhrase = characterCountSinceBreak >= 72 && ["ね", "よ", "か", "が", "で"].contains(String(character))

            if shouldBreakAtEnding || shouldBreakLongPhrase {
                currentSentence.append("。")
                appendSentence(&currentSentence, to: &sentences)
                characterCountSinceBreak = 0
            }
        }

        appendSentence(&currentSentence, to: &sentences, addFinalPeriod: true)
        return sentences.joined()
    }

    private static func appendSentence(
        _ sentence: inout String,
        to sentences: inout [String],
        addFinalPeriod: Bool = false
    ) {
        var trimmedSentence = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSentence.isEmpty else {
            sentence = ""
            return
        }

        if addFinalPeriod,
           trimmedSentence.range(of: #"[。！？!?]$"#, options: .regularExpression) == nil {
            trimmedSentence.append("。")
        }

        sentences.append(trimmedSentence)
        sentence = ""
    }

    private static func addParagraphBreaks(to text: String) -> String {
        let sentences = splitSentences(text)

        guard !sentences.isEmpty else {
            return text
        }

        let paragraphStarters = ["まず、", "次に、", "一方で、", "ただし、", "また、", "では、", "なお、", "ちなみに、"]
        var paragraphs: [String] = []
        var currentParagraph: [String] = []
        var currentLength = 0

        for sentence in sentences {
            let startsNewTopic = paragraphStarters.contains { sentence.hasPrefix($0) }
            let shouldStartNewParagraph = !currentParagraph.isEmpty && (startsNewTopic || currentParagraph.count >= 3 || currentLength >= 140)

            if shouldStartNewParagraph {
                paragraphs.append(currentParagraph.joined())
                currentParagraph = []
                currentLength = 0
            }

            currentParagraph.append(sentence)
            currentLength += sentence.count
        }

        if !currentParagraph.isEmpty {
            paragraphs.append(currentParagraph.joined())
        }

        return paragraphs.joined(separator: "\n\n")
    }

    private static func splitSentences(_ text: String) -> [String] {
        var sentences: [String] = []
        var currentSentence = ""
        let punctuation = CharacterSet(charactersIn: "。！？!?")

        for character in text {
            currentSentence.append(character)

            if String(character).rangeOfCharacter(from: punctuation) != nil {
                let trimmedSentence = currentSentence.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedSentence.isEmpty {
                    sentences.append(trimmedSentence)
                }
                currentSentence = ""
            }
        }

        let trimmedSentence = currentSentence.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedSentence.isEmpty {
            sentences.append(trimmedSentence)
        }

        return sentences
    }
}
