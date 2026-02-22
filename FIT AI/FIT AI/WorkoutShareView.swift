import SwiftUI
import PhotosUI
import UIKit

struct WorkoutShareData: Identifiable {
    struct TopLift {
        let name: String
        let reps: Int
        let weight: Double?
        let unit: WeightUnit
    }

    let id = UUID()
    let title: String
    let durationSeconds: Int
    let totalVolume: Double
    let volumeUnit: WeightUnit
    let topLift: TopLift
    let prCount: Int
    let weeklyStreak: Int
    let workoutDate: Date
}

enum WorkoutShareBuilder {
    static func makeShareData(
        title: String,
        exercises: [WorkoutExerciseSession],
        durationSeconds: Int,
        prCount: Int,
        weeklyStreak: Int,
        date: Date = Date()
    ) -> WorkoutShareData {
        let preferredUnit = preferredUnit(from: exercises)
        let calculation = calculate(exercises: exercises, preferredUnit: preferredUnit)
        let topLift = calculation.topLift ?? WorkoutShareData.TopLift(
            name: "Workout complete",
            reps: 0,
            weight: nil,
            unit: preferredUnit
        )

        return WorkoutShareData(
            title: title.isEmpty ? "Workout" : title,
            durationSeconds: max(durationSeconds, 0),
            totalVolume: max(calculation.totalVolume, 0),
            volumeUnit: preferredUnit,
            topLift: topLift,
            prCount: prCount,
            weeklyStreak: max(weeklyStreak, 0),
            workoutDate: date
        )
    }

    private static func preferredUnit(from exercises: [WorkoutExerciseSession]) -> WeightUnit {
        let kgCount = exercises.filter { $0.unit == .kg }.count
        let lbCount = exercises.filter { $0.unit == .lb }.count
        if kgCount > lbCount { return .kg }
        return .lb
    }

    private static func calculate(
        exercises: [WorkoutExerciseSession],
        preferredUnit: WeightUnit
    ) -> (totalVolume: Double, topLift: WorkoutShareData.TopLift?) {
        var total: Double = 0
        var best: WorkoutShareData.TopLift?

        for exercise in exercises {
            let isCardio = exercise.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix("cardio")
            for set in exercise.sets {
                guard set.isComplete || (!set.isWarmup && !(set.reps.isEmpty && set.weight.isEmpty)) else { continue }
                let reps = Int(set.reps.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
                let weightValue = Double(set.weight.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
                if reps <= 0 && weightValue <= 0 { continue }

                let converted = convert(weightValue, from: exercise.unit, to: preferredUnit)
                let liftVolume = max(converted, 0) * Double(max(reps, 0))
                if !isCardio {
                    total += liftVolume
                }

                // Track top lift prioritizing weight then reps
                if !isCardio {
                    if let current = best {
                        let currentWeight = current.weight ?? 0
                        if converted > currentWeight || (converted == currentWeight && reps > current.reps) {
                            best = WorkoutShareData.TopLift(name: exercise.name, reps: reps, weight: converted > 0 ? converted : nil, unit: preferredUnit)
                        }
                    } else {
                        best = WorkoutShareData.TopLift(name: exercise.name, reps: reps, weight: converted > 0 ? converted : nil, unit: preferredUnit)
                    }
                }
            }
        }

        // Fallback to highest reps bodyweight if no weighted sets
        if best == nil {
            var fallback: WorkoutShareData.TopLift?
            for exercise in exercises {
                let isCardio = exercise.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix("cardio")
                if isCardio { continue }
                for set in exercise.sets {
                    guard !set.isWarmup else { continue }
                    let reps = Int(set.reps.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
                    if reps <= 0 { continue }
                    if let existing = fallback {
                        if reps > existing.reps {
                            fallback = WorkoutShareData.TopLift(name: exercise.name, reps: reps, weight: nil, unit: preferredUnit)
                        }
                    } else {
                        fallback = WorkoutShareData.TopLift(name: exercise.name, reps: reps, weight: nil, unit: preferredUnit)
                    }
                }
            }
            best = fallback
        }

        return (total, best)
    }

    private static func convert(_ weight: Double, from: WeightUnit, to: WeightUnit) -> Double {
        guard weight > 0 else { return 0 }
        if from == to { return weight }
        if from == .kg && to == .lb { return weight * 2.20462 }
        if from == .lb && to == .kg { return weight / 2.20462 }
        return weight
    }
}

struct WorkoutShareComposer: View {
    let data: WorkoutShareData
    let onClose: () -> Void

    @State private var backgroundImage: UIImage?
    @State private var pickerItem: PhotosPickerItem?
    @State private var renderedImage: UIImage?
    @State private var showShareSheet = false
    @State private var isRendering = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                preview

                HStack(spacing: 12) {
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Label("Choose Photo", systemImage: "photo.on.rectangle")
                            .font(FitFont.body(size: 15, weight: .semibold))
                            .foregroundColor(FitTheme.textPrimary)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity)
                            .background(FitTheme.cardHighlight)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }

                    Button(action: renderAndShare) {
                        if isRendering {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(FitTheme.buttonText)
                                .frame(maxWidth: .infinity)
                        } else {
                            Label("Share", systemImage: "square.and.arrow.up")
                                .font(FitFont.body(size: 15, weight: .semibold))
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(isRendering)
                    .padding(.vertical, 10)
                    .background(FitTheme.primaryGradient)
                    .foregroundColor(FitTheme.buttonText)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }
            .padding(20)
            .navigationTitle("Share workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: onClose)
                        .foregroundColor(FitTheme.textSecondary)
                        .font(FitFont.body(size: 15))
                }
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let renderedImage {
                ActivityView(activityItems: [renderedImage])
            }
        }
        .onChange(of: pickerItem) { _ in
            Task { await loadImage() }
        }
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Preview")
                .font(FitFont.body(size: 14))
                .foregroundColor(FitTheme.textSecondary)

            WorkoutShareCardView(data: data, background: backgroundImage)
                .frame(height: 420)
                .clipShape(RoundedRectangle(cornerRadius: 24))
                .shadow(color: Color.black.opacity(0.25), radius: 12, x: 0, y: 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func loadImage() async {
        guard let item = pickerItem else { return }
        if let data = try? await item.loadTransferable(type: Data.self),
           let image = UIImage(data: data) {
            backgroundImage = image
        }
    }

    private func renderAndShare() {
        isRendering = true
        let renderer = ImageRenderer(content: WorkoutShareCardView(data: data, background: backgroundImage)
            .frame(width: 1080, height: 1920)
        )
        renderer.scale = 3
        renderedImage = renderer.uiImage
        isRendering = false
        if renderedImage != nil {
            showShareSheet = true
        }
    }
}

struct WorkoutShareCardView: View {
    let data: WorkoutShareData
    let background: UIImage?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let image = background {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .clipped()
            } else {
                FitTheme.backgroundGradient
            }

            LinearGradient(
                colors: [Color.black.opacity(0.55), Color.black.opacity(0.1)],
                startPoint: .bottom,
                endPoint: .top
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                if data.prCount > 0 {
                    Text(data.prCount == 1 ? "NEW PR" : "PRs: \(data.prCount)")
                        .font(FitFont.body(size: 14, weight: .bold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.white)
                        .clipShape(Capsule())
                        .shadow(color: Color.black.opacity(0.2), radius: 6, x: 0, y: 4)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(data.title)
                        .font(FitFont.heading(size: 28))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.3), radius: 6, x: 0, y: 4)

                    Text("Top lift · \(topLiftLine())")
                        .font(FitFont.body(size: 16))
                        .foregroundColor(.white.opacity(0.9))
                        .shadow(color: .black.opacity(0.3), radius: 6, x: 0, y: 4)
                }

                HStack(spacing: 18) {
                    statBlock(title: "Duration", value: formatDuration(data.durationSeconds))
                    statBlock(title: "Total volume", value: formatWeight(data.totalVolume, unit: data.volumeUnit))
                    statBlock(title: "Weekly streak", value: "\(data.weeklyStreak)w")
                }
                .padding(14)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 16))

                HStack {
                    Spacer()
                    Text("FitAi")
                        .font(FitFont.body(size: 16, weight: .heavy))
                        .foregroundColor(.white.opacity(0.9))
                        .tracking(0.5)
                        .shadow(color: .black.opacity(0.3), radius: 6, x: 0, y: 4)
                }
            }
            .padding(24)
        }
        .contentShape(Rectangle())
        .clipped()
    }

    private func statBlock(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(FitFont.body(size: 13))
                .foregroundColor(.white.opacity(0.8))
            Text(value)
                .font(FitFont.heading(size: 22))
                .foregroundColor(.white)
        }
    }

    private func topLiftLine() -> String {
        if let weight = data.topLift.weight {
            return "\(formatWeight(weight, unit: data.topLift.unit)) × \(data.topLift.reps)"
        }
        return "\(data.topLift.reps) reps"
    }

    private func formatDuration(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let remainder = seconds % 60
        return String(format: "%dm %02ds", minutes, remainder)
    }

    private func formatWeight(_ weight: Double, unit: WeightUnit) -> String {
        if weight == 0 { return "0 \(unit.label)" }
        let display = weight.rounded() == weight ? String(format: "%.0f", weight) : String(format: "%.1f", weight)
        return "\(display) \(unit.label)"
    }
}

struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
