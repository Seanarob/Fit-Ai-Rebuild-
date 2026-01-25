import Foundation

enum StartingPhotoType: String, CaseIterable, Codable, Identifiable {
    case front
    case side
    case back

    var id: String { rawValue }

    var title: String {
        switch self {
        case .front: return "Front"
        case .side: return "Side"
        case .back: return "Back"
        }
    }
}

struct StartingPhoto: Codable, Hashable {
    let url: String
    let date: Date
}

struct StartingPhotoEntry: Identifiable, Hashable {
    let id: String
    let type: StartingPhotoType
    let photo: StartingPhoto
}

struct StartingPhotosState: Codable, Hashable {
    var front: StartingPhoto?
    var side: StartingPhoto?
    var back: StartingPhoto?

    var summary: String {
        let total = [front, side, back].compactMap { $0 }.count
        return total == 3 ? "Complete" : "\(total)/3 uploaded"
    }

    var isEmpty: Bool {
        [front, side, back].allSatisfy { $0 == nil }
    }

    var entries: [StartingPhotoEntry] {
        var results: [StartingPhotoEntry] = []
        if let front {
            results.append(StartingPhotoEntry(id: "front", type: .front, photo: front))
        }
        if let side {
            results.append(StartingPhotoEntry(id: "side", type: .side, photo: side))
        }
        if let back {
            results.append(StartingPhotoEntry(id: "back", type: .back, photo: back))
        }
        return results
    }

    func url(for type: StartingPhotoType) -> String {
        switch type {
        case .front: return front?.url ?? ""
        case .side: return side?.url ?? ""
        case .back: return back?.url ?? ""
        }
    }

    func date(for type: StartingPhotoType) -> Date? {
        switch type {
        case .front: return front?.date
        case .side: return side?.date
        case .back: return back?.date
        }
    }

    mutating func set(url: String?, for type: StartingPhotoType) {
        let trimmed = url?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let photo = trimmed.isEmpty ? nil : StartingPhoto(url: trimmed, date: Date())
        switch type {
        case .front:
            front = photo
        case .side:
            side = photo
        case .back:
            back = photo
        }
    }

    func asDictionary() -> [String: Any] {
        var payload: [String: Any] = [:]
        if let front {
            payload["front"] = Self.photoPayload(from: front)
        }
        if let side {
            payload["side"] = Self.photoPayload(from: side)
        }
        if let back {
            payload["back"] = Self.photoPayload(from: back)
        }
        return payload
    }

    static func fromDictionary(_ value: Any) -> StartingPhotosState? {
        guard let dict = value as? [String: Any] else { return nil }
        var state = StartingPhotosState()
        state.front = photo(from: dict["front"])
        state.side = photo(from: dict["side"])
        state.back = photo(from: dict["back"])
        return state
    }

    private static let isoFormatter = ISO8601DateFormatter()

    private static func photoPayload(from photo: StartingPhoto) -> [String: Any] {
        [
            "url": photo.url,
            "date": isoFormatter.string(from: photo.date),
        ]
    }

    private static func photo(from value: Any?) -> StartingPhoto? {
        guard let dict = value as? [String: Any],
              let url = dict["url"] as? String,
              !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return nil
        }
        let dateString = dict["date"] as? String
        let date = dateString.flatMap { isoFormatter.date(from: $0) } ?? Date()
        return StartingPhoto(url: url, date: date)
    }
}

enum StartingPhotosStore {
    static let storageKey = "fitai.more.startingPhotos"

    static func load() -> StartingPhotosState {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode(StartingPhotosState.self, from: data)
        else {
            return StartingPhotosState()
        }
        return decoded
    }

    static func save(_ state: StartingPhotosState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
