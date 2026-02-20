import Foundation

struct LocalProgressPhoto: Codable, Hashable, Identifiable {
    let id: UUID
    let userId: String
    let remoteURL: String?
    let localFilename: String
    let date: Date
    let type: String?
    let category: String?
}

enum ProgressPhotoLocalStore {
    static let maxPhotosPerUser = 300

    private static let storageKey = "fitai.progressPhotos.local.v1"
    private static let directoryName = "ProgressPhotos"
    private static let fileManager = FileManager.default

    static func load(userId: String) -> [LocalProgressPhoto] {
        let all = loadAll()
        return all
            .filter { $0.userId == userId }
            .sorted { $0.date > $1.date }
    }

    static func date(forRemoteURL remoteURL: String, userId: String) -> Date? {
        load(userId: userId).first(where: { $0.remoteURL == remoteURL })?.date
    }

    @discardableResult
    static func save(
        imageData: Data,
        userId: String,
        remoteURL: String?,
        date: Date,
        type: String?,
        category: String?
    ) -> LocalProgressPhoto? {
        var all = loadAll()

        if let remoteURL,
           let existingIndex = all.firstIndex(where: { $0.userId == userId && $0.remoteURL == remoteURL }) {
            let existing = all[existingIndex]
            if !fileExists(userId: userId, filename: existing.localFilename) {
                _ = writeImageData(imageData, userId: userId, filename: existing.localFilename)
            }
            return existing
        }

        let id = UUID()
        let normalizedDate = Calendar.current.startOfDay(for: date)
        let filename = "\(dayString(from: normalizedDate))-\(id.uuidString).jpg"

        guard writeImageData(imageData, userId: userId, filename: filename) else {
            return nil
        }

        let photo = LocalProgressPhoto(
            id: id,
            userId: userId,
            remoteURL: remoteURL,
            localFilename: filename,
            date: normalizedDate,
            type: type,
            category: category
        )

        all.append(photo)
        all = prune(all, userId: userId)
        saveAll(all)
        NotificationCenter.default.post(name: .fitAIProgressPhotosUpdated, object: nil)
        return photo
    }

    static func fileURL(userId: String, filename: String) -> URL? {
        guard let base = baseDirectoryURL(userId: userId) else { return nil }
        return base.appendingPathComponent(filename, isDirectory: false)
    }

    // MARK: - Internals

    private static func loadAll() -> [LocalProgressPhoto] {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return [] }
        return (try? JSONDecoder().decode([LocalProgressPhoto].self, from: data)) ?? []
    }

    private static func saveAll(_ photos: [LocalProgressPhoto]) {
        guard let data = try? JSONEncoder().encode(photos) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private static func baseDirectoryURL(userId: String) -> URL? {
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }

        let safeUserId = sanitizePathComponent(userId)
        let root = appSupport
            .appendingPathComponent(directoryName, isDirectory: true)
            .appendingPathComponent(safeUserId, isDirectory: true)

        do {
            try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var mutableRoot = root
            try? mutableRoot.setResourceValues(values)
            return root
        } catch {
            return nil
        }
    }

    private static func writeImageData(_ data: Data, userId: String, filename: String) -> Bool {
        guard let url = fileURL(userId: userId, filename: filename) else { return false }
        do {
            try data.write(to: url, options: [.atomic])
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var mutableURL = url
            try? mutableURL.setResourceValues(values)
            return true
        } catch {
            return false
        }
    }

    private static func fileExists(userId: String, filename: String) -> Bool {
        guard let url = fileURL(userId: userId, filename: filename) else { return false }
        return fileManager.fileExists(atPath: url.path)
    }

    private static func prune(_ photos: [LocalProgressPhoto], userId: String) -> [LocalProgressPhoto] {
        let userPhotos = photos.filter { $0.userId == userId }.sorted { $0.date > $1.date }
        guard userPhotos.count > maxPhotosPerUser else { return photos }

        let keepIds = Set(userPhotos.prefix(maxPhotosPerUser).map(\.id))
        var pruned: [LocalProgressPhoto] = []
        pruned.reserveCapacity(photos.count)
        for photo in photos {
            if photo.userId != userId || keepIds.contains(photo.id) {
                pruned.append(photo)
            } else {
                if let url = fileURL(userId: userId, filename: photo.localFilename) {
                    try? fileManager.removeItem(at: url)
                }
            }
        }
        return pruned
    }

    private static func dayString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }

    private static func sanitizePathComponent(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let filtered = value.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? String(scalar) : "-"
        }.joined()
        return filtered.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}

extension Notification.Name {
    static let fitAIProgressPhotosUpdated = Notification.Name("fitai.progressPhotos.updated")
}
