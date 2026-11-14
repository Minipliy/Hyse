import SwiftUI

/// Translates exercise metadata into the independently tintable regions of the
/// anatomy atlas. The body view intentionally uses primary muscles only: a
/// stabilising or assisting muscle must never appear as if it was trained
/// directly.
nonisolated enum TrainingMuscleRegionMap {
    static func weightedRegions(primary: [String], secondary _: [String]) -> [String: Double] {
        let mappedRegions = Set(primary.flatMap { regions(for: $0) })
        return Dictionary(uniqueKeysWithValues: mappedRegions.map { ($0, 1.0) })
    }

    static func expandedCounts(_ counts: [String: Double]) -> [String: Double] {
        var result: [String: Double] = [:]
        for (rawMuscle, value) in counts where value > 0 {
            for region in regions(for: rawMuscle) {
                result[region, default: 0] += value
            }
        }
        return result
    }

    static func regions(for rawMuscle: String) -> [String] {
        let key = rawMuscle
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")

        switch key {
        case "chest", "pectorals", "pectoralis", "brust": return ["chest"]
        case "core", "abdominals", "abdomen", "bauch", "bauchmuskeln": return ["abs", "obliques"]
        case "abs": return ["abs"]
        case "obliques", "seitliche_bauchmuskeln": return ["obliques"]
        case "front_shoulders", "anterior_delts", "vordere_schulter": return ["front_shoulders"]
        case "shoulders", "side_shoulders", "lateral_shoulders", "lateral_delts", "schultern": return ["shoulders"]
        case "rear_shoulders", "posterior_delts", "hintere_schulter": return ["rear_shoulders"]
        case "biceps", "bizeps": return ["biceps"]
        case "triceps", "trizeps": return ["triceps"]
        case "forearms", "unterarme": return ["forearms"]
        case "lats", "latissimus": return ["lats"]
        case "upper_back", "oberer_rucken": return ["upper_back"]
        case "back", "lower_back", "rucken", "unterer_rucken": return ["back"]
        case "neck", "nacken": return ["neck"]
        case "traps", "trapezius": return ["traps"]
        case "glutes", "gluteus", "gesass": return ["glutes"]
        case "quadriceps", "quads", "quadrizeps": return ["quadriceps"]
        case "adductors", "adduktoren": return ["adductors"]
        case "abductors", "abduktoren": return ["abductors"]
        case "hip_flexors", "huftbeuger": return ["hip_flexors"]
        case "hamstrings", "beinbeuger": return ["hamstrings"]
        case "calves", "waden": return ["calves"]
        case "tibialis", "tibialis_anterior", "schienbeinmuskel": return ["tibialis"]

        // These old import tags do not identify one anatomical target. They
        // stay unpainted instead of colouring every arm or leg muscle.
        case "arms", "arme", "legs", "beine", "cardio", "mobility": return []
        default: return [key]
        }
    }
}

/// Every case owns a separate mask. A muscle can therefore be switched on
/// without sharing a rectangle, triangle or catch-all body-part shape with a
/// neighbouring muscle.
nonisolated enum TrainingAnatomicalMuscle: String, CaseIterable, Identifiable {
    case neck
    case traps
    case chest
    case shoulders
    case frontShoulders = "front_shoulders"
    case rearShoulders = "rear_shoulders"
    case biceps
    case triceps
    case forearms
    case abs
    case obliques
    case lats
    case upperBack = "upper_back"
    case back
    case glutes
    case hipFlexors = "hip_flexors"
    case abductors
    case adductors
    case quadriceps
    case hamstrings
    case calves
    case tibialis

    var id: String { rawValue }

    fileprivate var contours: [AnatomicalContour] {
        switch self {
        case .neck:
            return [
                .front([
                    p(0.331, 0.116), p(0.314, 0.122), p(0.296, 0.143), p(0.275, 0.178),
                    p(0.283, 0.194), p(0.306, 0.186), p(0.326, 0.166), p(0.333, 0.143)
                ]),
                .back([
                    p(0.666, 0.110), p(0.650, 0.124), p(0.633, 0.156), p(0.616, 0.199),
                    p(0.624, 0.222), p(0.647, 0.205), p(0.662, 0.174), p(0.669, 0.137)
                ])
            ]

        case .traps:
            // Trap activity is supplied by the reference asset above.
            return []

        case .chest:
            return [
                .front([
                    p(0.330, 0.192), p(0.310, 0.188), p(0.287, 0.192), p(0.266, 0.208),
                    p(0.263, 0.238), p(0.271, 0.272), p(0.291, 0.295), p(0.317, 0.302),
                    p(0.330, 0.287), p(0.333, 0.246), p(0.333, 0.210)
                ])
            ]

        case .shoulders:
            return [
                .front([
                    p(0.268, 0.190), p(0.249, 0.183), p(0.229, 0.190), p(0.218, 0.208),
                    p(0.216, 0.235), p(0.222, 0.266), p(0.236, 0.286), p(0.253, 0.284),
                    p(0.266, 0.260), p(0.273, 0.224)
                ]),
                .back([
                    p(0.611, 0.190), p(0.592, 0.183), p(0.573, 0.190), p(0.562, 0.208),
                    p(0.560, 0.236), p(0.566, 0.266), p(0.578, 0.285), p(0.593, 0.282),
                    p(0.605, 0.258), p(0.615, 0.220)
                ])
            ]

        case .frontShoulders:
            return [
                .front([
                    p(0.286, 0.194), p(0.271, 0.190), p(0.259, 0.201), p(0.253, 0.222),
                    p(0.256, 0.250), p(0.267, 0.276), p(0.281, 0.281), p(0.291, 0.261),
                    p(0.296, 0.225), p(0.294, 0.205)
                ])
            ]

        case .rearShoulders:
            return [
                .back([
                    p(0.634, 0.191), p(0.615, 0.188), p(0.600, 0.199), p(0.593, 0.221),
                    p(0.597, 0.250), p(0.609, 0.276), p(0.624, 0.282), p(0.635, 0.262),
                    p(0.640, 0.228), p(0.640, 0.205)
                ])
            ]

        case .biceps:
            return [
                .front([
                    p(0.252, 0.274), p(0.238, 0.278), p(0.226, 0.300), p(0.218, 0.332),
                    p(0.219, 0.365), p(0.227, 0.388), p(0.239, 0.394), p(0.251, 0.377),
                    p(0.260, 0.344), p(0.263, 0.311), p(0.260, 0.287)
                ])
            ]

        case .triceps:
            return [
                .front([
                    p(0.224, 0.275), p(0.216, 0.282), p(0.208, 0.308), p(0.205, 0.343),
                    p(0.209, 0.374), p(0.218, 0.389), p(0.224, 0.369), p(0.221, 0.337),
                    p(0.229, 0.303), p(0.233, 0.286)
                ]),
                .back([
                    p(0.584, 0.274), p(0.569, 0.280), p(0.555, 0.305), p(0.548, 0.337),
                    p(0.549, 0.369), p(0.558, 0.394), p(0.571, 0.399), p(0.582, 0.379),
                    p(0.590, 0.346), p(0.594, 0.313), p(0.591, 0.289)
                ])
            ]

        case .forearms:
            return [
                .front([
                    p(0.219, 0.377), p(0.208, 0.386), p(0.197, 0.413), p(0.188, 0.448),
                    p(0.185, 0.478), p(0.190, 0.497), p(0.199, 0.497), p(0.209, 0.474),
                    p(0.217, 0.442), p(0.227, 0.409), p(0.229, 0.391)
                ]),
                .back([
                    p(0.558, 0.381), p(0.547, 0.390), p(0.537, 0.416), p(0.528, 0.450),
                    p(0.526, 0.479), p(0.531, 0.497), p(0.540, 0.497), p(0.550, 0.472),
                    p(0.558, 0.440), p(0.567, 0.409), p(0.568, 0.393)
                ])
            ]

        case .abs:
            return [
                abdominalSegment(top: 0.294, bottom: 0.337, outer: 0.319),
                abdominalSegment(top: 0.339, bottom: 0.382, outer: 0.320),
                abdominalSegment(top: 0.384, bottom: 0.428, outer: 0.319),
                abdominalSegment(top: 0.430, bottom: 0.477, outer: 0.316)
            ]

        case .obliques:
            return [
                .front([
                    p(0.297, 0.299), p(0.282, 0.307), p(0.269, 0.334), p(0.263, 0.370),
                    p(0.265, 0.410), p(0.273, 0.451), p(0.287, 0.484), p(0.299, 0.471),
                    p(0.302, 0.429), p(0.300, 0.386), p(0.305, 0.342), p(0.307, 0.314)
                ])
            ]

        case .lats:
            return [
                .back([
                    p(0.647, 0.263), p(0.624, 0.270), p(0.607, 0.289), p(0.595, 0.321),
                    p(0.594, 0.356), p(0.602, 0.397), p(0.616, 0.432), p(0.637, 0.457),
                    p(0.653, 0.468), p(0.660, 0.445), p(0.657, 0.403), p(0.652, 0.359),
                    p(0.655, 0.317), p(0.659, 0.283)
                ])
            ]

        case .upperBack:
            return [
                .back([
                    p(0.664, 0.185), p(0.645, 0.188), p(0.626, 0.201), p(0.614, 0.222),
                    p(0.616, 0.250), p(0.628, 0.274), p(0.644, 0.298), p(0.660, 0.326),
                    p(0.667, 0.313), p(0.669, 0.274), p(0.669, 0.232), p(0.669, 0.201)
                ]),
                .back([
                    p(0.649, 0.286), p(0.635, 0.294), p(0.627, 0.313), p(0.629, 0.337),
                    p(0.642, 0.350), p(0.655, 0.344), p(0.665, 0.327), p(0.661, 0.304)
                ])
            ]

        case .back:
            return [
                .back([
                    p(0.668, 0.321), p(0.656, 0.338), p(0.648, 0.373), p(0.646, 0.414),
                    p(0.649, 0.454), p(0.658, 0.486), p(0.668, 0.493), p(0.670, 0.458),
                    p(0.670, 0.416), p(0.670, 0.371)
                ])
            ]

        case .glutes:
            return [
                .back([
                    p(0.666, 0.460), p(0.644, 0.459), p(0.624, 0.473), p(0.613, 0.501),
                    p(0.613, 0.533), p(0.625, 0.559), p(0.646, 0.571), p(0.663, 0.561),
                    p(0.669, 0.534), p(0.669, 0.497)
                ]),
                .back([
                    p(0.620, 0.456), p(0.607, 0.463), p(0.599, 0.480), p(0.602, 0.500),
                    p(0.612, 0.510), p(0.624, 0.498), p(0.633, 0.478), p(0.632, 0.463)
                ])
            ]

        case .hipFlexors:
            return [
                .front([
                    p(0.329, 0.475), p(0.316, 0.481), p(0.303, 0.497), p(0.299, 0.521),
                    p(0.306, 0.543), p(0.319, 0.548), p(0.329, 0.531), p(0.334, 0.504)
                ])
            ]

        case .abductors:
            return [
                .front([
                    p(0.284, 0.488), p(0.267, 0.493), p(0.252, 0.514), p(0.247, 0.548),
                    p(0.252, 0.578), p(0.264, 0.592), p(0.276, 0.575), p(0.282, 0.544),
                    p(0.291, 0.514), p(0.294, 0.497)
                ]),
                .back([
                    p(0.613, 0.459), p(0.600, 0.461), p(0.589, 0.480), p(0.587, 0.505),
                    p(0.596, 0.521), p(0.607, 0.511), p(0.616, 0.489), p(0.622, 0.470)
                ])
            ]

        case .adductors:
            return [
                .front([
                    p(0.331, 0.505), p(0.318, 0.516), p(0.307, 0.548), p(0.304, 0.588),
                    p(0.308, 0.626), p(0.317, 0.654), p(0.327, 0.637), p(0.334, 0.600),
                    p(0.336, 0.555), p(0.337, 0.521)
                ])
            ]

        case .quadriceps:
            return [
                .front([
                    p(0.303, 0.505), p(0.287, 0.513), p(0.277, 0.543), p(0.276, 0.589),
                    p(0.281, 0.638), p(0.291, 0.682), p(0.304, 0.694), p(0.313, 0.671),
                    p(0.313, 0.626), p(0.310, 0.577), p(0.313, 0.534)
                ]),
                .front([
                    p(0.279, 0.494), p(0.263, 0.503), p(0.250, 0.535), p(0.246, 0.581),
                    p(0.249, 0.627), p(0.258, 0.670), p(0.270, 0.690), p(0.282, 0.674),
                    p(0.287, 0.633), p(0.285, 0.586), p(0.291, 0.538), p(0.291, 0.510)
                ]),
                .front([
                    p(0.317, 0.614), p(0.307, 0.628), p(0.303, 0.652), p(0.307, 0.680),
                    p(0.316, 0.699), p(0.325, 0.690), p(0.329, 0.666), p(0.327, 0.638)
                ])
            ]

        case .hamstrings:
            return [
                .back([
                    p(0.651, 0.559), p(0.631, 0.566), p(0.617, 0.592), p(0.611, 0.632),
                    p(0.614, 0.675), p(0.624, 0.711), p(0.638, 0.724), p(0.649, 0.705),
                    p(0.653, 0.666), p(0.652, 0.620), p(0.658, 0.581)
                ]),
                .back([
                    p(0.615, 0.558), p(0.601, 0.570), p(0.592, 0.600), p(0.588, 0.639),
                    p(0.593, 0.680), p(0.603, 0.713), p(0.615, 0.722), p(0.623, 0.699),
                    p(0.623, 0.660), p(0.621, 0.615), p(0.626, 0.579)
                ])
            ]

        case .calves:
            return [
                // Calf raises colour only gastrocnemius/soleus on the back.
                // The anterior shin is a separate tibialis mask below.
                .back([
                    p(0.628, 0.714), p(0.613, 0.719), p(0.599, 0.741), p(0.590, 0.777),
                    p(0.589, 0.812), p(0.597, 0.838), p(0.608, 0.841), p(0.618, 0.820),
                    p(0.625, 0.786), p(0.634, 0.748), p(0.638, 0.725)
                ]),
                .back([
                    p(0.648, 0.721), p(0.636, 0.731), p(0.627, 0.757), p(0.624, 0.792),
                    p(0.630, 0.821), p(0.640, 0.835), p(0.649, 0.819), p(0.654, 0.788),
                    p(0.657, 0.754), p(0.656, 0.733)
                ])
            ]

        case .tibialis:
            return [
                .front([
                    p(0.278, 0.696), p(0.265, 0.700), p(0.254, 0.724), p(0.248, 0.760),
                    p(0.249, 0.807), p(0.255, 0.852), p(0.263, 0.890), p(0.271, 0.886),
                    p(0.275, 0.846), p(0.276, 0.801), p(0.281, 0.756), p(0.286, 0.716)
                ]),
                .front([
                    p(0.303, 0.698), p(0.291, 0.713), p(0.285, 0.751), p(0.284, 0.796),
                    p(0.289, 0.842), p(0.296, 0.879), p(0.304, 0.886), p(0.310, 0.851),
                    p(0.311, 0.807), p(0.310, 0.762), p(0.313, 0.724), p(0.312, 0.705)
                ])
            ]
        }
    }

    private func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: x, y: y)
    }

    private func abdominalSegment(top: CGFloat, bottom: CGFloat, outer: CGFloat) -> AnatomicalContour {
        .front([
            p(0.331, top), p(outer, top - 0.003), p(outer - 0.010, top + 0.009),
            p(outer - 0.011, bottom - 0.010), p(outer, bottom + 0.002), p(0.331, bottom),
            p(0.334, bottom - 0.010), p(0.334, top + 0.010)
        ])
    }
}

private nonisolated struct AnatomicalContour: Sendable {
    enum FigureSide: Sendable { case front, back }

    let figureSide: FigureSide
    let points: [CGPoint]
    let mirrored: Bool

    static func front(_ points: [CGPoint], mirrored: Bool = true) -> Self {
        Self(figureSide: .front, points: points, mirrored: mirrored)
    }

    static func back(_ points: [CGPoint], mirrored: Bool = true) -> Self {
        Self(figureSide: .back, points: points, mirrored: mirrored)
    }

    var mirrorAxis: CGFloat {
        switch figureSide {
        case .front: return 1.0 / 3.0
        case .back: return 2.0 / 3.0
        }
    }
}

private struct AnatomicalMuscleMask: Shape {
    let muscle: TrainingAnatomicalMuscle

    func path(in rect: CGRect) -> Path {
        var result = Path()
        for contour in muscle.contours {
            result.addPath(smoothPath(contour.points, in: rect))
            if contour.mirrored {
                let mirrored = contour.points.map {
                    CGPoint(x: contour.mirrorAxis * 2 - $0.x, y: $0.y)
                }
                result.addPath(smoothPath(mirrored, in: rect))
            }
        }
        return result
    }

    /// Closed quadratic splines keep the overlay on rounded muscle bellies;
    /// there are no straight-edged body-part polygons in the render path.
    private func smoothPath(_ points: [CGPoint], in rect: CGRect) -> Path {
        var path = Path()
        guard points.count >= 6, let first = points.first, let last = points.last else { return path }

        let scaled = points.map {
            CGPoint(x: rect.minX + $0.x * rect.width, y: rect.minY + $0.y * rect.height)
        }
        let firstPoint = CGPoint(x: rect.minX + first.x * rect.width, y: rect.minY + first.y * rect.height)
        let lastPoint = CGPoint(x: rect.minX + last.x * rect.width, y: rect.minY + last.y * rect.height)
        path.move(to: midpoint(lastPoint, firstPoint))

        for index in scaled.indices {
            let current = scaled[index]
            let next = scaled[(index + 1) % scaled.count]
            path.addQuadCurve(to: midpoint(current, next), control: current)
        }
        path.closeSubpath()
        return path
    }

    private func midpoint(_ lhs: CGPoint, _ rhs: CGPoint) -> CGPoint {
        CGPoint(x: (lhs.x + rhs.x) / 2, y: (lhs.y + rhs.y) / 2)
    }
}

/// Blue layers are extracted directly from the user's supplied reference
/// screens and registered to the source atlas. They contain no background and
/// no artificial geometric fill, so several reference layers can be composed
/// over the neutral illustration without covering its white fascia details.
private enum TrainingReferenceOverlay: String, Hashable {
    case biceps = "Biceps"
    case core = "Core"
    case benchPress = "BenchPress"
    case chest = "Chest"
    case pullUp = "PullUp"
    case neck = "Neck"
    case row = "Row"
    case lats = "Lats"
    case upperBack = "UpperBack"
    case facePull = "FacePull"
    case frontShoulders = "FrontShoulders"
    case rearShoulders = "RearShoulders"
    case traps = "Traps"
    case triceps = "Triceps"
    case forearms = "Forearms"
    case lowerBack = "LowerBack"
    case abductors = "Abductors"
    case adductors = "Adductors"
    case hamstrings = "Hamstrings"
    case birdDog = "BirdDog"
    case glutes = "Glutes"
    case quadriceps = "Quadriceps"
    case calves = "Calves"

    var assetName: String { "TrainingReference\(rawValue)" }

    /// Composite exercise references can include a lighter assist-muscle
    /// highlight. Draw those first, then place the direct muscle reference on
    /// top (for example Biceps Curl over Lat Pulldown's light-blue biceps).
    private var drawPriority: Int {
        switch self {
        // These references include several lighter assistance highlights.
        // They must never cover a targeted muscle from another exercise.
        case .benchPress, .row, .birdDog:
            return 0
        // These are still composite screenshots, but their named target is
        // more specific than the broad compound references above.
        case .pullUp, .facePull, .frontShoulders, .rearShoulders, .hamstrings:
            return 1
        case .biceps, .triceps, .forearms, .quadriceps, .calves,
                .core, .neck, .traps, .lowerBack, .abductors, .adductors,
                .lats, .upperBack, .chest, .glutes:
            return 2
        }
    }

    static func layers(
        for muscles: [TrainingAnatomicalMuscle],
        regionCounts: [String: Double]
    ) -> [Self] {
        // Every active muscle contributes its own transparent reference
        // layer. Do not select a single "best" exercise image here: doing so
        // made a later lat pulldown replace the layers from a deadlift.
        let individual: [TrainingAnatomicalMuscle: Self] = [
            .chest: .chest,
            .shoulders: .frontShoulders,
            .frontShoulders: .frontShoulders,
            .rearShoulders: .rearShoulders,
            .neck: .neck,
            .traps: .traps,
            .biceps: .biceps,
            .triceps: .triceps,
            .forearms: .forearms,
            .abs: .core,
            .obliques: .core,
            .upperBack: .upperBack,
            .lats: .lats,
            .back: .lowerBack,
            .glutes: .glutes,
            .abductors: .abductors,
            .adductors: .adductors,
            .quadriceps: .quadriceps,
            .hamstrings: .hamstrings,
            .calves: .calves,
        ]

        // A muscle accumulated from more than one exercise is the stronger
        // signal. Render that layer last, so Lat Pulldown + Row keeps the
        // dark latissimus instead of Row's lighter assist highlight.
        var strengthByLayer: [Self: Double] = [:]
        for muscle in muscles {
            guard let layer = individual[muscle] else { continue }
            strengthByLayer[layer] = max(
                strengthByLayer[layer, default: 0],
                regionCounts[muscle.rawValue, default: 0]
            )
        }
        return strengthByLayer.keys.sorted { lhs, rhs in
            let leftStrength = strengthByLayer[lhs, default: 0]
            let rightStrength = strengthByLayer[rhs, default: 0]
            if leftStrength != rightStrength { return leftStrength < rightStrength }
            if lhs.drawPriority != rhs.drawPriority { return lhs.drawPriority < rhs.drawPriority }
            return lhs.rawValue < rhs.rawValue
        }
    }
}

/// Front and back anatomy atlas used everywhere muscle activity is shown.
/// Each active layer is copied from the supplied reference screenshots and
/// composed on the neutral atlas, preserving every original muscle fibre.
struct DetailedTrainingMuscleBody: View {
    let counts: [String: Double]

    private var regionCounts: [String: Double] { TrainingMuscleRegionMap.expandedCounts(counts) }
    private var activeMuscles: [TrainingAnatomicalMuscle] {
        TrainingAnatomicalMuscle.allCases.filter { regionCounts[$0.rawValue, default: 0] > 0 }
    }
    private var referenceLayers: [TrainingReferenceOverlay] {
        TrainingReferenceOverlay.layers(for: activeMuscles, regionCounts: regionCounts)
    }
    var body: some View {
        ZStack {
            // This neutral frame is assembled from the supplied screenshots,
            // so scale, anatomy and shading match the reference exactly.
            Image("TrainingReferenceAnatomyNeutral")
                .resizable()
                .scaledToFit()

            ForEach(referenceLayers, id: \.self) { layer in
                Image(layer.assetName)
                    .resizable()
                    .scaledToFit()
            }
        }
        .aspectRatio(1.5, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: HyseRadius.card, style: .continuous))
        .accessibilityElement(children: .ignore)
    }
}
