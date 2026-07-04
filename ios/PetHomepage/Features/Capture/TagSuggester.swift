// ios/PetHomepage/Features/Capture/TagSuggester.swift
import Foundation
import UIKit
import Vision

/// On-device OCR + fuzzy matching that suggests which chip (medication/activity) a just-captured
/// photo is probably of, e.g. a med bottle label. Pure garnish: never blocks save, never calls out
/// to the network, and silently returns nil when nothing matches.
enum TagSuggester {
    /// Index of the best-matching candidate name in the OCR'd text, or nil.
    ///
    /// A candidate matches when ALL of its "significant" words (length >= 3 after normalization)
    /// are present as whole words somewhere in the normalized OCR text. Candidates with zero
    /// significant words never match. Among matching candidates, the one with the most matched
    /// characters (sum of its significant words' lengths) wins; ties go to the earlier candidate.
    static func bestMatch(ocrText: String, candidateNames: [String]) -> Int? {
        let ocrWords = Set(normalizedWords(in: ocrText))
        guard !ocrWords.isEmpty else { return nil }

        var bestIndex: Int?
        var bestScore = 0

        for (index, name) in candidateNames.enumerated() {
            let words = normalizedWords(in: name)
            guard !words.isEmpty else { continue }
            guard words.allSatisfy({ ocrWords.contains($0) }) else { continue }

            let score = words.reduce(0) { $0 + $1.count }
            if score > bestScore {
                bestScore = score
                bestIndex = index
            }
        }

        return bestIndex
    }

    /// OCRs the photo off-main and matches. Returns the winning candidate index, or nil.
    static func suggest(photo: Data, candidateNames: [String]) async -> Int? {
        guard let cgImage = UIImage(data: photo)?.cgImage else { return nil }

        let text = await recognizeText(in: cgImage)
        guard let text, !text.isEmpty else { return nil }

        return bestMatch(ocrText: text, candidateNames: candidateNames)
    }

    /// Normalizes text (lowercase, diacritic-folded, non-alphanumeric -> space, whitespace
    /// collapsed) and splits it into words that are at least 3 characters long.
    private static func normalizedWords(in text: String) -> [String] {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        var normalized = ""
        normalized.reserveCapacity(folded.count)
        for scalar in folded.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                normalized.unicodeScalars.append(scalar)
            } else {
                normalized.append(" ")
            }
        }
        return normalized
            .split(separator: " ")
            .map(String.init)
            .filter { $0.count >= 3 }
    }

    private static func recognizeText(in cgImage: CGImage) async -> String? {
        await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                guard error == nil,
                      let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: nil)
                    return
                }
                let strings = observations.compactMap { $0.topCandidates(1).first?.string }
                continuation.resume(returning: strings.joined(separator: " "))
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: nil)
            }
        }
    }
}
