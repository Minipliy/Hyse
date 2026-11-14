import Foundation

// Exercise names and categories checked against https://www.strengthlog.com/exercise-directory/
// on 2026-09-26. Instructions below are original Hyse wording.
nonisolated enum StrengthLogDirectory {
    static let exercises: [TrainingExercise] = [
        TrainingExercise.builtIn("sl_001", "Assisted Dip", "Unterstützter Dip", .weightReps, .machine, ["chest"], ["triceps", "front_shoulders"]),
        TrainingExercise.builtIn("sl_002", "Band-Assisted Bench Press", "Bandunterstütztes Bankdrücken", .weightReps, .bands, ["chest"], ["triceps", "front_shoulders"]),
        TrainingExercise.builtIn("sl_005", "Bench Press Against Band", "Bankdrücken mit Bandwiderstand", .weightReps, .bands, ["chest"], ["triceps", "front_shoulders"]),
        TrainingExercise.builtIn("sl_006", "Board Press", "Board Press mit Langhantel", .weightReps, .barbell, ["chest"], ["triceps", "front_shoulders"]),
        TrainingExercise.builtIn("sl_007", "Cable Chest Press", "Brustdrücken am Kabelzug", .weightReps, .cable, ["chest"], ["triceps", "front_shoulders"]),
        TrainingExercise.builtIn("sl_008", "Clap Push-Up", "Liegestütz mit Klatschen", .repsOnly, .bodyweight, ["chest"], ["triceps", "front_shoulders"]),
        TrainingExercise.builtIn("sl_010", "Close-Grip Feet-Up Bench Press", "Enges Bankdrücken mit angehobenen Füßen", .weightReps, .barbell, ["chest"], ["triceps", "front_shoulders"]),
        TrainingExercise.builtIn("sl_011", "Cobra Push-Up", "Cobra-Liegestütz", .repsOnly, .bodyweight, ["chest"], ["triceps", "front_shoulders"]),
        TrainingExercise.builtIn("sl_013", "Dumbbell Floor Press", "Floor Press mit Kurzhanteln", .weightReps, .dumbbell, ["chest"], ["triceps", "front_shoulders"]),
        TrainingExercise.builtIn("sl_015", "Feet-Up Bench Press", "Bankdrücken mit angehobenen Füßen", .weightReps, .barbell, ["chest"], ["triceps", "front_shoulders"]),
        TrainingExercise.builtIn("sl_016", "Floor Press", "Floor Press mit Langhantel", .weightReps, .barbell, ["chest"], ["triceps", "front_shoulders"]),
        TrainingExercise.builtIn("sl_019", "Incline Push-Up", "Liegestütz mit erhöhten Händen", .repsOnly, .bodyweight, ["chest"], ["triceps", "front_shoulders"]),
        TrainingExercise.builtIn("sl_020", "Kettlebell Floor Press", "Floor Press mit Kettlebell", .weightReps, .kettlebell, ["chest"], ["triceps", "front_shoulders"]),
        TrainingExercise.builtIn("sl_021", "Kneeling Incline Push-Up", "Liegestütz auf Knien mit erhöhten Händen", .repsOnly, .bodyweight, ["chest"], ["triceps", "front_shoulders"]),
        TrainingExercise.builtIn("sl_022", "Kneeling Push-Up", "Liegestütz auf Knien", .repsOnly, .bodyweight, ["chest"], ["triceps", "front_shoulders"]),
        TrainingExercise.builtIn("sl_025", "Medicine Ball Chest Pass", "Brustpass mit Medizinball", .weightReps, .other, ["chest"], ["triceps", "front_shoulders"]),
        TrainingExercise.builtIn("sl_027", "Pin Bench Press", "Bankdrücken von Ablagen", .weightReps, .barbell, ["chest"], ["triceps", "front_shoulders"]),
        TrainingExercise.builtIn("sl_028", "Plank to Push-Up", "Vom Unterarmstütz in den Liegestütz", .repsOnly, .bodyweight, ["chest"], ["triceps", "front_shoulders"]),
        TrainingExercise.builtIn("sl_030", "Push-Up Against Wall", "Wandliegestütz", .repsOnly, .bodyweight, ["chest"], ["triceps", "front_shoulders"]),
        TrainingExercise.builtIn("sl_031", "Push-Ups With Feet in Rings", "Liegestütze mit Füßen in Ringen", .repsOnly, .bodyweight, ["chest"], ["triceps", "front_shoulders"]),
        TrainingExercise.builtIn("sl_033", "Ring Dip", "Dip an Ringen", .repsOnly, .bodyweight, ["chest"], ["triceps", "front_shoulders"]),
        TrainingExercise.builtIn("sl_034", "Seated Cable Chest Fly", "Sitzende Kabel-Flys", .weightReps, .cable, ["chest"], ["front_shoulders"]),
        TrainingExercise.builtIn("sl_035", "Smith Machine Bench Press", "Bankdrücken an der Multipresse", .weightReps, .machine, ["chest"], ["triceps", "front_shoulders"]),
        TrainingExercise.builtIn("sl_037", "Smith Machine Reverse Grip Bench Press", "Bankdrücken im Untergriff an der Multipresse", .weightReps, .machine, ["chest"], ["triceps", "front_shoulders"]),
        TrainingExercise.builtIn("sl_038", "Standing Cable Chest Fly", "Stehende Kabel-Flys", .weightReps, .cable, ["chest"], ["front_shoulders"]),
        TrainingExercise.builtIn("sl_039", "Standing Resistance Band Chest Fly", "Stehende Brust-Flys mit Band", .weightReps, .bands, ["chest"], ["front_shoulders"]),
        TrainingExercise.builtIn("sl_041", "Band External Shoulder Rotation", "Schulteraußenrotation mit Band", .weightReps, .bands, ["shoulders"], []),
        TrainingExercise.builtIn("sl_042", "Band Internal Shoulder Rotation", "Schulterinnenrotation mit Band", .weightReps, .bands, ["shoulders"], []),
        TrainingExercise.builtIn("sl_043", "Band Pull-Apart", "Band Pull-Apart", .weightReps, .bands, ["rear_shoulders", "upper_back"], []),
        TrainingExercise.builtIn("sl_045", "Barbell Front Raise", "Frontheben mit Langhantel", .weightReps, .barbell, ["front_shoulders"], []),
        TrainingExercise.builtIn("sl_046", "Barbell Rear Delt Row", "Rudern mit Langhantel für die hintere Schulter", .weightReps, .barbell, ["rear_shoulders", "upper_back"], []),
        TrainingExercise.builtIn("sl_048", "Behind the Neck Press", "Nackendrücken", .weightReps, .barbell, ["shoulders"], ["triceps"]),
        TrainingExercise.builtIn("sl_049", "Cable Internal Shoulder Rotation", "Schulterinnenrotation am Kabelzug", .weightReps, .cable, ["shoulders"], []),
        TrainingExercise.builtIn("sl_050", "Cable External Shoulder Rotation", "Schulteraußenrotation am Kabelzug", .weightReps, .cable, ["shoulders"], []),
        TrainingExercise.builtIn("sl_053", "Cable Rear Delt Row", "Rudern am Kabelzug für die hintere Schulter", .weightReps, .cable, ["rear_shoulders", "upper_back"], []),
        TrainingExercise.builtIn("sl_054", "Cuban Press", "Cuban Press", .weightReps, .barbell, ["shoulders", "rear_shoulders"], ["upper_back"]),
        TrainingExercise.builtIn("sl_055", "Devils Press", "Devils Press", .weightReps, .barbell, ["front_shoulders", "chest", "quadriceps", "adductors"], ["forearms", "calves", "core", "triceps"]),
        TrainingExercise.builtIn("sl_056", "Dumbbell Front Raise", "Frontheben mit Kurzhanteln", .weightReps, .dumbbell, ["front_shoulders"], []),
        TrainingExercise.builtIn("sl_057", "Dumbbell Horizontal Internal Shoulder Rotation", "Waagerechte Schulterinnenrotation mit Kurzhantel", .weightReps, .dumbbell, ["shoulders"], []),
        TrainingExercise.builtIn("sl_058", "Dumbbell Horizontal External Shoulder Rotation", "Waagerechte Schulteraußenrotation mit Kurzhantel", .weightReps, .dumbbell, ["shoulders"], []),
        TrainingExercise.builtIn("sl_060", "Dumbbell Rear Delt Row", "Rudern mit Kurzhanteln für die hintere Schulter", .weightReps, .dumbbell, ["rear_shoulders", "upper_back"], []),
        TrainingExercise.builtIn("sl_063", "Front Hold", "Statisches Frontheben", .duration, .bodyweight, ["front_shoulders"], []),
        TrainingExercise.builtIn("sl_064", "Handstand Push-Up", "Handstand-Liegestütz", .repsOnly, .bodyweight, ["shoulders"], ["triceps"]),
        TrainingExercise.builtIn("sl_065", "Jerk", "Ausstoßen (Jerk)", .weightReps, .barbell, ["shoulders"], ["triceps"]),
        TrainingExercise.builtIn("sl_066", "Kettlebell Halo", "Halo mit Kettlebell", .weightReps, .kettlebell, ["shoulders"], ["core"]),
        TrainingExercise.builtIn("sl_067", "Kettlebell Press", "Schulterdrücken mit Kettlebell", .weightReps, .kettlebell, ["shoulders"], ["triceps"]),
        TrainingExercise.builtIn("sl_068", "Kettlebell Push Press", "Push Press mit Kettlebell", .weightReps, .kettlebell, ["shoulders"], ["triceps"]),
        TrainingExercise.builtIn("sl_069", "Landmine Press", "Landmine Press", .weightReps, .barbell, ["shoulders"], ["triceps"]),
        TrainingExercise.builtIn("sl_070", "Lying Dumbbell External Shoulder Rotation", "Schulteraußenrotation mit Kurzhantel im Liegen", .weightReps, .dumbbell, ["shoulders"], []),
        TrainingExercise.builtIn("sl_071", "Lying Dumbbell Internal Shoulder Rotation", "Schulterinnenrotation mit Kurzhantel im Liegen", .weightReps, .dumbbell, ["shoulders"], []),
        TrainingExercise.builtIn("sl_072", "Machine Lateral Raise", "Seitheben an der Maschine", .weightReps, .machine, ["shoulders"], []),
        TrainingExercise.builtIn("sl_074", "Monkey Row", "Monkey Row", .weightReps, .dumbbell, ["shoulders", "upper_back"], ["rear_shoulders"]),
        TrainingExercise.builtIn("sl_075", "One-Arm Landmine Press", "Einarmiges Landmine-Drücken", .weightReps, .barbell, ["shoulders"], ["triceps"]),
        TrainingExercise.builtIn("sl_077", "Plate Front Raise", "Frontheben mit Gewichtsscheibe", .weightReps, .other, ["front_shoulders"], []),
        TrainingExercise.builtIn("sl_078", "Poliquin Raise", "Poliquin Raise", .weightReps, .dumbbell, ["shoulders"], []),
        TrainingExercise.builtIn("sl_079", "Power Jerk", "Power Jerk", .weightReps, .barbell, ["shoulders"], ["triceps"]),
        TrainingExercise.builtIn("sl_080", "Push Press", "Push Press", .weightReps, .barbell, ["shoulders"], ["triceps"]),
        TrainingExercise.builtIn("sl_082", "Reverse Cable Flyes", "Reverse Flys am Kabelzug", .weightReps, .cable, ["rear_shoulders", "upper_back"], []),
        TrainingExercise.builtIn("sl_083", "Reverse Dumbbell Flyes", "Reverse Flys mit Kurzhanteln", .weightReps, .dumbbell, ["rear_shoulders", "upper_back"], []),
        TrainingExercise.builtIn("sl_084", "Reverse Dumbbell Flyes on Incline Bench", "Reverse Flys auf der Schrägbank", .weightReps, .dumbbell, ["rear_shoulders", "upper_back"], []),
        TrainingExercise.builtIn("sl_086", "Seated Dumbbell Shoulder Press", "Schulterdrücken sitzend mit Kurzhanteln", .weightReps, .dumbbell, ["shoulders"], ["triceps"]),
        TrainingExercise.builtIn("sl_087", "Seated Barbell Overhead Press", "Überkopfdrücken sitzend mit Langhantel", .weightReps, .barbell, ["shoulders"], ["triceps"]),
        TrainingExercise.builtIn("sl_088", "Seated Kettlebell Press", "Schulterdrücken sitzend mit Kettlebell", .weightReps, .kettlebell, ["shoulders"], ["triceps"]),
        TrainingExercise.builtIn("sl_089", "Seated Smith Machine Shoulder Press", "Schulterdrücken sitzend an der Multipresse", .weightReps, .machine, ["shoulders"], ["triceps"]),
        TrainingExercise.builtIn("sl_090", "Smith Machine Landmine Press", "Landmine Press an der Multipresse", .weightReps, .machine, ["shoulders"], ["triceps"]),
        TrainingExercise.builtIn("sl_091", "Snatch Grip Behind the Neck Press", "Nackendrücken im Reißgriff", .weightReps, .barbell, ["shoulders"], ["triceps"]),
        TrainingExercise.builtIn("sl_092", "Squat Jerk", "Stoßen aus der Kniebeuge", .weightReps, .barbell, ["shoulders"], ["triceps"]),
        TrainingExercise.builtIn("sl_093", "Split Jerk", "Split Jerk", .weightReps, .barbell, ["shoulders"], ["triceps"]),
        TrainingExercise.builtIn("sl_094", "Turkish Get-Up", "Turkish Get-Up", .repsOnly, .bodyweight, ["core", "front_shoulders", "shoulders", "rear_shoulders", "glutes"], ["quadriceps", "hamstrings", "traps", "lats"]),
        TrainingExercise.builtIn("sl_095", "Wall Walk", "Wandhochlaufen (Wall Walk)", .repsOnly, .bodyweight, ["shoulders"], ["triceps"]),
        TrainingExercise.builtIn("sl_096", "Z Press", "Z Press", .weightReps, .barbell, ["shoulders"], ["triceps"]),
        TrainingExercise.builtIn("sl_097", "Barbell Curl", "Bizepscurls mit Langhantel", .weightReps, .barbell, ["biceps"], ["forearms"]),
        TrainingExercise.builtIn("sl_100", "Bodyweight Curl", "Bizepscurl mit Körpergewicht", .repsOnly, .bodyweight, ["biceps"], ["forearms"]),
        TrainingExercise.builtIn("sl_101", "Cable Crossover Bicep Curl", "Bizepscurls am Kabelkreuz", .weightReps, .cable, ["biceps"], ["forearms"]),
        TrainingExercise.builtIn("sl_102", "Cable Curl With Bar", "Bizepscurls am Kabelzug mit Stange", .weightReps, .cable, ["biceps"], ["forearms"]),
        TrainingExercise.builtIn("sl_103", "Cable Curl With Rope", "Bizepscurls am Kabelzug mit Seil", .weightReps, .cable, ["biceps"], ["forearms"]),
        TrainingExercise.builtIn("sl_105", "Drag Curl", "Drag Curl", .weightReps, .barbell, ["biceps"], ["forearms"]),
        TrainingExercise.builtIn("sl_111", "Kettlebell Curl", "Bizepscurl mit Kettlebell", .weightReps, .kettlebell, ["biceps"], ["forearms"]),
        TrainingExercise.builtIn("sl_112", "Lying Bicep Cable Curl on Bench", "Bizepscurls auf der Bank liegend am Kabelzug", .weightReps, .cable, ["biceps"], ["forearms"]),
        TrainingExercise.builtIn("sl_113", "Lying Bicep Cable Curl on Floor", "Bizepscurls am Boden liegend am Kabelzug", .weightReps, .cable, ["biceps"], ["forearms"]),
        TrainingExercise.builtIn("sl_114", "Machine Bicep Curl", "Bizepscurls an der Maschine", .weightReps, .machine, ["biceps"], ["forearms"]),
        TrainingExercise.builtIn("sl_115", "Overhead Cable Curl", "Überkopf-Bizepscurls am Kabelzug", .weightReps, .cable, ["biceps"], ["forearms"]),
        TrainingExercise.builtIn("sl_117", "Reverse Dumbbell Curl", "Reverse Curl mit Kurzhanteln", .weightReps, .dumbbell, ["biceps"], ["forearms"]),
        TrainingExercise.builtIn("sl_118", "Resistance Band Curl", "Bizepscurl mit Widerstandsband", .weightReps, .bands, ["biceps"], ["forearms"]),
        TrainingExercise.builtIn("sl_119", "Spider Curl", "Spider Curl", .weightReps, .dumbbell, ["biceps"], ["forearms"]),
        TrainingExercise.builtIn("sl_121", "Barbell Standing Triceps Extension", "Trizepsstrecken stehend mit Langhantel", .weightReps, .barbell, ["triceps"], []),
        TrainingExercise.builtIn("sl_122", "Barbell Incline Triceps Extension", "Trizepsstrecken auf der Schrägbank mit Langhantel", .weightReps, .barbell, ["triceps"], []),
        TrainingExercise.builtIn("sl_123", "Barbell Lying Triceps Extension", "Trizepsstrecken liegend mit Langhantel", .weightReps, .barbell, ["triceps"], []),
        TrainingExercise.builtIn("sl_124", "Bench Dip", "Bank-Dip", .repsOnly, .bodyweight, ["triceps"], ["chest"]),
        TrainingExercise.builtIn("sl_125", "Crossbody Cable Triceps Extension", "Trizepsstrecken quer vor dem Körper am Kabelzug", .weightReps, .cable, ["triceps"], []),
        TrainingExercise.builtIn("sl_126", "Close-Grip Push-Up", "Enger Liegestütz", .repsOnly, .bodyweight, ["triceps"], ["chest"]),
        TrainingExercise.builtIn("sl_127", "Dumbbell Lying Triceps Extension", "Trizepsstrecken liegend mit Kurzhanteln", .weightReps, .dumbbell, ["triceps"], []),
        TrainingExercise.builtIn("sl_128", "Dumbbell Standing Triceps Extension", "Trizepsstrecken stehend mit Kurzhantel", .weightReps, .dumbbell, ["triceps"], []),
        TrainingExercise.builtIn("sl_129", "EZ Bar Lying Triceps Extension", "Trizepsstrecken liegend mit SZ-Stange", .weightReps, .barbell, ["triceps"], []),
        TrainingExercise.builtIn("sl_130", "Machine Overhead Triceps Extension", "Überkopf-Trizepsstrecken an der Maschine", .weightReps, .machine, ["triceps"], []),
        TrainingExercise.builtIn("sl_131", "Overhead Cable Triceps Extension (Lower Position)", "Überkopf-Trizepsstrecken am tiefen Kabelzug", .weightReps, .cable, ["triceps"], []),
        TrainingExercise.builtIn("sl_132", "Overhead Cable Triceps Extension (Upper Position)", "Überkopf-Trizepsstrecken am hohen Kabelzug", .weightReps, .cable, ["triceps"], []),
        TrainingExercise.builtIn("sl_133", "Smith Machine Skull Crushers", "Skull Crusher an der Multipresse", .weightReps, .machine, ["triceps"], []),
        TrainingExercise.builtIn("sl_134", "Tate Press", "Tate Press", .weightReps, .barbell, ["triceps"], ["chest"]),
        TrainingExercise.builtIn("sl_135", "Tricep Bodyweight Extension", "Trizepsstrecken mit Körpergewicht", .repsOnly, .bodyweight, ["triceps"], []),
        TrainingExercise.builtIn("sl_136", "Tricep Pushdown With Bar", "Trizepsdrücken am Kabelzug mit Stange", .weightReps, .cable, ["triceps"], []),
        TrainingExercise.builtIn("sl_139", "Banded Hip March", "Knieheben mit Widerstandsband", .weightReps, .bands, ["hip_flexors"], ["core"]),
        TrainingExercise.builtIn("sl_140", "Barbell Hack Squat", "Hackenschmidt-Kniebeuge mit Langhantel", .weightReps, .barbell, ["quadriceps", "glutes"], ["hamstrings", "core"]),
        TrainingExercise.builtIn("sl_141", "Barbell Lunge", "Ausfallschritt mit Langhantel", .weightReps, .barbell, ["quadriceps", "glutes"], ["hamstrings", "core"]),
        TrainingExercise.builtIn("sl_142", "Barbell Walking Lunge", "Gehender Ausfallschritt mit Langhantel", .weightReps, .barbell, ["quadriceps", "glutes"], ["hamstrings", "core"]),
        TrainingExercise.builtIn("sl_143", "Belt Squat", "Kniebeuge mit Hüftgurt", .weightReps, .machine, ["quadriceps", "glutes"], ["hamstrings", "core"]),
        TrainingExercise.builtIn("sl_144", "Body Weight Lunge", "Ausfallschritt ohne Zusatzgewicht", .repsOnly, .bodyweight, ["quadriceps", "glutes"], ["hamstrings", "core"]),
        TrainingExercise.builtIn("sl_145", "Bodyweight Leg Curl", "Beinbeuger mit Körpergewicht", .repsOnly, .bodyweight, ["hamstrings"], ["glutes"]),
        TrainingExercise.builtIn("sl_146", "Box Jump", "Boxsprung", .repsOnly, .bodyweight, ["quadriceps", "glutes"], ["calves", "core"]),
        TrainingExercise.builtIn("sl_147", "Box Squat", "Kniebeuge zur Box", .weightReps, .barbell, ["quadriceps", "glutes"], ["hamstrings", "core"]),
        TrainingExercise.builtIn("sl_149", "Cable Machine Hip Adduction", "Hüftadduktion am Kabelzug", .weightReps, .machine, ["adductors"], []),
        TrainingExercise.builtIn("sl_150", "Chair Squat", "Kniebeuge zum Stuhl", .repsOnly, .bodyweight, ["quadriceps", "glutes"], ["hamstrings", "core"]),
        TrainingExercise.builtIn("sl_151", "Curtsy Lunge", "Überkreuz-Ausfallschritt", .repsOnly, .bodyweight, ["quadriceps", "glutes"], ["hamstrings", "core"]),
        TrainingExercise.builtIn("sl_152", "Depth Jump", "Tiefensprung", .repsOnly, .bodyweight, ["quadriceps", "glutes"], ["calves", "core"]),
        TrainingExercise.builtIn("sl_153", "Dumbbell Lunge", "Ausfallschritt mit Kurzhanteln", .weightReps, .dumbbell, ["quadriceps", "glutes"], ["hamstrings", "core"]),
        TrainingExercise.builtIn("sl_155", "Dumbbell Squat", "Kniebeuge mit Kurzhanteln", .weightReps, .dumbbell, ["quadriceps", "glutes"], ["hamstrings", "core"]),
        TrainingExercise.builtIn("sl_156", "Front Squat", "Frontkniebeuge", .weightReps, .barbell, ["quadriceps", "glutes"], ["hamstrings", "core"]),
        TrainingExercise.builtIn("sl_157", "Glute Ham Raise", "Glute Ham Raise", .repsOnly, .bodyweight, ["hamstrings"], ["glutes"]),
        TrainingExercise.builtIn("sl_159", "Ground to Overhead", "Vom Boden über den Kopf", .weightReps, .barbell, ["adductors", "front_shoulders", "glutes", "back", "quadriceps"], ["calves", "forearms", "hamstrings", "shoulders", "traps", "triceps"]),
        TrainingExercise.builtIn("sl_161", "Half Air Squat", "Halbe Kniebeuge ohne Gewicht", .repsOnly, .bodyweight, ["quadriceps", "glutes"], ["hamstrings", "core"]),
        TrainingExercise.builtIn("sl_162", "Heel Walk", "Fersengang", .duration, .bodyweight, ["tibialis"], []),
        TrainingExercise.builtIn("sl_163", "Hip Adduction Against Band", "Hüftadduktion mit Band", .weightReps, .bands, ["adductors"], []),
        TrainingExercise.builtIn("sl_165", "Jump Squat", "Sprungkniebeuge", .repsOnly, .bodyweight, ["quadriceps", "glutes"], ["calves", "core"]),
        TrainingExercise.builtIn("sl_166", "Jumping Lunge", "Sprungausfallschritt", .repsOnly, .bodyweight, ["quadriceps", "glutes"], ["calves", "core"]),
        TrainingExercise.builtIn("sl_167", "Kettlebell Front Squat", "Frontkniebeuge mit Kettlebell", .weightReps, .kettlebell, ["quadriceps", "glutes"], ["hamstrings", "core"]),
        TrainingExercise.builtIn("sl_168", "Kettlebell Thrusters", "Thruster mit Kettlebell", .weightReps, .kettlebell, ["quadriceps", "glutes", "shoulders"], ["calves", "core", "triceps"]),
        TrainingExercise.builtIn("sl_169", "Kettlebell Tibialis Raise", "Schienbeinheben mit Kettlebell", .weightReps, .kettlebell, ["tibialis"], []),
        TrainingExercise.builtIn("sl_170", "Landmine Hack Squat", "Landmine-Hackenschmidt-Kniebeuge", .weightReps, .barbell, ["quadriceps", "glutes"], ["hamstrings", "core"]),
        TrainingExercise.builtIn("sl_171", "Landmine Squat", "Landmine-Kniebeuge", .weightReps, .barbell, ["quadriceps", "glutes"], ["hamstrings", "core"]),
        TrainingExercise.builtIn("sl_172", "Lateral Bound", "Seitlicher Sprung (Lateral Bound)", .repsOnly, .bodyweight, ["quadriceps", "glutes"], ["calves", "core"]),
        TrainingExercise.builtIn("sl_173", "Leg Curl On Ball", "Beinbeuger auf dem Gymnastikball", .repsOnly, .bodyweight, ["hamstrings"], ["glutes"]),
        TrainingExercise.builtIn("sl_177", "Nordic Hamstring Eccentric", "Exzentrischer Nordic Curl", .repsOnly, .bodyweight, ["hamstrings"], ["glutes"]),
        TrainingExercise.builtIn("sl_178", "One-Legged Leg Extension", "Einbeiniges Beinstrecken", .weightReps, .machine, ["quadriceps"], []),
        TrainingExercise.builtIn("sl_179", "One-Legged Lying Leg Curl", "Einbeiniger Beinbeuger liegend", .weightReps, .machine, ["hamstrings"], ["glutes"]),
        TrainingExercise.builtIn("sl_180", "One-Legged Seated Leg Curl", "Einbeiniger Beinbeuger sitzend", .weightReps, .machine, ["hamstrings"], ["glutes"]),
        TrainingExercise.builtIn("sl_181", "Pause Squat", "Kniebeuge mit Pause", .weightReps, .barbell, ["quadriceps", "glutes"], ["hamstrings", "core"]),
        TrainingExercise.builtIn("sl_183", "Pin Squat", "Kniebeuge von Ablagen", .weightReps, .barbell, ["quadriceps", "glutes"], ["hamstrings", "core"]),
        TrainingExercise.builtIn("sl_184", "Pistol Squat", "Einbeinige Kniebeuge", .repsOnly, .bodyweight, ["quadriceps", "glutes"], ["hamstrings", "core"]),
        TrainingExercise.builtIn("sl_185", "Poliquin Step-Up", "Poliquin Step-Up", .repsOnly, .bodyweight, ["quadriceps", "glutes"], ["hamstrings", "core"]),
        TrainingExercise.builtIn("sl_186", "Prisoner Get Up", "Prisoner Get-Up", .repsOnly, .bodyweight, ["quadriceps", "glutes"], ["hamstrings", "core"]),
        TrainingExercise.builtIn("sl_187", "Reverse Barbell Lunge", "Rückwärtiger Ausfallschritt mit Langhantel", .weightReps, .barbell, ["quadriceps", "glutes"], ["hamstrings", "core"]),
        TrainingExercise.builtIn("sl_189", "Reverse Dumbbell Lunge", "Rückwärtiger Ausfallschritt mit Kurzhanteln", .weightReps, .dumbbell, ["quadriceps", "glutes"], ["hamstrings", "core"]),
        TrainingExercise.builtIn("sl_190", "Reverse Nordic", "Reverse Nordic", .repsOnly, .bodyweight, ["quadriceps"], []),
        TrainingExercise.builtIn("sl_192", "Safety Bar Squat", "Kniebeuge mit Safety-Bar", .weightReps, .barbell, ["quadriceps", "glutes"], ["hamstrings", "core"]),
        TrainingExercise.builtIn("sl_194", "Shallow Body Weight Lunge", "Kurzer Ausfallschritt ohne Gewicht", .repsOnly, .bodyweight, ["quadriceps", "glutes"], ["hamstrings", "core"]),
        TrainingExercise.builtIn("sl_195", "Side Lunges (Bodyweight)", "Seitlicher Ausfallschritt ohne Zusatzgewicht", .repsOnly, .bodyweight, ["quadriceps", "glutes"], ["hamstrings", "core"]),
        TrainingExercise.builtIn("sl_196", "Sled Push", "Schlitten schieben", .duration, .other, ["quadriceps", "glutes"], ["calves", "core"]),
        TrainingExercise.builtIn("sl_197", "Smith Machine Bulgarian Split Squat", "Bulgarische Kniebeuge an der Multipresse", .weightReps, .machine, ["quadriceps", "glutes"], ["hamstrings", "core"]),
        TrainingExercise.builtIn("sl_198", "Smith Machine Front Squat", "Frontkniebeuge an der Multipresse", .weightReps, .machine, ["quadriceps", "glutes"], ["hamstrings", "core"]),
        TrainingExercise.builtIn("sl_199", "Smith Machine Lunge", "Ausfallschritt an der Multipresse", .weightReps, .machine, ["quadriceps", "glutes"], ["hamstrings", "core"]),
        TrainingExercise.builtIn("sl_200", "Smith Machine Romanian Deadlift", "Rumänisches Kreuzheben an der Multipresse", .weightReps, .machine, ["hamstrings", "glutes"], ["back"]),
        TrainingExercise.builtIn("sl_202", "Sumo Squat", "Sumo-Kniebeuge", .weightReps, .barbell, ["quadriceps", "glutes"], ["hamstrings", "core"]),
        TrainingExercise.builtIn("sl_204", "Standing Cable Leg Extension", "Beinstrecken stehend am Kabelzug", .weightReps, .cable, ["quadriceps"], []),
        TrainingExercise.builtIn("sl_205", "Standing Hip Flexor Raise", "Knieheben im Stehen", .repsOnly, .bodyweight, ["hip_flexors"], ["tibialis", "core"]),
        TrainingExercise.builtIn("sl_206", "Standing Leg Curl", "Beinbeuger stehend", .weightReps, .machine, ["hamstrings"], ["glutes"]),
        TrainingExercise.builtIn("sl_207", "Step Up", "Step-up", .repsOnly, .bodyweight, ["quadriceps", "glutes"], ["hamstrings", "core"]),
        TrainingExercise.builtIn("sl_208", "Tibialis Band Pull", "Schienbeinheben mit Band", .weightReps, .bands, ["tibialis"], []),
        TrainingExercise.builtIn("sl_209", "Tibialis Raise", "Schienbeinheben", .repsOnly, .bodyweight, ["tibialis"], []),
        TrainingExercise.builtIn("sl_210", "Vertical Leg Press", "Vertikale Beinpresse", .weightReps, .machine, ["quadriceps", "glutes"], ["hamstrings", "core"]),
        TrainingExercise.builtIn("sl_211", "Zercher Squat", "Zercher-Kniebeuge", .weightReps, .barbell, ["quadriceps", "glutes"], ["hamstrings", "core"]),
        TrainingExercise.builtIn("sl_212", "Zombie Squat", "Zombie-Kniebeuge", .weightReps, .barbell, ["quadriceps", "glutes"], ["hamstrings", "core"]),
        TrainingExercise.builtIn("sl_213", "Assisted Chin-Up", "Unterstützter Klimmzug im Untergriff", .weightReps, .machine, ["upper_back", "lats"], ["biceps", "forearms"]),
        TrainingExercise.builtIn("sl_215", "Back Extension", "Rückenstrecken", .repsOnly, .bodyweight, ["hamstrings", "glutes", "back"], ["core"]),
        TrainingExercise.builtIn("sl_216", "Banded Muscle-Up", "Muscle-Up mit Bandunterstützung", .weightReps, .bands, ["upper_back", "lats"], ["biceps", "forearms"]),
        TrainingExercise.builtIn("sl_219", "Block Clean", "Clean vom Block", .weightReps, .barbell, ["glutes", "hamstrings", "upper_back"], ["core"]),
        TrainingExercise.builtIn("sl_220", "Block Snatch", "Snatch vom Block", .weightReps, .barbell, ["glutes", "hamstrings", "upper_back"], ["core"]),
        TrainingExercise.builtIn("sl_221", "Cable Close Grip Seated Row", "Sitzendes Kabelrudern mit engem Griff", .weightReps, .cable, ["upper_back", "lats"], ["biceps", "forearms"]),
        TrainingExercise.builtIn("sl_222", "Cable Wide Grip Seated Row", "Sitzendes Kabelrudern mit breitem Griff", .weightReps, .cable, ["upper_back", "lats"], ["biceps", "forearms"]),
        TrainingExercise.builtIn("sl_223", "Chest-Supported Dumbbell Row", "Brustgestütztes Rudern mit Kurzhanteln", .weightReps, .dumbbell, ["upper_back", "lats"], ["biceps", "forearms"]),
        TrainingExercise.builtIn("sl_224", "Chest to Bar", "Chest-to-Bar-Klimmzug", .repsOnly, .bodyweight, ["upper_back", "lats"], ["biceps", "forearms"]),
        TrainingExercise.builtIn("sl_226", "Clean", "Umsetzen (Clean)", .weightReps, .barbell, ["glutes", "hamstrings", "upper_back"], ["core"]),
        TrainingExercise.builtIn("sl_227", "Clean and Jerk", "Umsetzen und Ausstoßen (Clean and Jerk)", .weightReps, .barbell, ["glutes", "hamstrings", "upper_back"], ["core"]),
        TrainingExercise.builtIn("sl_228", "Close-Grip Chin-Up", "Klimmzug im engen Untergriff", .repsOnly, .bodyweight, ["upper_back", "lats"], ["biceps", "forearms"]),
        TrainingExercise.builtIn("sl_229", "Close-Grip Lat Pulldown", "Latzug mit engem Griff", .weightReps, .cable, ["upper_back", "lats"], ["biceps", "forearms"]),
        TrainingExercise.builtIn("sl_231", "Deficit Deadlift", "Kreuzheben mit erhöhtem Stand", .weightReps, .barbell, ["hamstrings", "glutes", "back"], ["core"]),
        TrainingExercise.builtIn("sl_232", "Dumbbell Deadlift", "Kreuzheben mit Kurzhanteln", .weightReps, .dumbbell, ["hamstrings", "glutes", "back"], ["core"]),
        TrainingExercise.builtIn("sl_234", "Dumbbell Shrug", "Schulterheben mit Kurzhanteln", .weightReps, .dumbbell, ["traps"], ["forearms"]),
        TrainingExercise.builtIn("sl_235", "Floor Back Extension", "Rückenstrecken am Boden", .repsOnly, .bodyweight, ["hamstrings", "glutes", "back"], ["core"]),
        TrainingExercise.builtIn("sl_237", "Gorilla Row", "Gorilla Row", .weightReps, .kettlebell, ["upper_back", "lats"], ["biceps", "forearms"]),
        TrainingExercise.builtIn("sl_238", "Hang Clean", "Hang Clean", .weightReps, .barbell, ["glutes", "hamstrings", "upper_back"], ["core"]),
        TrainingExercise.builtIn("sl_239", "Hang Power Clean", "Hang Power Clean", .weightReps, .barbell, ["glutes", "hamstrings", "upper_back"], ["core"]),
        TrainingExercise.builtIn("sl_240", "Hang Power Snatch", "Hang Power Snatch", .weightReps, .barbell, ["glutes", "hamstrings", "upper_back"], ["core"]),
        TrainingExercise.builtIn("sl_241", "Hang Snatch", "Hang Snatch", .weightReps, .barbell, ["glutes", "hamstrings", "upper_back"], ["core"]),
        TrainingExercise.builtIn("sl_242", "Inverted Row", "Inverted Row", .repsOnly, .bodyweight, ["upper_back", "lats"], ["biceps", "forearms"]),
        TrainingExercise.builtIn("sl_243", "Inverted Row with Underhand Grip", "Inverted Row im Untergriff", .repsOnly, .bodyweight, ["upper_back", "lats"], ["biceps", "forearms"]),
        TrainingExercise.builtIn("sl_244", "Jefferson Curl", "Jefferson Curl", .weightReps, .barbell, ["hamstrings", "glutes", "back"], ["core"]),
        TrainingExercise.builtIn("sl_245", "Jumping Muscle-Up", "Muscle-Up mit Absprung", .repsOnly, .bodyweight, ["upper_back", "lats"], ["biceps", "forearms"]),
        TrainingExercise.builtIn("sl_246", "Kettlebell Clean", "Clean mit Kettlebell", .weightReps, .kettlebell, ["glutes", "hamstrings", "upper_back"], ["core"]),
        TrainingExercise.builtIn("sl_247", "Kettlebell Clean & Jerk", "Clean and Jerk mit Kettlebell", .weightReps, .kettlebell, ["glutes", "hamstrings", "upper_back"], ["core"]),
        TrainingExercise.builtIn("sl_250", "Kettlebell Snatch", "Snatch mit Kettlebell", .weightReps, .kettlebell, ["glutes", "hamstrings", "upper_back"], ["core"]),
        TrainingExercise.builtIn("sl_252", "Kroc Row", "Kroc Row", .weightReps, .dumbbell, ["upper_back", "lats"], ["biceps", "forearms"]),
        TrainingExercise.builtIn("sl_253", "Lat Pulldown With Neutral Grip", "Latzug mit Neutralgriff", .weightReps, .cable, ["upper_back", "lats"], ["biceps", "forearms"]),
        TrainingExercise.builtIn("sl_254", "Lat Pulldown With Pronated Grip", "Latzug im Obergriff", .weightReps, .cable, ["upper_back", "lats"], ["biceps", "forearms"]),
        TrainingExercise.builtIn("sl_255", "Lat Pulldown With Supinated Grip", "Latzug im Untergriff", .weightReps, .cable, ["upper_back", "lats"], ["biceps", "forearms"]),
        TrainingExercise.builtIn("sl_257", "Muscle-Up (Bar)", "Muscle-Up an der Stange", .repsOnly, .bodyweight, ["upper_back", "lats"], ["biceps", "forearms"]),
        TrainingExercise.builtIn("sl_258", "Muscle-Up (Rings)", "Muscle-Up an Ringen", .repsOnly, .bodyweight, ["upper_back", "lats"], ["biceps", "forearms"]),
        TrainingExercise.builtIn("sl_259", "Neutral Close-Grip Lat Pulldown", "Enger Latzug im Neutralgriff", .weightReps, .cable, ["upper_back", "lats"], ["biceps", "forearms"]),
        TrainingExercise.builtIn("sl_261", "One-Handed Kettlebell Swing", "Einarmiger Kettlebell Swing", .weightReps, .kettlebell, ["glutes", "hamstrings"], ["upper_back", "core"]),
        TrainingExercise.builtIn("sl_263", "Pause Deadlift", "Kreuzheben mit Pause", .weightReps, .barbell, ["hamstrings", "glutes", "back"], ["core"]),
        TrainingExercise.builtIn("sl_264", "Pendlay Row", "Pendlay Row", .weightReps, .barbell, ["upper_back", "lats"], ["biceps", "forearms"]),
        TrainingExercise.builtIn("sl_265", "Power Clean", "Power Clean", .weightReps, .barbell, ["glutes", "hamstrings", "upper_back"], ["core"]),
        TrainingExercise.builtIn("sl_266", "Power Snatch", "Power Snatch", .weightReps, .barbell, ["glutes", "hamstrings", "upper_back"], ["core"]),
        TrainingExercise.builtIn("sl_268", "Pull-Up With a Neutral Grip", "Klimmzug im Neutralgriff", .repsOnly, .bodyweight, ["upper_back", "lats"], ["biceps", "forearms"]),
        TrainingExercise.builtIn("sl_269", "Rack Pull", "Rack Pull", .weightReps, .barbell, ["glutes", "back"], ["hamstrings", "adductors", "traps", "forearms"]),
        TrainingExercise.builtIn("sl_270", "Renegade Row", "Renegade Row", .weightReps, .dumbbell, ["upper_back", "lats"], ["biceps", "forearms"]),
        TrainingExercise.builtIn("sl_271", "Rope Pulldown", "Pulldown mit Seil", .weightReps, .cable, ["upper_back", "lats"], ["biceps", "forearms"]),
        TrainingExercise.builtIn("sl_272", "Ring Pull-Up", "Klimmzug an Ringen", .repsOnly, .bodyweight, ["upper_back", "lats"], ["biceps", "forearms"]),
        TrainingExercise.builtIn("sl_273", "Ring Row", "Rudern an Ringen", .repsOnly, .bodyweight, ["upper_back", "lats"], ["biceps", "forearms"]),
        TrainingExercise.builtIn("sl_274", "Scap Pull-Up", "Schulterblatt-Klimmzug", .repsOnly, .bodyweight, ["upper_back", "lats"], ["biceps", "forearms"]),
        TrainingExercise.builtIn("sl_275", "Seal Row", "Seal Row", .weightReps, .barbell, ["upper_back", "lats"], ["biceps", "forearms"]),
        TrainingExercise.builtIn("sl_276", "Seated Machine Row", "Sitzendes Rudern an der Maschine", .weightReps, .machine, ["upper_back", "lats"], ["biceps", "forearms"]),
        TrainingExercise.builtIn("sl_277", "Single Leg Deadlift with Kettlebell", "Einbeiniges Kreuzheben mit Kettlebell", .weightReps, .kettlebell, ["hamstrings", "glutes", "back"], ["core"]),
        TrainingExercise.builtIn("sl_278", "Smith Machine Deadlift", "Kreuzheben an der Multipresse", .weightReps, .machine, ["hamstrings", "glutes", "back"], ["core"]),
        TrainingExercise.builtIn("sl_279", "Smith Machine One-Handed Row", "Einarmiges Rudern an der Multipresse", .weightReps, .machine, ["upper_back", "lats"], ["biceps", "forearms"]),
        TrainingExercise.builtIn("sl_280", "Snatch", "Snatch", .weightReps, .barbell, ["glutes", "hamstrings", "upper_back"], ["core"]),
        TrainingExercise.builtIn("sl_281", "Snatch Grip Deadlift", "Kreuzheben im Reißgriff", .weightReps, .barbell, ["hamstrings", "glutes", "back"], ["core"]),
        TrainingExercise.builtIn("sl_282", "Stiff-Legged Deadlift", "Kreuzheben mit gestreckten Beinen", .weightReps, .barbell, ["hamstrings", "glutes", "back"], ["core"]),
        TrainingExercise.builtIn("sl_284", "Sumo Deadlift", "Sumo-Kreuzheben", .weightReps, .barbell, ["hamstrings", "glutes", "back"], ["core"]),
        TrainingExercise.builtIn("sl_285", "Superman Raise", "Superman-Heben", .repsOnly, .bodyweight, ["back", "glutes"], ["hamstrings"]),
        TrainingExercise.builtIn("sl_287", "Towel Row", "Rudern mit Handtuch", .repsOnly, .bodyweight, ["upper_back", "lats"], ["biceps", "forearms"]),
        TrainingExercise.builtIn("sl_288", "Trap Bar Deadlift With High Handles", "Trap-Bar-Kreuzheben mit hohen Griffen", .weightReps, .barbell, ["hamstrings", "glutes", "back"], ["core"]),
        TrainingExercise.builtIn("sl_289", "Trap Bar Deadlift With Low Handles", "Trap-Bar-Kreuzheben mit tiefen Griffen", .weightReps, .barbell, ["hamstrings", "glutes", "back"], ["core"]),
        TrainingExercise.builtIn("sl_290", "Banded Side Kicks", "Seitliches Beinheben mit Band", .weightReps, .bands, ["abductors", "glutes"], []),
        TrainingExercise.builtIn("sl_292", "Cable Pull Through", "Cable Pull-Through", .weightReps, .cable, ["glutes"], ["hamstrings", "core"]),
        TrainingExercise.builtIn("sl_293", "Cable Machine Hip Abduction", "Hüftabduktion am Kabelzug", .weightReps, .machine, ["abductors", "glutes"], []),
        TrainingExercise.builtIn("sl_294", "Clamshells", "Clamshells (Muschelübung)", .repsOnly, .bodyweight, ["abductors", "glutes"], []),
        TrainingExercise.builtIn("sl_295", "Cossack Squat", "Kosakenkniebeuge", .repsOnly, .bodyweight, ["quadriceps", "glutes", "adductors"], ["hamstrings", "core"]),
        TrainingExercise.builtIn("sl_296", "Death March with Dumbbells", "Death March mit Kurzhanteln", .weightReps, .dumbbell, ["glutes"], ["hamstrings", "core"]),
        TrainingExercise.builtIn("sl_297", "Donkey Kicks", "Donkey Kicks", .repsOnly, .bodyweight, ["glutes"], ["hamstrings", "core"]),
        TrainingExercise.builtIn("sl_299", "Dumbbell Frog Pumps", "Frog Pumps mit Kurzhantel", .weightReps, .dumbbell, ["glutes"], ["hamstrings", "core"]),
        TrainingExercise.builtIn("sl_300", "Fire Hydrants", "Fire Hydrants", .repsOnly, .bodyweight, ["abductors", "glutes"], []),
        TrainingExercise.builtIn("sl_301", "Frog Pumps", "Frog Pumps", .repsOnly, .bodyweight, ["glutes"], ["hamstrings", "core"]),
        TrainingExercise.builtIn("sl_303", "Hip Abduction Against Band", "Hüftabduktion mit Band", .weightReps, .bands, ["abductors", "glutes"], []),
        TrainingExercise.builtIn("sl_306", "Hip Thrust Machine", "Hip Thrust an der Maschine", .weightReps, .machine, ["glutes"], ["hamstrings", "core"]),
        TrainingExercise.builtIn("sl_307", "Hip Thrust With Band Around Knees", "Hip Thrust mit Band um die Knie", .weightReps, .bands, ["glutes"], ["hamstrings", "core"]),
        TrainingExercise.builtIn("sl_308", "Kettlebell Windmill", "Windmühle mit Kettlebell", .weightReps, .kettlebell, ["core", "glutes"], ["hamstrings", "shoulders"]),
        TrainingExercise.builtIn("sl_309", "Lateral Walk With Band", "Seitliches Gehen mit Band", .duration, .bands, ["abductors", "glutes"], []),
        TrainingExercise.builtIn("sl_310", "Machine Glute Kickbacks", "Glute Kickback an der Maschine", .weightReps, .machine, ["glutes"], ["hamstrings", "core"]),
        TrainingExercise.builtIn("sl_311", "One-Legged Glute Bridge", "Einbeinige Glute Bridge", .repsOnly, .bodyweight, ["glutes"], ["hamstrings", "core"]),
        TrainingExercise.builtIn("sl_312", "One-Legged Hip Thrust", "Einbeiniger Hip Thrust", .repsOnly, .bodyweight, ["glutes"], ["hamstrings", "core"]),
        TrainingExercise.builtIn("sl_313", "Reverse Hyperextension", "Reverse Hyperextension", .repsOnly, .bodyweight, ["glutes"], ["hamstrings", "core"]),
        TrainingExercise.builtIn("sl_314", "Smith Machine Hip Thrust", "Hip Thrust an der Multipresse", .weightReps, .machine, ["glutes"], ["hamstrings", "core"]),
        TrainingExercise.builtIn("sl_315", "Single Leg Romanian Deadlift", "Einbeiniges rumänisches Kreuzheben", .weightReps, .barbell, ["glutes", "hamstrings", "back"], ["adductors", "traps", "forearms"]),
        TrainingExercise.builtIn("sl_316", "Standing Hip Abduction Against Band", "Hüftabduktion mit Band im Stehen", .weightReps, .bands, ["abductors", "glutes"], []),
        TrainingExercise.builtIn("sl_317", "Standing Glute Kickback in Machine", "Stehender Glute Kickback an der Maschine", .weightReps, .machine, ["glutes"], ["hamstrings", "core"]),
        TrainingExercise.builtIn("sl_318", "Standing Glute Push Down", "Glute Pushdown im Stehen", .weightReps, .cable, ["glutes"], ["hamstrings", "core"]),
        TrainingExercise.builtIn("sl_319", "Ball Slams", "Ball Slams", .weightReps, .other, ["core"], ["obliques"]),
        TrainingExercise.builtIn("sl_320", "Bicycle Crunch", "Fahrrad-Crunch", .repsOnly, .bodyweight, ["core"], ["obliques"]),
        TrainingExercise.builtIn("sl_323", "Captain’s Chair Leg Raise", "Beinheben am Barren", .repsOnly, .bodyweight, ["core"], ["obliques"]),
        TrainingExercise.builtIn("sl_324", "Copenhagen Plank", "Kopenhagen-Plank", .duration, .bodyweight, ["adductors", "core"], ["obliques"]),
        TrainingExercise.builtIn("sl_325", "Core Twist", "Core Twist", .repsOnly, .bodyweight, ["core"], ["obliques"]),
        TrainingExercise.builtIn("sl_326", "Crunch", "Crunch", .repsOnly, .bodyweight, ["core"], ["obliques"]),
        TrainingExercise.builtIn("sl_327", "Dead Bug", "Dead Bug", .repsOnly, .bodyweight, ["core"], ["obliques"]),
        TrainingExercise.builtIn("sl_328", "Dead Bug With Dumbbells", "Dead Bug mit Kurzhanteln", .weightReps, .dumbbell, ["core"], ["obliques"]),
        TrainingExercise.builtIn("sl_329", "Dragon Flag", "Dragon Flag", .repsOnly, .bodyweight, ["core"], ["obliques"]),
        TrainingExercise.builtIn("sl_330", "Dumbbell Side Bend", "Seitbeugen mit Kurzhantel", .weightReps, .dumbbell, ["core"], ["obliques"]),
        TrainingExercise.builtIn("sl_331", "Dynamic Side Plank", "Dynamischer Seitstütz", .repsOnly, .bodyweight, ["core"], ["obliques"]),
        TrainingExercise.builtIn("sl_332", "Hanging Knee Raise", "Hängendes Knieheben", .repsOnly, .bodyweight, ["core"], ["obliques"]),
        TrainingExercise.builtIn("sl_334", "Hanging Sit-Up", "Hängender Sit-up", .repsOnly, .bodyweight, ["core"], ["obliques"]),
        TrainingExercise.builtIn("sl_335", "Hanging Windshield Wiper", "Hängender Scheibenwischer", .repsOnly, .bodyweight, ["core"], ["obliques"]),
        TrainingExercise.builtIn("sl_336", "High to Low Wood Chop with Band", "Holzhacker von oben nach unten mit Band", .weightReps, .bands, ["core"], ["obliques"]),
        TrainingExercise.builtIn("sl_338", "Hollow Body Crunch", "Hollow Body Crunch", .repsOnly, .bodyweight, ["core"], ["obliques"]),
        TrainingExercise.builtIn("sl_339", "Hollow Hold", "Hollow Hold", .duration, .bodyweight, ["core"], ["obliques"]),
        TrainingExercise.builtIn("sl_340", "Horizontal Wood Chop with Band", "Waagerechter Holzhacker mit Band", .weightReps, .bands, ["core"], ["obliques"]),
        TrainingExercise.builtIn("sl_341", "Horizontal Wood Chop with Cable", "Waagerechter Holzhacker am Kabelzug", .weightReps, .cable, ["core"], ["obliques"]),
        TrainingExercise.builtIn("sl_342", "Jackknife Sit-Up", "Klappmesser-Sit-up", .repsOnly, .bodyweight, ["core"], ["obliques"]),
        TrainingExercise.builtIn("sl_343", "Kettlebell Plank Pull Through", "Plank mit Kettlebell-Durchziehen", .weightReps, .kettlebell, ["core"], ["obliques"]),
        TrainingExercise.builtIn("sl_345", "Kneeling Plank", "Unterarmstütz auf Knien", .duration, .bodyweight, ["core"], ["obliques"]),
        TrainingExercise.builtIn("sl_346", "Kneeling Side Plank", "Seitstütz auf Knien", .duration, .bodyweight, ["core"], ["obliques"]),
        TrainingExercise.builtIn("sl_347", "Landmine Rotation", "Rotation mit Landmine-Stange", .weightReps, .barbell, ["core"], ["obliques"]),
        TrainingExercise.builtIn("sl_348", "L-Sit", "L-Sit", .duration, .bodyweight, ["core"], ["obliques"]),
        TrainingExercise.builtIn("sl_349", "Low to High Wood Chop with Band", "Holzhacker von unten nach oben mit Band", .weightReps, .bands, ["core"], ["obliques"]),
        TrainingExercise.builtIn("sl_350", "Low to High Wood Chop with Cable", "Holzhacker von unten nach oben am Kabelzug", .weightReps, .cable, ["core"], ["obliques"]),
        TrainingExercise.builtIn("sl_351", "Lying Leg Raise", "Beinheben in Rückenlage", .repsOnly, .bodyweight, ["core"], ["obliques"]),
        TrainingExercise.builtIn("sl_352", "Lying Windshield Wiper", "Scheibenwischer in Rückenlage", .repsOnly, .bodyweight, ["core"], ["obliques"]),
        TrainingExercise.builtIn("sl_353", "Lying Windshield Wiper with Bent Knees", "Scheibenwischer in Rückenlage mit gebeugten Knien", .repsOnly, .bodyweight, ["core"], ["obliques"]),
        TrainingExercise.builtIn("sl_356", "Oblique Crunch", "Seitlicher Crunch", .repsOnly, .bodyweight, ["core"], ["obliques"]),
        TrainingExercise.builtIn("sl_357", "Oblique Sit-Up", "Seitlicher Sit-up", .repsOnly, .bodyweight, ["core"], ["obliques"]),
        TrainingExercise.builtIn("sl_358", "Pallof Press", "Pallof Press", .weightReps, .cable, ["core"], ["obliques"]),
        TrainingExercise.builtIn("sl_360", "Plank with Leg Lifts", "Plank mit Beinheben", .repsOnly, .bodyweight, ["core"], ["obliques"]),
        TrainingExercise.builtIn("sl_361", "Plank with Shoulder Taps", "Plank mit Schultertippen", .repsOnly, .bodyweight, ["core"], ["obliques"]),
        TrainingExercise.builtIn("sl_362", "Side Plank", "Seitstütz", .duration, .bodyweight, ["core"], ["obliques"]),
        TrainingExercise.builtIn("sl_363", "Sit-Up", "Sit-Up", .repsOnly, .bodyweight, ["core"], ["obliques"]),
        TrainingExercise.builtIn("sl_364", "Weighted Plank", "Plank mit Zusatzgewicht", .duration, .bodyweight, ["core"], ["obliques"]),
        TrainingExercise.builtIn("sl_365", "Barbell Standing Calf Raise", "Wadenheben stehend mit Langhantel", .weightReps, .barbell, ["calves"], []),
        TrainingExercise.builtIn("sl_366", "Barbell Seated Calf Raise", "Wadenheben sitzend mit Langhantel", .weightReps, .barbell, ["calves"], []),
        TrainingExercise.builtIn("sl_367", "Calf Raise in Leg Press", "Wadenheben an der Beinpresse", .weightReps, .machine, ["calves"], []),
        TrainingExercise.builtIn("sl_369", "Eccentric Heel Drop", "Exzentrisches Fersensenken", .repsOnly, .bodyweight, ["calves"], []),
        TrainingExercise.builtIn("sl_370", "Heel Raise", "Fersenheben", .repsOnly, .bodyweight, ["calves"], []),
        TrainingExercise.builtIn("sl_373", "Barbell Wrist Curl", "Handgelenkcurls mit Langhantel", .weightReps, .barbell, ["forearms"], []),
        TrainingExercise.builtIn("sl_374", "Barbell Wrist Curl Behind the Back", "Handgelenkcurls hinter dem Rücken mit Langhantel", .weightReps, .barbell, ["forearms"], []),
        TrainingExercise.builtIn("sl_375", "Bar Hang", "Hängen an der Stange", .duration, .bodyweight, ["forearms"], []),
        TrainingExercise.builtIn("sl_376", "Dumbbell Wrist Curl", "Handgelenkcurls mit Kurzhantel", .weightReps, .dumbbell, ["forearms"], []),
        TrainingExercise.builtIn("sl_377", "Farmers Walk", "Farmer’s Walk", .duration, .dumbbell, ["forearms"], []),
        TrainingExercise.builtIn("sl_378", "Fat Bar Deadlift", "Kreuzheben mit dicker Stange", .weightReps, .barbell, ["glutes", "back", "forearms"], ["quadriceps", "hamstrings", "adductors", "traps"]),
        TrainingExercise.builtIn("sl_379", "Gripper", "Handtrainer (Gripper)", .weightReps, .other, ["forearms"], []),
        TrainingExercise.builtIn("sl_380", "One-Handed Bar Hang", "Einarmiges Hängen an der Stange", .duration, .bodyweight, ["forearms"], []),
        TrainingExercise.builtIn("sl_381", "Plate Pinch", "Gewichtsscheibe im Pinch-Griff halten", .weightReps, .other, ["forearms"], []),
        TrainingExercise.builtIn("sl_382", "Plate Wrist Curl", "Handgelenkcurls mit Gewichtsscheibe", .weightReps, .other, ["forearms"], []),
        TrainingExercise.builtIn("sl_383", "Towel Pull-Up", "Klimmzug mit Handtuchgriff", .repsOnly, .bodyweight, ["lats", "forearms"], ["biceps", "rear_shoulders"]),
        TrainingExercise.builtIn("sl_385", "Barbell Wrist Extension", "Handgelenkstrecken mit Langhantel", .weightReps, .barbell, ["forearms"], []),
        TrainingExercise.builtIn("sl_386", "Dumbbell Wrist Extension", "Handgelenkstrecken mit Kurzhantel", .weightReps, .dumbbell, ["forearms"], []),
        TrainingExercise.builtIn("sl_387", "Lying Neck Curl", "Nackenbeugen im Liegen", .repsOnly, .bodyweight, ["neck"], []),
        TrainingExercise.builtIn("sl_388", "Lying Neck Extension", "Nackenstrecken im Liegen", .repsOnly, .bodyweight, ["neck"], []),
        TrainingExercise.builtIn("sl_389", "Prone Neck Bridge", "Nackenbrücke in Bauchlage", .duration, .bodyweight, ["neck"], []),
        TrainingExercise.builtIn("sl_390", "Supine Neck Bridge", "Nackenbrücke in Rückenlage", .duration, .bodyweight, ["neck"], []),
        TrainingExercise.builtIn("sl_391", "Decline Push-Up", "Liegestütz mit erhöhten Füßen", .repsOnly, .bodyweight, ["chest"], ["triceps", "front_shoulders"]),
        TrainingExercise.builtIn("sl_392", "Dumbbell Chest Press", "Brustdrücken mit Kurzhanteln", .weightReps, .dumbbell, ["chest"], ["triceps", "front_shoulders"]),
        TrainingExercise.builtIn("sl_393", "Dumbbell Decline Chest Press", "Negativbankdrücken mit Kurzhanteln", .weightReps, .dumbbell, ["chest"], ["triceps", "front_shoulders"]),
        TrainingExercise.builtIn("sl_394", "Resistance Band Chest Fly", "Brust-Flys mit Widerstandsband", .weightReps, .bands, ["chest"], ["front_shoulders"]),
        TrainingExercise.builtIn("sl_395", "Cable Front Raise", "Frontheben am Kabelzug", .weightReps, .cable, ["front_shoulders"], []),
        TrainingExercise.builtIn("sl_396", "Face Pull", "Face Pull am Kabelzug", .weightReps, .cable, ["rear_shoulders", "upper_back"], ["biceps"]),
        TrainingExercise.builtIn("sl_397", "Dumbbell Preacher Curl", "Scott-Curl mit Kurzhantel", .weightReps, .dumbbell, ["biceps"], ["forearms"]),
        TrainingExercise.builtIn("sl_398", "Tricep Pushdown With Rope", "Trizepsdrücken mit Seil", .weightReps, .cable, ["triceps"], []),
        TrainingExercise.builtIn("sl_399", "Machine Lat Pulldown", "Latzug an der Maschine", .weightReps, .machine, ["lats", "back"], ["biceps"]),
        TrainingExercise.builtIn("sl_400", "Machine Crunch", "Crunch an der Maschine", .weightReps, .machine, ["core"], []),
        TrainingExercise.builtIn("sl_401", "Captain’s Chair Knee Raise", "Knieheben am Barren", .repsOnly, .bodyweight, ["core"], []),
        TrainingExercise.builtIn("sl_402", "High to Low Wood Chop with Cable", "Holzhacker von oben nach unten am Kabelzug", .weightReps, .cable, ["core"], ["obliques"]),
    ]

    static func guide(for exercise: TrainingExercise, isGerman: Bool) -> String? {
        guard exercise.nameKey.hasPrefix("sl_") else { return nil }
        let name = exercise.englishName.lowercased()
        func has(_ words: String...) -> Bool { words.contains { name.contains($0) } }
        let cue: (de: String, en: String)

        if has("medicine ball chest pass") {
            cue = ("Halte den Medizinball vor der Brust, stelle die Füße stabil und spanne den Rumpf an. Stoße den Ball explosiv mit beiden Händen gerade nach vorn und fange ihn mit leicht gebeugten Armen auf.",
                   "Hold the medicine ball at chest height, plant the feet, and brace the trunk. Drive the ball straight forward with both hands, then catch it with softly bent arms.")
        } else if has("clap push-up") {
            cue = ("Beginne im festen Liegestütz und senke die Brust kontrolliert. Drücke dich explosiv vom Boden ab, klatsche kurz und fange dich mit leicht gebeugten Ellenbogen wieder auf.",
                   "Start in a braced push-up and lower the chest under control. Push explosively off the floor, clap briefly, and catch yourself with softly bent elbows.")
        } else if has("wall walk") {
            cue = ("Beginne mit den Füßen an der Wand im hohen Stütz. Gehe mit den Füßen die Wand hoch und mit den Händen näher zur Wand, soweit du den Rumpf stabil halten kannst; gehe denselben Weg kontrolliert zurück.",
                   "Start in a high plank with your feet against the wall. Walk the feet up and the hands closer to the wall only as far as you can keep the trunk stable, then reverse the path under control.")
        } else if has("landmine press") {
            cue = ("Halte das freie Ende der Stange vor der Schulter und spanne den Rumpf an. Drücke die Stange schräg nach vorn oben, ohne dich zur Seite zu lehnen, und senke sie zur Schulter zurück.",
                   "Hold the free end of the bar in front of the shoulder and brace the trunk. Press it diagonally forward and up without leaning sideways, then lower it back to the shoulder.")
        } else if has("z press") {
            cue = ("Sitze mit gestreckten Beinen auf dem Boden und halte den Rumpf aufrecht. Drücke die Stange über den Kopf, ohne ins Hohlkreuz zu fallen, und senke sie kontrolliert zu den Schultern.",
                   "Sit on the floor with straight legs and an upright trunk. Press the bar overhead without arching the lower back, then lower it to the shoulders under control.")
        } else if has("farmers walk") {
            cue = ("Nimm je eine schwere Hantel in die Hände und lass die Arme lang. Gehe mit aufrechtem Oberkörper und ruhigen Schritten, ohne die Schultern hochzuziehen oder die Gewichte gegen die Beine zu schwingen.",
                   "Hold a heavy dumbbell in each hand with long arms. Walk with an upright torso and steady steps without shrugging or swinging the weights into your legs.")
        } else if has("neck bridge") {
            cue = ("Stütze Kopf und Füße stabil ab, spanne den Rumpf an und bewege den Hals nur in einem kleinen, kontrollierten Bereich. Vermeide Druckspitzen auf die Halswirbelsäule.",
                   "Support your head and feet securely, brace your trunk, and move your neck only through a small controlled range. Avoid sudden pressure on the cervical spine.")
        } else if has("neck curl", "neck extension") {
            cue = ("Lege dich stabil hin und bewege den Kopf langsam gegen leichten Widerstand. Halte den Nacken lang und stoppe vor Schmerzen oder Schwindel.",
                   "Lie in a stable position and move your head slowly against light resistance. Keep your neck long and stop before pain or dizziness.")
        } else if has("clean", "snatch", "jerk", "ground to overhead") {
            cue = ("Starte mit festem Stand und gespanntem Rumpf. Beschleunige das Gewicht durch Strecken von Hüfte und Beinen, fange es stabil ab und kontrolliere die Rückführung.",
                   "Start with a firm stance and braced trunk. Accelerate the load by extending your hips and legs, receive it in a stable position, and control the return.")
        } else if has("turkish get-up", "prisoner get up") {
            cue = ("Beginne am Boden und richte dich Schritt für Schritt über Hand, Knie und Fuß auf. Halte den Oberkörper stabil und kehre die Reihenfolge beim Absenken um.",
                   "Start on the floor and rise step by step using your hand, knee, and foot. Keep your trunk stable and reverse the sequence on the way down.")
        } else if has("kettlebell halo") {
            cue = ("Halte die Kettlebell vor der Brust und führe sie langsam im Kreis um den Kopf. Halte Rippen und Rumpf ruhig und wechsle danach die Richtung.",
                   "Hold the kettlebell in front of your chest and circle it slowly around your head. Keep your ribs and trunk steady, then reverse direction.")
        } else if has("front hold") {
            cue = ("Hebe das Gewicht mit nahezu gestreckten Armen vor den Körper und halte es auf Schulterhöhe. Spanne den Bauch an und vermeide ein Hohlkreuz.",
                   "Raise the load in front of you with nearly straight arms and hold it at shoulder height. Brace your abs and avoid arching your back.")
        } else if has("muscle-up") {
            cue = ("Ziehe dich explosiv bis über die Stange oder Ringe, bringe die Brust über die Hände und drücke dich in den Stütz. Senke dich über dieselben Phasen kontrolliert ab.",
                   "Pull explosively above the bar or rings, bring your chest over your hands, and press into support. Reverse the phases under control.")
        } else if has("plank to push-up") {
            cue = ("Beginne im Unterarmstütz mit festem Rumpf. Stütze erst eine, dann die andere Hand auf und kehre kontrolliert auf die Unterarme zurück, ohne die Hüfte zu verdrehen.",
                   "Start in a forearm plank with a braced trunk. Plant one hand and then the other, then return to your forearms without twisting your hips.")
        } else if has("ball slam") {
            cue = ("Hebe den Ball über den Kopf, spanne den Rumpf an und wirf ihn kraftvoll vor dir auf den Boden. Fange ihn kontrolliert auf und richte dich erneut auf.",
                   "Raise the ball overhead, brace your trunk, and throw it forcefully to the floor in front of you. Catch it under control and reset.")
        } else if has("thruster") {
            cue = ("Gehe mit dem Gewicht vor den Schultern in die Kniebeuge. Strecke Hüfte und Beine kraftvoll und drücke das Gewicht in einem Zug über den Kopf.",
                   "Squat with the load at your shoulders. Extend your hips and legs powerfully and press the load overhead in one continuous motion.")
        } else if has("devils press") {
            cue = ("Stütze dich auf den Hanteln ab, mache einen Liegestütz und springe mit den Füßen nach vorn. Schwinge die Hanteln aus der Hüfte über den Kopf und setze kontrolliert ab.",
                   "Support yourself on the dumbbells, perform a push-up, and hop your feet forward. Drive the dumbbells overhead with your hips and lower them under control.")
        } else if has("cuban press") {
            cue = ("Ziehe die Hanteln mit hohen Ellenbogen zur Brust, drehe die Unterarme nach oben und drücke über den Kopf. Kehre die drei Phasen langsam um.",
                   "Row the dumbbells to chest height with high elbows, rotate your forearms upward, and press overhead. Reverse the three phases slowly.")
        } else if has("hip march", "hip flexor raise") {
            cue = ("Stelle dich aufrecht hin, spanne den Rumpf an und hebe ein Knie gegen den Widerstand bis etwa auf Hüfthöhe. Senke es langsam und ohne Schwung.",
                   "Stand tall, brace your trunk, and lift one knee against resistance to about hip height. Lower it slowly without swinging.")
        } else if has("superman raise") {
            cue = ("Lege dich auf den Bauch und hebe Arme und Beine leicht vom Boden, während der Blick nach unten gerichtet bleibt. Senke sie langsam wieder ab.",
                   "Lie face down and lift your arms and legs slightly from the floor while looking down. Lower them slowly.")
        } else if has("scap pull-up") {
            cue = ("Hänge mit gestreckten Armen an der Stange und ziehe die Schulterblätter nach unten. Hebe den Körper nur wenige Zentimeter und löse die Schulterblätter langsam wieder.",
                   "Hang from the bar with straight arms and pull your shoulder blades down. Lift your body only a few centimeters, then slowly release your shoulder blades.")
        } else if has("nordic hamstring eccentric") {
            cue = ("Fixiere die Unterschenkel, halte Hüfte und Rumpf gestreckt und lasse den Körper langsam nach vorn sinken. Fange dich mit den Händen ab und richte dich erneut auf.",
                   "Secure your lower legs, keep your hips and trunk straight, and lower your body forward slowly. Catch yourself with your hands and reset.")
        } else if has("reverse nordic") {
            cue = ("Knie aufrecht mit gestreckter Hüfte und lehne den Körper als Einheit langsam nach hinten. Spanne die Oberschenkelvorderseite an, um wieder aufzurichten.",
                   "Kneel upright with your hips extended and lean your body backward as one unit. Use your quads to return upright.")
        } else if has("dead bug") {
            cue = ("Lege dich auf den Rücken, halte die Lendenwirbelsäule ruhig und strecke abwechselnd einen Arm und das gegenüberliegende Bein. Kehre kontrolliert zur Mitte zurück.",
                   "Lie on your back, keep your lower back steady, and alternately extend one arm and the opposite leg. Return to center under control.")
        } else if has("pallof press") {
            cue = ("Stehe seitlich zum Kabelzug oder Band, halte die Hände vor der Brust und drücke sie gerade nach vorn. Widerstehe der Drehung und ziehe die Hände langsam zurück.",
                   "Stand sideways to the cable or band, hold your hands at your chest, and press them straight forward. Resist rotation and return slowly.")
        } else if has("copenhagen plank") {
            cue = ("Stütze dich seitlich auf dem Unterarm ab und lege das obere Bein auf eine Bank. Hebe die Hüfte an, sodass Rumpf und Beine eine Linie bilden.",
                   "Support yourself on one forearm with your upper leg on a bench. Lift your hips until your trunk and legs form a straight line.")
        } else if has("windmill") {
            cue = ("Halte die Kettlebell mit gestrecktem Arm über der Schulter, schiebe die Hüfte zur Seite und neige den Oberkörper kontrolliert. Richte dich mit stabilem Rumpf wieder auf.",
                   "Hold the kettlebell over your shoulder with a straight arm, shift your hips sideways, and lower your torso under control. Stand again with a stable trunk.")
        } else if has("jump", "bound") {
            cue = ("Beuge Hüfte und Knie leicht, springe explosiv ab und lande leise mit gebeugten Knien. Richte die Knie über den Füßen aus und stabilisiere die Landung.",
                   "Bend your hips and knees slightly, jump explosively, and land softly with bent knees. Keep your knees over your feet and stabilize the landing.")
        } else if has("sled push") {
            cue = ("Lehne dich mit festem Rumpf gegen den Schlitten und drücke ihn mit kurzen, kräftigen Schritten vorwärts. Halte Rücken und Arme stabil.",
                   "Lean into the sled with a braced trunk and drive it forward with short, strong steps. Keep your back and arms stable.")
        } else if has("deadlift", "good morning", "pull through", "jefferson curl", "death march", "swing", "back extension", "hyperextension", "rack pull") {
            cue = ("Stelle die Füße stabil auf, schiebe die Hüfte nach hinten und führe das Gewicht nah am Körper. Strecke die Hüfte zum Aufrichten und kontrolliere den Rückweg.",
                   "Set your feet firmly, push your hips back, and keep the load close to your body. Extend your hips to stand and control the return.")
        } else if has("leg curl", "ham raise", "nordic") {
            cue = ("Halte Hüfte und Oberkörper stabil und beuge die Knie gegen den Widerstand. Senke die Unterschenkel langsam zurück, ohne ins Hohlkreuz zu fallen.",
                   "Keep your hips and trunk stable and bend your knees against the resistance. Lower your legs slowly without arching your lower back.")
        } else if has("leg extension", "reverse nordic") {
            cue = ("Richte das Kniegelenk passend zur Maschine oder Ausgangsposition aus. Strecke die Knie kontrolliert und senke langsam ab, ohne Schwung zu holen.",
                   "Align your knees with the machine or starting position. Extend them under control and lower slowly without swinging.")
        } else if has("calf", "heel raise", "heel drop") {
            cue = ("Stelle die Fußballen stabil auf, hebe die Fersen so hoch wie möglich und senke sie langsam in die Dehnung. Halte die Knie in der vorgesehenen Position.",
                   "Place the balls of your feet securely, lift your heels as high as possible, and lower slowly into the stretch. Keep your knees in the intended position.")
        } else if has("tibialis", "heel walk") {
            cue = ("Ziehe die Fußspitzen zum Schienbein, während die Fersen am Boden bleiben oder kontrolliert aufsetzen. Senke die Füße langsam zurück.",
                   "Pull your toes toward your shins while your heels stay grounded or land under control. Lower your feet slowly.")
        } else if has("abduction", "adduction", "clamshell", "side kick", "lateral walk", "fire hydrant") {
            cue = ("Halte Becken und Oberkörper ruhig und bewege das Bein kontrolliert gegen den Widerstand zur Seite oder zur Mitte. Kehre langsam zurück.",
                   "Keep your pelvis and trunk still as you move the leg sideways or inward against resistance. Return slowly.")
        } else if has("hip thrust", "glute bridge", "frog pump", "kickback", "glute push down", "donkey kick") {
            cue = ("Spanne den Bauch an und strecke die Hüfte aus dem Gesäß, bis Rumpf und Oberschenkel eine Linie bilden. Vermeide ein Überstrecken des unteren Rückens.",
                   "Brace your abs and extend your hips using your glutes until trunk and thighs form a line. Avoid overextending your lower back.")
        } else if has("squat", "lunge", "step up", "step-up", "leg press", "chair squat") {
            cue = ("Stelle die Füße stabil auf und beuge Hüfte und Knie kontrolliert. Halte die Knie in Richtung der Fußspitzen und drücke dich über den ganzen Fuß zurück.",
                   "Plant your feet and bend your hips and knees under control. Track your knees with your toes and push back through your whole foot.")
        } else if has("pull-up", "chin-up", "pulldown", "muscle-up", "chest to bar") {
            cue = ("Beginne mit aktiven Schultern und ziehe die Ellenbogen nach unten zum Rumpf. Führe dich oder den Griff kontrolliert zurück, bis die Arme wieder lang sind.",
                   "Start with active shoulders and drive your elbows down toward your trunk. Return yourself or the handle under control until your arms are long.")
        } else if has("rear delt row") {
            cue = ("Stütze den Oberkörper ab oder halte ihn ruhig und ziehe die Ellenbogen seitlich nach hinten. Halte die Hände etwa auf Brusthöhe und führe das Gewicht langsam zurück, ohne den Rücken aufzurichten.",
                   "Support or brace the torso and row the elbows out and back. Keep the hands near chest height and return the load slowly without lifting the trunk.")
        } else if has("row", "towel row") {
            cue = ("Halte Rumpf und Rücken stabil und ziehe Griff oder Gewicht zum Oberkörper. Führe die Ellenbogen zurück und strecke die Arme langsam wieder.",
                   "Keep your trunk and back stable and pull the handle or load toward your body. Drive your elbows back and slowly extend your arms again.")
        } else if has("shrug") {
            cue = ("Halte die Arme lang und bewege die Schulterblätter kontrolliert nach oben oder hinten. Halte kurz und senke ohne Schwung ab.",
                   "Keep your arms long and move your shoulder blades up or back under control. Pause briefly and lower without momentum.")
        } else if has("wrist", "gripper", "pinch", "bar hang", "farmers walk") {
            cue = ("Greife den Widerstand fest, halte Schultern und Handgelenke stabil und bewege nur das vorgesehene Gelenk. Löse den Griff oder senke das Gewicht kontrolliert.",
                   "Grip the resistance firmly, keep shoulders and wrists stable, and move only the intended joint. Release your grip or lower the load under control.")
        } else if has("curl") {
            cue = ("Halte die Oberarme möglichst ruhig und beuge die Ellenbogen gegen den Widerstand. Senke das Gewicht langsam ab, ohne den Oberkörper zu schwingen.",
                   "Keep your upper arms mostly still and bend your elbows against the resistance. Lower the load slowly without swinging your torso.")
        } else if has("tricep", "triceps", "skull crusher", "tate press") {
            cue = ("Halte die Oberarme stabil und strecke die Ellenbogen kontrolliert gegen den Widerstand. Beuge die Arme langsam wieder, ohne die Schultern mitzubewegen.",
                   "Keep your upper arms steady and extend your elbows against the resistance. Bend them slowly again without moving your shoulders.")
        } else if has("bench dip", "close-grip push-up") {
            cue = ("Halte den Rumpf stabil und die Ellenbogen nah am Körper. Beuge die Arme kontrolliert und drücke dich durch Strecken der Ellenbogen wieder hoch.",
                   "Keep your trunk stable and your elbows close to your sides. Bend your arms under control, then press yourself up by extending your elbows.")
        } else if has("dip", "push-up", "press", "chest pass") && exercise.primaryMuscles.contains("chest") {
            cue = ("Stabilisiere Schultern und Rumpf, senke den Körper oder das Gewicht kontrolliert zur Brust und drücke wieder nach oben oder vorn. Halte die Ellenbogen in einer angenehmen Bahn.",
                   "Stabilize your shoulders and trunk, lower your body or the load toward your chest, then press up or forward. Keep your elbows on a comfortable path.")
        } else if (has("reverse") && has("fly", "flyes", "flys")) || has("rear delt fly", "face pull") {
            cue = ("Halte die Brust stabil und führe die Arme seitlich nach hinten oder den Griff zum Gesicht. Ziehe die Schulterblätter sanft zusammen und kehre ohne Schwung zurück.",
                   "Keep the chest stable and open the arms back or draw the handle toward the face. Gently bring the shoulder blades together, then return without momentum.")
        } else if has("fly", "flyes", "flys", "pec deck") && exercise.primaryMuscles.contains("chest") {
            cue = ("Halte die Ellenbogen leicht gebeugt und führe die Arme in einem weiten Bogen vor dem Körper zusammen. Öffne sie langsam bis zu einer angenehmen Brustdehnung.",
                   "Keep a slight bend in your elbows and sweep your arms together in front of your body. Open them slowly to a comfortable chest stretch.")
        } else if has("shoulder rotation", "external shoulder", "internal shoulder") {
            cue = ("Fixiere den Oberarm am Körper und drehe den Unterarm langsam gegen leichten Widerstand. Halte Schulter und Rumpf ruhig.",
                   "Keep your upper arm close to your body and rotate your forearm slowly against light resistance. Keep your shoulder and trunk still.")
        } else if has("raise", "fly", "flyes", "flys", "pull-apart", "face pull", "poliquin") &&
                    (exercise.primaryMuscles.contains("shoulders") || exercise.primaryMuscles.contains("front_shoulders") || exercise.primaryMuscles.contains("rear_shoulders")) {
            cue = ("Hebe oder öffne die Arme kontrolliert bis etwa auf Schulterhöhe. Halte den Nacken lang und senke den Widerstand langsam ohne Schwung.",
                   "Raise or open your arms under control to about shoulder height. Keep your neck long and lower the resistance slowly without swinging.")
        } else if has("press", "jerk", "wall walk", "handstand") && exercise.primaryMuscles.contains("shoulders") {
            cue = ("Spanne Bauch und Gesäß an und drücke den Widerstand über den Kopf. Führe die Arme kontrolliert zur Ausgangsposition zurück, ohne ins Hohlkreuz zu fallen.",
                   "Brace your abs and glutes and press the resistance overhead. Return your arms under control without arching your lower back.")
        } else if has("crunch", "sit-up", "jackknife", "dragon flag") {
            cue = ("Spanne den Bauch an und rolle den Oberkörper kontrolliert ein oder hebe ihn an. Senke langsam ab, ohne mit Armen oder Nacken zu ziehen.",
                   "Brace your abs and curl or lift your trunk under control. Lower slowly without pulling with your arms or neck.")
        } else if has("plank", "hollow", "l-sit", "dead bug", "pallof") {
            cue = ("Spanne Bauch und Gesäß an und halte den Rumpf stabil. Atme ruhig weiter und verhindere, dass Becken oder Rücken ausweichen.",
                   "Brace your abs and glutes and keep your trunk stable. Breathe steadily and prevent your pelvis or back from shifting.")
        } else if has("leg raise", "knee raise", "windshield wiper", "mountain climber") {
            cue = ("Halte den Oberkörper stabil und hebe Beine oder Knie mit dem Bauch an. Senke sie kontrolliert, ohne den unteren Rücken stark zu überstrecken.",
                   "Keep your trunk stable and lift your legs or knees using your abs. Lower under control without strongly arching your lower back.")
        } else if has("wood chop", "rotation", "twist", "side bend") {
            cue = ("Spanne den Rumpf an und bewege Arme und Oberkörper kontrolliert in die vorgesehene Richtung. Vermeide ruckartige Drehungen und kehre langsam zurück.",
                   "Brace your trunk and move your arms and torso in the intended direction under control. Avoid jerky twists and return slowly.")
        } else if exercise.equipment == .cardio {
            cue = ("Stelle das Gerät passend ein und beginne in einem gleichmäßigen, gut kontrollierbaren Tempo. Halte den Oberkörper ruhig und steigere die Belastung schrittweise.",
                   "Adjust the machine and begin at a steady, manageable pace. Keep your torso stable and increase the effort gradually.")
        } else {
            cue = ("Nimm eine stabile Ausgangsposition ein, bewege den Widerstand kontrolliert durch den vorgesehenen Bewegungsumfang und führe ihn langsam zurück. Halte den Rumpf ruhig.",
                   "Set a stable starting position, move the resistance through the intended range under control, and return it slowly. Keep your trunk steady.")
        }
        let detail: (de: String, en: String)?
        switch exercise.nameKey {
        case "sl_002":
            detail = ("Befestige das Band so, dass es die Hantel am unteren Punkt des Bankdrückens unterstützt.",
                      "Attach the band so it assists the bar at the bottom of the bench press.")
        case "sl_005":
            detail = ("Befestige die Bänder unter der Bank oder Hantel, sodass ihr Widerstand beim Hochdrücken zunimmt.",
                      "Anchor the bands beneath the bench or bar so resistance rises as you press upward.")
        case "sl_006":
            detail = ("Lege ein Board auf die Brust und senke die Stange nur bis zum Kontakt mit dem Board.",
                      "Place a board on the chest and lower the bar only until it touches the board.")
        case "sl_010", "sl_015":
            detail = ("Hebe die Füße von Boden und Bank ab und halte Bauch und Gesäß angespannt, damit das Becken ruhig bleibt.",
                      "Lift the feet clear of the floor and bench, and brace abs and glutes to keep the pelvis steady.")
        case "sl_013", "sl_016", "sl_020":
            detail = ("Lege dich auf den Boden und stoppe das Absenken, sobald die Oberarme den Boden berühren.",
                      "Lie on the floor and stop lowering once the upper arms touch it.")
        case "sl_027":
            detail = ("Stelle die Sicherheitsablagen so ein, dass die Stange knapp über der Brust aus dem Stillstand startet.",
                      "Set the safety pins so the bar starts from a dead stop just above the chest.")
        case "sl_031":
            detail = ("Hänge beide Füße sicher in die Ringe und halte die Beine während des Liegestützes ruhig.",
                      "Secure both feet in the rings and keep the legs steady through the push-up.")
        case "sl_033":
            detail = ("Halte die Ringe eng am Körper und stabilisiere sie, bevor du die Ellenbogen beugst.",
                      "Keep the rings close to the body and stabilize them before bending the elbows.")
        case "sl_034", "sl_038":
            detail = ("Stelle die Kabelrollen auf Brusthöhe und führe die Griffe mit leicht gebeugten Ellenbogen zusammen.",
                      "Set the pulleys near chest height and bring the handles together with softly bent elbows.")
        case "sl_039", "sl_394":
            detail = ("Verankere das Band hinter dir auf Brusthöhe und halte es während des gesamten Flys unter Spannung.",
                      "Anchor the band behind you near chest height and keep it under tension throughout the fly.")
        case "sl_075":
            detail = ("Trainiere einen Arm nach dem anderen und halte den Oberkörper beim schrägen Hochdrücken gerade.",
                      "Train one arm at a time and keep the torso square during the diagonal press.")
        case "sl_115":
            detail = ("Stelle die Kabelrollen hoch und halte die Oberarme seitlich auf Schulterhöhe.",
                      "Set the pulleys high and hold the upper arms out at shoulder height.")
        case "sl_130", "sl_131", "sl_132":
            detail = ("Halte die Ellenbogen neben dem Kopf und senke die Hände hinter den Kopf, bevor du die Arme streckst.",
                      "Keep the elbows beside the head and lower the hands behind it before extending the arms.")
        case "sl_178":
            detail = ("Richte ein Knie an der Maschinenachse aus und benutze nur dieses Bein zum Beinstrecken.",
                      "Align one knee with the machine pivot and use only that leg to extend the pad.")
        case "sl_204":
            detail = ("Befestige die Fußschlaufe am tiefen Kabel und strecke das Knie im Stand, während der Oberschenkel ruhig bleibt.",
                      "Attach an ankle cuff to the low cable and extend the knee while standing, keeping the thigh still.")
        default:
            detail = nil
        }
        let movement = isGerman ? cue.de : cue.en
        guard let detail else { return movement }
        return "\(isGerman ? detail.de : detail.en) \(movement)"
    }
}
