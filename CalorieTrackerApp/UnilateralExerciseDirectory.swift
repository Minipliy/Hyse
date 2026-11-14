import Foundation

// Side-specific options for movements that can be trained independently.
// Keep keys distinct from existing catalog entries so saved workouts stay stable.
nonisolated enum UnilateralExerciseDirectory {
    static let exercises: [TrainingExercise] = [
        TrainingExercise.builtIn("uni_001_single_leg_press", "Single-Leg Leg Press", "Einbeinige Beinpresse", .weightReps, .machine, ["quadriceps", "glutes"], ["hamstrings"]),
        TrainingExercise.builtIn("uni_002_single_leg_vertical_press", "Single-Leg Vertical Leg Press", "Einbeinige vertikale Beinpresse", .weightReps, .machine, ["quadriceps", "glutes"], ["hamstrings", "core"]),
        TrainingExercise.builtIn("uni_003_single_leg_hack_squat", "Single-Leg Hack Squat", "Einbeinige Hackenschmidt-Kniebeuge", .weightReps, .machine, ["quadriceps", "glutes"], ["hamstrings"]),
        TrainingExercise.builtIn("uni_004_single_leg_standing_calf_raise", "Single-Leg Standing Calf Raise", "Einbeiniges Wadenheben stehend", .weightReps, .machine, ["calves"], []),
        TrainingExercise.builtIn("uni_005_single_leg_seated_calf_raise", "Single-Leg Seated Calf Raise", "Einbeiniges Wadenheben sitzend", .weightReps, .machine, ["calves"], []),
        TrainingExercise.builtIn("uni_006_single_leg_calf_press", "Single-Leg Calf Press in Leg Press", "Einbeiniges Wadenheben an der Beinpresse", .weightReps, .machine, ["calves"], []),
        TrainingExercise.builtIn("uni_007_single_leg_donkey_calf_raise", "Single-Leg Donkey Calf Raise", "Einbeiniges Donkey-Wadenheben", .weightReps, .machine, ["calves"], []),
        TrainingExercise.builtIn("uni_008_single_leg_heel_raise", "Single-Leg Heel Raise", "Einbeiniges Fersenheben", .repsOnly, .bodyweight, ["calves"], []),
        TrainingExercise.builtIn("uni_009_single_leg_tibialis_raise", "Single-Leg Tibialis Raise", "Einbeiniges Schienbeinheben", .repsOnly, .bodyweight, ["tibialis"], []),
        TrainingExercise.builtIn("uni_010_single_leg_box_squat", "Single-Leg Box Squat", "Einbeinige Kniebeuge zur Box", .repsOnly, .bodyweight, ["quadriceps", "glutes"], ["hamstrings", "core"]),
        TrainingExercise.builtIn("uni_011_single_leg_belt_squat", "Single-Leg Belt Squat", "Einbeinige Kniebeuge mit Hüftgurt", .weightReps, .machine, ["quadriceps", "glutes"], ["hamstrings", "core"]),
        TrainingExercise.builtIn("uni_012_single_leg_smith_squat", "Single-Leg Smith Machine Squat", "Einbeinige Kniebeuge an der Multipresse", .weightReps, .machine, ["quadriceps", "glutes"], ["hamstrings", "core"]),
        TrainingExercise.builtIn("uni_013_single_leg_dumbbell_rdl", "Single-Leg Dumbbell Romanian Deadlift", "Einbeiniges rumänisches Kreuzheben mit Kurzhantel", .weightReps, .dumbbell, ["hamstrings", "glutes"], ["back"]),
        TrainingExercise.builtIn("uni_014_single_leg_bodyweight_rdl", "Single-Leg Bodyweight Romanian Deadlift", "Einbeiniges rumänisches Kreuzheben ohne Gewicht", .repsOnly, .bodyweight, ["hamstrings", "glutes", "back"], ["core"]),
        TrainingExercise.builtIn("uni_015_single_leg_back_extension", "Single-Leg Back Extension", "Einbeiniges Rückenstrecken", .weightReps, .bodyweight, ["hamstrings", "glutes"], ["back"]),
        TrainingExercise.builtIn("uni_016_single_leg_reverse_hyper", "Single-Leg Reverse Hyperextension", "Einbeinige Reverse Hyperextension", .repsOnly, .bodyweight, ["glutes"], ["hamstrings", "core"]),
        TrainingExercise.builtIn("uni_017_single_leg_ball_curl", "Single-Leg Stability Ball Leg Curl", "Einbeiniger Beinbeuger auf dem Gymnastikball", .repsOnly, .bodyweight, ["hamstrings"], ["glutes"]),
        TrainingExercise.builtIn("uni_018_single_leg_bodyweight_curl", "Single-Leg Bodyweight Leg Curl", "Einbeiniger Beinbeuger mit Körpergewicht", .repsOnly, .bodyweight, ["hamstrings"], ["glutes"]),
        TrainingExercise.builtIn("uni_019_single_leg_hip_thrust_machine", "Single-Leg Machine Hip Thrust", "Einbeiniger Hip Thrust an der Maschine", .weightReps, .machine, ["glutes"], ["hamstrings", "core"]),
        TrainingExercise.builtIn("uni_020_single_leg_smith_hip_thrust", "Single-Leg Smith Machine Hip Thrust", "Einbeiniger Hip Thrust an der Multipresse", .weightReps, .machine, ["glutes"], ["hamstrings", "core"]),
        TrainingExercise.builtIn("uni_021_single_leg_barbell_hip_thrust", "Single-Leg Barbell Hip Thrust", "Einbeiniger Hip Thrust mit Langhantel", .weightReps, .barbell, ["glutes"], ["hamstrings", "core"]),
        TrainingExercise.builtIn("uni_022_single_leg_banded_glute_bridge", "Single-Leg Banded Glute Bridge", "Einbeinige Glute Bridge mit Band", .weightReps, .bands, ["glutes"], ["hamstrings", "core"]),
        TrainingExercise.builtIn("uni_023_single_arm_dumbbell_row", "Single-Arm Dumbbell Row", "Einarmiges Kurzhantelrudern", .weightReps, .dumbbell, ["upper_back", "lats"], ["biceps", "rear_shoulders"]),
        TrainingExercise.builtIn("uni_024_single_arm_chest_supported_row", "Single-Arm Chest-Supported Dumbbell Row", "Einarmiges brustgestütztes Rudern mit Kurzhantel", .weightReps, .dumbbell, ["upper_back", "lats"], ["biceps", "forearms"]),
        TrainingExercise.builtIn("uni_025_single_arm_machine_row", "Single-Arm Seated Machine Row", "Einarmiges Rudern sitzend an der Maschine", .weightReps, .machine, ["upper_back", "lats"], ["biceps", "forearms"]),
        TrainingExercise.builtIn("uni_026_single_arm_supported_machine_row", "Single-Arm Chest-Supported Machine Row", "Einarmiges brustgestütztes Rudern an der Maschine", .weightReps, .machine, ["upper_back", "lats"], ["biceps", "rear_shoulders"]),
        TrainingExercise.builtIn("uni_027_single_arm_band_row", "Single-Arm Resistance Band Row", "Einarmiges Rudern mit Widerstandsband", .weightReps, .bands, ["upper_back", "lats"], ["biceps", "rear_shoulders"]),
        TrainingExercise.builtIn("uni_028_single_arm_cable_rear_delt_row", "Single-Arm Cable Rear Delt Row", "Einarmiges Kabelrudern für die hintere Schulter", .weightReps, .cable, ["rear_shoulders", "upper_back"], []),
        TrainingExercise.builtIn("uni_029_single_arm_dumbbell_rear_delt_row", "Single-Arm Dumbbell Rear Delt Row", "Einarmiges Kurzhantelrudern für die hintere Schulter", .weightReps, .dumbbell, ["rear_shoulders", "upper_back"], []),
        TrainingExercise.builtIn("uni_030_single_arm_lat_pulldown_machine", "Single-Arm Machine Lat Pulldown", "Einarmiger Latzug an der Maschine", .weightReps, .machine, ["lats", "back"], ["biceps"]),
        TrainingExercise.builtIn("uni_031_single_arm_neutral_lat_pulldown", "Single-Arm Neutral-Grip Lat Pulldown", "Einarmiger Latzug im Neutralgriff", .weightReps, .cable, ["upper_back", "lats"], ["biceps", "forearms"]),
        TrainingExercise.builtIn("uni_032_single_arm_straightarm_pulldown", "Single-Arm Straight-Arm Pulldown", "Einarmiger Überzug am Kabelzug", .weightReps, .cable, ["lats"], ["triceps"]),
        TrainingExercise.builtIn("uni_033_single_arm_dumbbell_shrug", "Single-Arm Dumbbell Shrug", "Einarmiges Schulterheben mit Kurzhantel", .weightReps, .dumbbell, ["traps"], ["forearms"]),
        TrainingExercise.builtIn("uni_034_single_arm_cable_chest_press", "Single-Arm Cable Chest Press", "Einarmiges Brustdrücken am Kabelzug", .weightReps, .cable, ["chest"], ["triceps", "front_shoulders"]),
        TrainingExercise.builtIn("uni_035_single_arm_band_chest_press", "Single-Arm Resistance Band Chest Press", "Einarmiges Brustdrücken mit Widerstandsband", .weightReps, .bands, ["chest"], ["triceps"]),
        TrainingExercise.builtIn("uni_036_single_arm_dumbbell_chest_press", "Single-Arm Dumbbell Chest Press", "Einarmiges Brustdrücken mit Kurzhantel", .weightReps, .dumbbell, ["chest"], ["triceps", "front_shoulders"]),
        TrainingExercise.builtIn("uni_037_single_arm_dumbbell_floor_press", "Single-Arm Dumbbell Floor Press", "Einarmiges Floor Press mit Kurzhantel", .weightReps, .dumbbell, ["chest"], ["triceps", "front_shoulders"]),
        TrainingExercise.builtIn("uni_038_single_arm_kettlebell_floor_press", "Single-Arm Kettlebell Floor Press", "Einarmiges Floor Press mit Kettlebell", .weightReps, .kettlebell, ["chest"], ["triceps", "front_shoulders"]),
        TrainingExercise.builtIn("uni_039_single_arm_incline_dumbbell_press", "Single-Arm Incline Dumbbell Press", "Einarmiges Schrägbankdrücken mit Kurzhantel", .weightReps, .dumbbell, ["chest"], ["triceps", "front_shoulders"]),
        TrainingExercise.builtIn("uni_040_single_arm_dumbbell_fly", "Single-Arm Dumbbell Chest Fly", "Einarmiges Brust-Fly mit Kurzhantel", .weightReps, .dumbbell, ["chest"], ["front_shoulders"]),
        TrainingExercise.builtIn("uni_041_single_arm_cable_fly", "Single-Arm Cable Chest Fly", "Einarmiges Brust-Fly am Kabelzug", .weightReps, .cable, ["chest"], ["front_shoulders"]),
        TrainingExercise.builtIn("uni_042_single_arm_low_high_cable_fly", "Single-Arm Low-to-High Cable Fly", "Einarmiges Kabel-Fly von unten nach oben", .weightReps, .cable, ["chest"], ["front_shoulders"]),
        TrainingExercise.builtIn("uni_043_single_arm_band_chest_fly", "Single-Arm Resistance Band Chest Fly", "Einarmiges Brust-Fly mit Widerstandsband", .weightReps, .bands, ["chest"], ["front_shoulders"]),
        TrainingExercise.builtIn("uni_044_single_arm_push_up", "Single-Arm Push-Up", "Einarmiger Liegestütz", .repsOnly, .bodyweight, ["chest"], ["triceps", "shoulders"]),
        TrainingExercise.builtIn("uni_045_single_arm_dumbbell_shoulder_press", "Single-Arm Dumbbell Shoulder Press", "Einarmiges Kurzhantel-Schulterdrücken", .weightReps, .dumbbell, ["front_shoulders", "shoulders"], ["triceps"]),
        TrainingExercise.builtIn("uni_046_single_arm_seated_dumbbell_press", "Single-Arm Seated Dumbbell Shoulder Press", "Einarmiges Schulterdrücken sitzend mit Kurzhantel", .weightReps, .dumbbell, ["shoulders"], ["triceps"]),
        TrainingExercise.builtIn("uni_047_single_arm_kettlebell_press", "Single-Arm Kettlebell Press", "Einarmiges Schulterdrücken mit Kettlebell", .weightReps, .kettlebell, ["shoulders"], ["triceps"]),
        TrainingExercise.builtIn("uni_048_single_arm_kettlebell_push_press", "Single-Arm Kettlebell Push Press", "Einarmige Push Press mit Kettlebell", .weightReps, .kettlebell, ["shoulders"], ["triceps"]),
        TrainingExercise.builtIn("uni_049_single_arm_dumbbell_arnold_press", "Single-Arm Arnold Press", "Einarmige Arnold Press", .weightReps, .dumbbell, ["front_shoulders", "shoulders"], ["triceps"]),
        TrainingExercise.builtIn("uni_050_single_arm_dumbbell_lateral_raise", "Single-Arm Dumbbell Lateral Raise", "Einarmiges Seitheben mit Kurzhantel", .weightReps, .dumbbell, ["shoulders"], []),
        TrainingExercise.builtIn("uni_051_single_arm_cable_lateral_raise", "Single-Arm Cable Lateral Raise", "Einarmiges Seitheben am Kabelzug", .weightReps, .cable, ["shoulders"], []),
        TrainingExercise.builtIn("uni_052_single_arm_band_lateral_raise", "Single-Arm Resistance Band Lateral Raise", "Einarmiges Seitheben mit Widerstandsband", .weightReps, .bands, ["shoulders"], []),
        TrainingExercise.builtIn("uni_053_single_arm_dumbbell_front_raise", "Single-Arm Dumbbell Front Raise", "Einarmiges Frontheben mit Kurzhantel", .weightReps, .dumbbell, ["front_shoulders"], []),
        TrainingExercise.builtIn("uni_054_single_arm_cable_front_raise", "Single-Arm Cable Front Raise", "Einarmiges Frontheben am Kabelzug", .weightReps, .cable, ["front_shoulders"], []),
        TrainingExercise.builtIn("uni_055_single_arm_reverse_cable_fly", "Single-Arm Reverse Cable Fly", "Einarmiges Reverse Fly am Kabelzug", .weightReps, .cable, ["rear_shoulders", "upper_back"], []),
        TrainingExercise.builtIn("uni_056_single_arm_reverse_dumbbell_fly", "Single-Arm Reverse Dumbbell Fly", "Einarmiges Reverse Fly mit Kurzhantel", .weightReps, .dumbbell, ["rear_shoulders", "upper_back"], []),
        TrainingExercise.builtIn("uni_057_single_arm_cable_face_pull", "Single-Arm Cable Face Pull", "Einarmiger Face Pull am Kabelzug", .weightReps, .cable, ["rear_shoulders", "upper_back"], ["biceps"]),
        TrainingExercise.builtIn("uni_058_single_arm_dumbbell_biceps_curl", "Single-Arm Dumbbell Biceps Curl", "Einarmiger Bizepscurl mit Kurzhantel", .weightReps, .dumbbell, ["biceps"], ["forearms"]),
        TrainingExercise.builtIn("uni_059_single_arm_hammer_curl", "Single-Arm Hammer Curl", "Einarmiger Hammercurl", .weightReps, .dumbbell, ["biceps"], ["forearms"]),
        TrainingExercise.builtIn("uni_060_single_arm_incline_biceps_curl", "Single-Arm Incline Dumbbell Curl", "Einarmiger Schrägbankcurl mit Kurzhantel", .weightReps, .dumbbell, ["biceps"], ["forearms"]),
        TrainingExercise.builtIn("uni_061_single_arm_preacher_curl", "Single-Arm Dumbbell Preacher Curl", "Einarmiger Scott-Curl mit Kurzhantel", .weightReps, .dumbbell, ["biceps"], ["forearms"]),
        TrainingExercise.builtIn("uni_062_single_arm_cable_biceps_curl", "Single-Arm Cable Biceps Curl", "Einarmiger Bizepscurl am Kabelzug", .weightReps, .cable, ["biceps"], ["forearms"]),
        TrainingExercise.builtIn("uni_063_single_arm_bayesian_curl", "Single-Arm Bayesian Cable Curl", "Einarmiger Bayesian Curl am Kabelzug", .weightReps, .cable, ["biceps"], ["forearms"]),
        TrainingExercise.builtIn("uni_064_single_arm_band_biceps_curl", "Single-Arm Resistance Band Curl", "Einarmiger Bizepscurl mit Widerstandsband", .weightReps, .bands, ["biceps"], ["forearms"]),
        TrainingExercise.builtIn("uni_065_single_arm_kettlebell_curl", "Single-Arm Kettlebell Curl", "Einarmiger Bizepscurl mit Kettlebell", .weightReps, .kettlebell, ["biceps"], ["forearms"]),
        TrainingExercise.builtIn("uni_066_single_arm_cable_triceps_pushdown", "Single-Arm Cable Triceps Pushdown", "Einarmiges Trizepsdrücken am Kabelzug", .weightReps, .cable, ["triceps"], []),
        TrainingExercise.builtIn("uni_067_single_arm_overhead_cable_triceps", "Single-Arm Overhead Cable Triceps Extension", "Einarmiges Überkopf-Trizepsstrecken am Kabelzug", .weightReps, .cable, ["triceps"], []),
        TrainingExercise.builtIn("uni_068_single_arm_dumbbell_overhead_triceps", "Single-Arm Dumbbell Overhead Triceps Extension", "Einarmiges Überkopf-Trizepsstrecken mit Kurzhantel", .weightReps, .dumbbell, ["triceps"], []),
        TrainingExercise.builtIn("uni_069_single_arm_dumbbell_lying_triceps", "Single-Arm Lying Dumbbell Triceps Extension", "Einarmiges Trizepsstrecken liegend mit Kurzhantel", .weightReps, .dumbbell, ["triceps"], []),
        TrainingExercise.builtIn("uni_070_single_arm_cable_triceps_kickback", "Single-Arm Cable Triceps Kickback", "Einarmiger Trizeps-Kickback am Kabelzug", .weightReps, .cable, ["triceps"], []),
        TrainingExercise.builtIn("uni_071_single_arm_dumbbell_wrist_curl", "Single-Arm Dumbbell Wrist Curl", "Einarmiger Handgelenkscurl mit Kurzhantel", .weightReps, .dumbbell, ["forearms"], []),
        TrainingExercise.builtIn("uni_072_single_arm_dumbbell_wrist_extension", "Single-Arm Dumbbell Wrist Extension", "Einarmiges Handgelenkstrecken mit Kurzhantel", .weightReps, .dumbbell, ["forearms"], []),
        TrainingExercise.builtIn("uni_073_single_arm_farmers_walk", "Single-Arm Farmer's Walk", "Einarmiger Farmer's Walk", .duration, .dumbbell, ["forearms", "core"], ["traps"]),
        TrainingExercise.builtIn("uni_074_single_arm_plank", "Single-Arm Plank", "Einarmiger Unterarmstütz", .duration, .bodyweight, ["core"], ["shoulders"])
    ]

    /// The unilateral options need their own cues: using the bilateral cue
    /// alone would omit balance, pelvis position, and switching sides.
    static func guide(for exercise: TrainingExercise, isGerman: Bool) -> String? {
        let cue: (de: String, en: String)
        switch exercise.nameKey {
        case "uni_001_single_leg_press", "uni_002_single_leg_vertical_press":
            cue = ("Setze einen Fuß mittig auf die Druckplatte und halte Becken und Rücken am Polster. Beuge dieses Knie kontrolliert und drücke die Platte über den ganzen Fuß weg, ohne das Knie durchzustoßen. Wechsle danach das Bein.",
                   "Place one foot near the center of the platform and keep your pelvis and back against the pad. Bend that knee under control, then press through the whole foot without snapping the knee straight. Switch legs afterward.")
        case "uni_003_single_leg_hack_squat":
            cue = ("Stelle einen Fuß stabil auf die Hackenschmidt-Platte und halte Schultern und Rücken am Schlitten. Beuge Knie und Hüfte kontrolliert, halte das Knie über dem Fuß und drücke dich wieder hoch. Trainiere beide Beine nacheinander.",
                   "Plant one foot securely on the hack squat platform and keep your shoulders and back against the sled. Bend your knee and hip under control, track the knee over the foot, then press back up. Train both legs in turn.")
        case "uni_004_single_leg_standing_calf_raise", "uni_007_single_leg_donkey_calf_raise", "uni_008_single_leg_heel_raise":
            cue = ("Stelle den Fußballen eines Beins auf die Kante und halte dich für das Gleichgewicht fest. Senke die Ferse langsam ab, drücke dich auf die Zehenspitze und halte kurz oben. Wechsle das Bein nach dem Satz.",
                   "Place the ball of one foot on the edge and hold a support for balance. Lower the heel slowly, rise onto the toes, and pause at the top. Switch legs after the set.")
        case "uni_005_single_leg_seated_calf_raise":
            cue = ("Setze einen Fußballen auf die Trittfläche und fixiere den zugehörigen Oberschenkel unter dem Polster. Senke die Ferse tief und drücke sie dann aus der Wade nach oben; halte das Knie ruhig. Wechsle anschließend die Seite.",
                   "Put one forefoot on the platform and secure that thigh beneath the pad. Lower the heel, then raise it using the calf while keeping the knee still. Switch sides afterward.")
        case "uni_006_single_leg_calf_press":
            cue = ("Stelle nur einen Fußballen auf die Beinpresse und halte das Knie fast gestreckt. Bewege die Platte ausschließlich über das Fußgelenk: Ferse senken, dann die Zehen wegdrücken. Trainiere danach die andere Wade.",
                   "Place only one forefoot on the leg-press platform and keep the knee nearly straight. Move the platform at the ankle only: lower the heel, then press through the toes. Train the other calf afterward.")
        case "uni_009_single_leg_tibialis_raise":
            cue = ("Stehe auf einem Bein und stütze dich bei Bedarf ab. Halte die Ferse am Boden und ziehe die Fußspitze zum Schienbein; senke sie langsam zurück. Wiederhole auf der anderen Seite.",
                   "Stand on one leg and use support if needed. Keep the heel down and pull the toes toward the shin, then lower them slowly. Repeat on the other side.")
        case "uni_010_single_leg_box_squat":
            cue = ("Stehe mit einem Bein vor einer stabilen Box und strecke das freie Bein leicht nach vorn. Schiebe die Hüfte zurück, setze dich kontrolliert auf die Box und stehe über den ganzen Standfuß wieder auf. Wechsle die Seite.",
                   "Stand on one leg in front of a stable box with the free leg slightly forward. Push the hips back, sit onto the box under control, then stand through the whole supporting foot. Switch sides.")
        case "uni_011_single_leg_belt_squat", "uni_012_single_leg_smith_squat":
            cue = ("Stelle einen Fuß stabil unter deinen Körperschwerpunkt und nutze den freien Fuß nur zur Balance. Beuge Hüfte und Knie des Standbeins, halte das Becken gerade und drücke dich über diesen Fuß hoch. Wechsle danach die Seite.",
                   "Plant one foot beneath your center of mass and use the free foot only for balance. Bend the working hip and knee, keep the pelvis level, and drive up through that foot. Switch sides afterward.")
        case "uni_013_single_leg_dumbbell_rdl", "uni_014_single_leg_bodyweight_rdl":
            cue = ("Stehe auf einem leicht gebeugten Bein, schiebe die Hüfte nach hinten und führe das freie Bein nach hinten. Senke den Oberkörper mit geradem Rücken, bis die Beinrückseite spannt; richte dich aus der Hüfte wieder auf. Halte das Becken gerade und wechsle die Seite.",
                   "Stand on a softly bent leg, hinge the hips back, and extend the free leg behind you. Lower the torso with a neutral back until you feel the hamstring stretch, then extend the hip to stand. Keep the pelvis level and switch sides.")
        case "uni_015_single_leg_back_extension":
            cue = ("Fixiere ein Bein an der Rückenstreckerbank und beuge den Oberkörper mit neutralem Rücken aus der Hüfte vor. Richte dich über Gesäß und Beinrückseite des fixierten Beins bis zur geraden Körperlinie auf. Wechsle danach die Seite.",
                   "Secure one leg on the back-extension bench and hinge the torso forward with a neutral spine. Use that leg's glutes and hamstrings to rise until your body is straight. Switch sides afterward.")
        case "uni_016_single_leg_reverse_hyper":
            cue = ("Lege den Oberkörper bäuchlings auf die Bank und halte ein Bein frei. Hebe dieses Bein aus der Hüfte nach hinten, bis es ungefähr mit dem Rumpf fluchtet; senke es ohne Schwung. Wechsle danach das Bein.",
                   "Lie face down with your torso supported and one leg free. Extend that leg back from the hip until it roughly aligns with the trunk, then lower without swinging. Switch legs afterward.")
        case "uni_017_single_leg_ball_curl", "uni_018_single_leg_bodyweight_curl":
            cue = ("Lege eine Ferse auf den Ball oder die vorgesehene Unterlage und hebe das Becken an. Ziehe die Ferse durch Beugen des Knies zum Gesäß, halte die Hüfte oben und strecke das Bein langsam wieder. Wechsle anschließend die Seite.",
                   "Place one heel on the ball or support and lift the hips. Curl the heel toward your glutes by bending the knee, keep the hips raised, then straighten the leg slowly. Switch sides afterward.")
        case "uni_019_single_leg_hip_thrust_machine", "uni_020_single_leg_smith_hip_thrust", "uni_021_single_leg_barbell_hip_thrust", "uni_022_single_leg_banded_glute_bridge":
            cue = ("Stelle einen Fuß fest auf und hebe das andere Bein an. Strecke die Hüfte über die Ferse des Standbeins, bis Rumpf und Oberschenkel eine Linie bilden; halte das Becken waagerecht und senke langsam ab. Wechsle das Bein.",
                   "Plant one foot and lift the other leg. Drive through the supporting heel until your torso and thigh form a line; keep the pelvis level and lower slowly. Switch legs.")
        case "uni_023_single_arm_dumbbell_row", "uni_024_single_arm_chest_supported_row", "uni_025_single_arm_machine_row", "uni_026_single_arm_supported_machine_row", "uni_027_single_arm_band_row":
            cue = ("Stütze den Oberkörper ab oder halte ihn stabil und strecke den Arbeitsarm nach vorn. Ziehe den Ellenbogen Richtung Hüfte, ohne den Rumpf aufzudrehen, und senke den Widerstand langsam. Wechsle danach den Arm.",
                   "Support or brace your torso and reach the working arm forward. Pull the elbow toward the hip without rotating the trunk, then lower the resistance slowly. Switch arms afterward.")
        case "uni_028_single_arm_cable_rear_delt_row", "uni_029_single_arm_dumbbell_rear_delt_row":
            cue = ("Halte den Oberkörper ruhig und ziehe den Ellenbogen seitlich auf Schulterhöhe nach hinten. Bewege die Schulter aus dem oberen Rücken, ohne mit dem Rumpf zu drehen; führe den Arm kontrolliert zurück. Wechsle den Arm.",
                   "Keep the torso still and row the elbow outward at shoulder height. Move from the upper back without twisting the trunk, then return the arm under control. Switch arms.")
        case "uni_030_single_arm_lat_pulldown_machine", "uni_031_single_arm_neutral_lat_pulldown":
            cue = ("Greife den Griff mit einer Hand und halte den Oberkörper aufrecht. Ziehe den Ellenbogen nach unten zur Hüfte, ohne dich zur Seite zu neigen, und lass den Arm langsam wieder lang werden. Wechsle den Arm.",
                   "Hold the handle with one hand and sit or stand tall. Drive the elbow down toward the hip without leaning sideways, then let the arm lengthen slowly. Switch arms.")
        case "uni_032_single_arm_straightarm_pulldown":
            cue = ("Stelle dich stabil vor den Kabelzug und halte den Arbeitsarm fast gestreckt. Ziehe den Griff in einem Bogen von über Schulterhöhe zur Hüfte, ohne den Ellenbogen zu beugen oder den Rumpf zu drehen. Führe den Arm langsam zurück und wechsle die Seite.",
                   "Stand firmly at the cable station with the working arm nearly straight. Sweep the handle from above shoulder height to the hip without bending the elbow or rotating the trunk. Return slowly and switch sides.")
        case "uni_033_single_arm_dumbbell_shrug":
            cue = ("Halte die Kurzhantel mit langem Arm neben dem Körper. Ziehe nur die belastete Schulter gerade nach oben, halte kurz und senke sie vollständig ab; neige den Oberkörper nicht zur Gegenseite. Wechsle den Arm.",
                   "Hold a dumbbell at your side with a long arm. Lift only the loaded shoulder straight up, pause, then lower fully without leaning away. Switch arms.")
        case "uni_034_single_arm_cable_chest_press", "uni_035_single_arm_band_chest_press", "uni_036_single_arm_dumbbell_chest_press", "uni_037_single_arm_dumbbell_floor_press", "uni_038_single_arm_kettlebell_floor_press", "uni_039_single_arm_incline_dumbbell_press":
            cue = ("Richte Griff oder Gewicht auf Brusthöhe aus und spanne den Rumpf gegen Verdrehen an. Drücke mit einem Arm nach vorn oder oben, ohne die Schulter hochzuziehen, und senke kontrolliert zurück. Wechsle danach den Arm.",
                   "Set the handle or load at chest height and brace against rotation. Press with one arm forward or upward without shrugging, then lower under control. Switch arms afterward.")
        case "uni_040_single_arm_dumbbell_fly", "uni_041_single_arm_cable_fly", "uni_042_single_arm_low_high_cable_fly", "uni_043_single_arm_band_chest_fly":
            cue = ("Halte den Arbeitsarm leicht gebeugt und den Rumpf stabil. Führe die Hand in einem weiten Bogen vor die Brust; öffne den Arm langsam bis zu einer angenehmen Brustdehnung, ohne den Ellenbogen zu strecken. Wechsle den Arm.",
                   "Keep the working elbow softly bent and the trunk steady. Sweep the hand in a wide arc in front of the chest, then open slowly to a comfortable chest stretch without straightening the elbow. Switch arms.")
        case "uni_044_single_arm_push_up":
            cue = ("Setze eine Hand unter die Schulter, stelle die Füße für Balance etwas breiter und spanne den ganzen Rumpf an. Senke die Brust kontrolliert zur Hand und drücke dich hoch, ohne Hüfte oder Schultern zu verdrehen. Wechsle den Arm.",
                   "Place one hand below the shoulder, widen the feet for balance, and brace the whole trunk. Lower the chest toward the hand and press up without twisting the hips or shoulders. Switch arms.")
        case "uni_045_single_arm_dumbbell_shoulder_press", "uni_046_single_arm_seated_dumbbell_press", "uni_047_single_arm_kettlebell_press", "uni_048_single_arm_kettlebell_push_press", "uni_049_single_arm_dumbbell_arnold_press":
            cue = ("Halte das Gewicht auf Schulterhöhe und spanne Bauch und Gesäß gegen seitliches Neigen an. Drücke es über den Kopf und senke es kontrolliert bis zur Schulter zurück; nutze nur bei der Push Press einen kurzen Beinantrieb. Wechsle den Arm.",
                   "Hold the load at shoulder height and brace your abs and glutes against side bending. Press overhead and lower to the shoulder under control; use a small leg drive only for the push press. Switch arms.")
        case "uni_050_single_arm_dumbbell_lateral_raise", "uni_051_single_arm_cable_lateral_raise", "uni_052_single_arm_band_lateral_raise":
            cue = ("Halte den Rumpf aufrecht und den Arbeitsarm leicht gebeugt. Hebe den Arm seitlich bis ungefähr auf Schulterhöhe, ohne die Schulter hochzuziehen, und senke langsam ab. Wechsle den Arm.",
                   "Keep the torso upright and the working elbow softly bent. Raise the arm out to about shoulder height without shrugging, then lower slowly. Switch arms.")
        case "uni_053_single_arm_dumbbell_front_raise", "uni_054_single_arm_cable_front_raise":
            cue = ("Halte das Gewicht mit einem fast gestreckten Arm vor dem Körper. Hebe die Hand bis ungefähr auf Schulterhöhe, ohne Schwung oder Hohlkreuz, und senke sie langsam. Wechsle den Arm.",
                   "Hold the load in front of you with a nearly straight arm. Raise the hand to about shoulder height without swinging or arching the back, then lower slowly. Switch arms.")
        case "uni_055_single_arm_reverse_cable_fly", "uni_056_single_arm_reverse_dumbbell_fly":
            cue = ("Halte den Oberkörper ruhig und den Arbeitsarm leicht gebeugt. Führe den Arm seitlich nach hinten, ohne den Rumpf aufzudrehen, und kehre langsam in die Ausgangsposition zurück. Wechsle den Arm.",
                   "Keep the torso still and the working elbow softly bent. Open the arm out and back without twisting the trunk, then return slowly to the start. Switch arms.")
        case "uni_057_single_arm_cable_face_pull":
            cue = ("Stelle das Kabel auf Gesichtshöhe und greife es mit einer Hand. Ziehe den Ellenbogen nach außen hinten und die Hand zum Gesicht, während der Rumpf gerade bleibt; strecke den Arm langsam. Wechsle die Seite.",
                   "Set the cable at face height and grasp it with one hand. Pull the elbow out and back and the hand toward the face while keeping the trunk square; extend slowly. Switch sides.")
        case "uni_058_single_arm_dumbbell_biceps_curl", "uni_059_single_arm_hammer_curl", "uni_060_single_arm_incline_biceps_curl", "uni_061_single_arm_preacher_curl", "uni_062_single_arm_cable_biceps_curl", "uni_063_single_arm_bayesian_curl", "uni_064_single_arm_band_biceps_curl", "uni_065_single_arm_kettlebell_curl":
            cue = ("Halte den Arbeitsoberarm ruhig und beuge nur den Ellenbogen, bis die Hand zur Schulter kommt. Senke das Gewicht langsam bis zur fast gestreckten Position, ohne Schulter oder Oberkörper mitzunehmen. Wechsle den Arm.",
                   "Keep the working upper arm still and bend only the elbow until the hand approaches the shoulder. Lower slowly to a nearly straight arm without moving the shoulder or torso. Switch arms.")
        case "uni_066_single_arm_cable_triceps_pushdown", "uni_067_single_arm_overhead_cable_triceps", "uni_068_single_arm_dumbbell_overhead_triceps", "uni_069_single_arm_dumbbell_lying_triceps", "uni_070_single_arm_cable_triceps_kickback":
            cue = ("Fixiere den Arbeitsoberarm und strecke den Ellenbogen gegen den Widerstand. Beuge ihn anschließend langsam wieder, ohne den Rumpf zu bewegen; bei Überkopfvarianten bleibt der Ellenbogen neben dem Kopf. Wechsle den Arm.",
                   "Keep the working upper arm still and extend the elbow against resistance. Bend it slowly again without moving the torso; for overhead variants, keep the elbow beside the head. Switch arms.")
        case "uni_071_single_arm_dumbbell_wrist_curl":
            cue = ("Lege den Unterarm mit der Handfläche nach oben auf dem Oberschenkel ab und lass das Handgelenk frei. Beuge nur das Handgelenk, um die Hantel anzuheben, und senke sie langsam. Wechsle den Arm.",
                   "Rest the forearm on the thigh with the palm facing up and the wrist free. Flex only the wrist to raise the dumbbell, then lower slowly. Switch arms.")
        case "uni_072_single_arm_dumbbell_wrist_extension":
            cue = ("Lege den Unterarm mit der Handfläche nach unten auf dem Oberschenkel ab und lass das Handgelenk frei. Hebe den Handrücken gegen das Gewicht an und senke ihn langsam; der Unterarm bleibt ruhig. Wechsle den Arm.",
                   "Rest the forearm on the thigh with the palm facing down and the wrist free. Lift the back of the hand against the weight, then lower slowly while keeping the forearm still. Switch arms.")
        case "uni_073_single_arm_farmers_walk":
            cue = ("Trage eine schwere Hantel in einer Hand mit langem Arm. Gehe in ruhigen Schritten aufrecht, halte die Schultern waagerecht und verhindere, dass der Rumpf zur Last kippt. Wechsle die Hand nach der Strecke.",
                   "Carry a heavy dumbbell at one side with a long arm. Walk upright with steady steps, keep the shoulders level, and resist leaning toward the load. Switch hands after the distance.")
        case "uni_074_single_arm_plank":
            cue = ("Beginne im Unterarmstütz und stelle die Füße etwas breiter. Löse einen Unterarm vom Boden und halte Schulter, Becken und Beine möglichst ruhig; setze ihn kontrolliert wieder auf. Wechsle den Arm.",
                   "Start in a forearm plank with the feet somewhat wider. Lift one forearm from the floor while keeping shoulders, pelvis, and legs still, then replace it under control. Switch arms.")
        default:
            return nil
        }
        let detail: (de: String, en: String)?
        switch exercise.nameKey {
        case "uni_002_single_leg_vertical_press":
            detail = ("Bei der vertikalen Beinpresse liegt die Platte über dir; stelle den Fuß so, dass das Knie in Richtung der Zehen zeigt.",
                      "On the vertical leg press the platform is above you; place the foot so the knee tracks toward the toes.")
        case "uni_007_single_leg_donkey_calf_raise":
            detail = ("Beuge den Oberkörper für die Donkey-Variante aus der Hüfte vor und halte den Rücken stabil.",
                      "For the donkey variation, hinge the torso forward at the hips and keep the back stable.")
        case "uni_011_single_leg_belt_squat":
            detail = ("Befestige den Hüftgurt so, dass die Last unter dem Becken hängt und die Hände nur die Balance sichern.",
                      "Attach the hip belt so the load hangs below the pelvis and use your hands only for balance.")
        case "uni_012_single_leg_smith_squat":
            detail = ("Stelle den Standfuß unter die Multipressenstange und entriegle die Stange erst, wenn du stabil stehst.",
                      "Place the supporting foot below the Smith bar and unlock it only once your stance is stable.")
        case "uni_013_single_leg_dumbbell_rdl":
            detail = ("Halte die Kurzhantel nah am Standbein und lass den Arm während des Hüftbeugens lang.",
                      "Keep the dumbbell close to the supporting leg and let the arm hang long throughout the hinge.")
        case "uni_017_single_leg_ball_curl":
            detail = ("Lass den Gymnastikball nur über die arbeitende Ferse rollen und vermeide seitliches Kippen des Beckens.",
                      "Let the stability ball roll beneath the working heel and prevent the pelvis from tipping sideways.")
        case "uni_019_single_leg_hip_thrust_machine":
            detail = ("Richte das Maschinenpolster über der Hüfte aus und halte den oberen Rücken an der Lehne.",
                      "Position the machine pad over the hips and keep the upper back against the support.")
        case "uni_020_single_leg_smith_hip_thrust", "uni_021_single_leg_barbell_hip_thrust":
            detail = ("Lege die Stange gepolstert über die Hüfte und stütze den oberen Rücken an einer stabilen Bank ab.",
                      "Pad the bar across the hips and support the upper back on a stable bench.")
        case "uni_022_single_leg_banded_glute_bridge":
            detail = ("Lege das Band oberhalb der Knie an und halte es während der Hüftstreckung unter Spannung.",
                      "Place the band above the knees and keep it under tension while extending the hip.")
        case "uni_024_single_arm_chest_supported_row", "uni_026_single_arm_supported_machine_row":
            detail = ("Lass die Brust während des gesamten Zuges am Polster, damit der Rumpf nicht mithilft.",
                      "Keep the chest against the pad throughout the pull so the trunk does not assist.")
        case "uni_027_single_arm_band_row":
            detail = ("Verankere das Band auf Höhe des unteren Brustkorbs und prüfe vor dem Ziehen den festen Sitz.",
                      "Anchor the band near lower-chest height and check that it is secure before pulling.")
        case "uni_031_single_arm_neutral_lat_pulldown":
            detail = ("Greife den Einzelgriff im Neutralgriff, sodass die Handfläche nach innen zeigt.",
                      "Use a neutral grip on the single handle with the palm facing inward.")
        case "uni_037_single_arm_dumbbell_floor_press", "uni_038_single_arm_kettlebell_floor_press":
            detail = ("Lege dich auf den Boden und stoppe das Absenken, sobald der Oberarm den Boden berührt.",
                      "Lie on the floor and stop lowering when the upper arm touches it.")
        case "uni_039_single_arm_incline_dumbbell_press":
            detail = ("Stelle die Bank moderat schräg und halte den oberen Rücken beim Drücken an der Lehne.",
                      "Set the bench at a moderate incline and keep the upper back against it while pressing.")
        case "uni_042_single_arm_low_high_cable_fly":
            detail = ("Stelle die Kabelrolle tief ein und führe die Hand diagonal von der Hüfte zur gegenüberliegenden oberen Brust.",
                      "Set the cable low and sweep the hand diagonally from the hip toward the opposite upper chest.")
        case "uni_043_single_arm_band_chest_fly":
            detail = ("Befestige das Band seitlich auf Brusthöhe und halte während des Öffnens durchgehend Spannung.",
                      "Anchor the band beside you at chest height and keep tension through the opening phase.")
        case "uni_048_single_arm_kettlebell_push_press":
            detail = ("Beuge die Knie kurz und strecke Beine und Hüfte explosiv, bevor der Arm die Kettlebell über Kopf drückt.",
                      "Dip the knees briefly, then extend the legs and hips sharply before the arm finishes pressing the kettlebell overhead.")
        case "uni_049_single_arm_dumbbell_arnold_press":
            detail = ("Starte mit der Handfläche zum Körper und drehe sie beim Hochdrücken kontrolliert nach vorn.",
                      "Start with the palm facing your body and rotate it forward as you press overhead.")
        case "uni_059_single_arm_hammer_curl":
            detail = ("Halte die Handfläche während des gesamten Hammercurls nach innen gerichtet.",
                      "Keep the palm facing inward throughout the hammer curl.")
        case "uni_060_single_arm_incline_biceps_curl":
            detail = ("Lehne dich an die Schrägbank und lass den Oberarm hinter dem Rumpf hängen.",
                      "Lean against the incline bench and let the upper arm hang behind the torso.")
        case "uni_061_single_arm_preacher_curl":
            detail = ("Lege den Oberarm fest auf das Scott-Polster und halte die Schulter während des Curls ruhig.",
                      "Rest the upper arm firmly on the preacher pad and keep the shoulder still during the curl.")
        case "uni_063_single_arm_bayesian_curl":
            detail = ("Stelle dich mit dem Rücken zur tiefen Kabelrolle, sodass der Arbeitsarm hinter dem Rumpf startet.",
                      "Stand facing away from the low cable so the working arm starts behind the torso.")
        case "uni_067_single_arm_overhead_cable_triceps", "uni_068_single_arm_dumbbell_overhead_triceps":
            detail = ("Halte den Ellenbogen neben dem Kopf und senke die Hand hinter den Kopf, bevor du den Arm streckst.",
                      "Keep the elbow beside the head and lower the hand behind it before extending the arm.")
        case "uni_069_single_arm_dumbbell_lying_triceps":
            detail = ("Lege dich auf eine Bank und senke die Hantel durch Ellenbogenbeugung neben die Stirn.",
                      "Lie on a bench and bend the elbow to lower the dumbbell beside the forehead.")
        case "uni_070_single_arm_cable_triceps_kickback":
            detail = ("Beuge dich aus der Hüfte vor und halte den Oberarm parallel zum Oberkörper, während du den Ellenbogen streckst.",
                      "Hinge at the hips and hold the upper arm beside the torso while extending the elbow.")
        default:
            detail = nil
        }
        let movement = isGerman ? cue.de : cue.en
        guard let detail else { return movement }
        return "\(isGerman ? detail.de : detail.en) \(movement)"
    }
}
