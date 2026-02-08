import Foundation

enum ExerciseVideoLibrary {
    // Add exercise name keys mapped to video URLs, e.g.
    // "bench press": "https://..."
    private static let videos: [String: String] = [:]

    static func url(for exerciseName: String) -> URL? {
        let key = normalize(exerciseName)
        if let direct = videos[key], let url = URL(string: direct) {
            return url
        }
        return nil
    }

    private static func normalize(_ name: String) -> String {
        let lowercased = name.lowercased()
        let allowed = lowercased.filter { $0.isLetter || $0.isNumber || $0 == " " }
        return allowed.replacingOccurrences(of: "  ", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
