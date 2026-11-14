import Foundation

extension TrainingExercise {
    /// Short, exercise-specific setup and movement cues. The wording is kept
    /// compact enough for the progress sheet while still describing the actual
    /// exercise instead of only its broad movement category.
    func executionGuide(isGerman: Bool) -> String {
        if isCustom,
           let catalogExercise = Self.matchingBuiltIn(named: englishName) ?? Self.matchingBuiltIn(named: germanName) {
            return catalogExercise.executionGuide(isGerman: isGerman)
        }
        if let guide = UnilateralExerciseDirectory.guide(for: self, isGerman: isGerman) {
            return guide
        }
        if nameKey.hasPrefix("sl_"), let guide = StrengthLogDirectory.guide(for: self, isGerman: isGerman) {
            return guide
        }
        let guide: (de: String, en: String)

        switch nameKey {
        case "barbell_bench_press", "smith_flat_bench_press":
            guide = (
                "Lege die Füße fest auf, ziehe die Schulterblätter nach hinten unten und senke die Stange kontrolliert zur mittleren Brust. Drücke sie über den Unterarmen wieder nach oben.",
                "Plant your feet, pull your shoulder blades back and down, and lower the bar to mid-chest under control. Press it back up over your forearms."
            )
        case "incline_barbell_press", "incline_dumbbell_press", "smith_incline_press":
            guide = (
                "Stelle die Bank moderat schräg, halte Schulterblätter und Füße stabil und senke das Gewicht zur oberen Brust. Drücke kontrolliert nach oben, ohne die Schultern hochzuziehen.",
                "Set a moderate bench incline, keep your shoulder blades and feet stable, and lower the load toward the upper chest. Press up without shrugging."
            )
        case "decline_barbell_press":
            guide = (
                "Sichere die Beine, ziehe die Schulterblätter zurück und senke die Stange kontrolliert zur unteren Brust. Drücke sie auf derselben Bahn wieder hoch.",
                "Secure your legs, retract your shoulder blades, and lower the bar toward the lower chest. Press it back up along the same path."
            )
        case "closegrip_bench_press":
            guide = (
                "Greife etwa schulterbreit, halte die Ellenbogen näher am Körper und senke die Stange zur unteren Brust. Drücke sie aus dem Trizeps kontrolliert hoch.",
                "Use about a shoulder-width grip, keep your elbows closer to your sides, and lower the bar to the lower chest. Press up under control through the triceps."
            )
        case "machine_chest_press", "band_chest_press":
            guide = (
                "Richte die Griffe auf Brusthöhe aus, halte Rücken und Schulterblätter stabil und drücke nach vorn. Führe die Hände langsam zurück, bis die Brust angenehm gedehnt ist.",
                "Align the handles with your chest, keep your back and shoulder blades stable, and press forward. Return slowly until the chest is comfortably stretched."
            )
        case "push_up":
            guide = (
                "Halte Kopf, Rumpf und Beine in einer Linie und senke die Brust zwischen die Hände. Drücke den Boden weg, ohne Hüfte oder unteren Rücken absinken zu lassen.",
                "Keep your head, trunk, and legs in one line and lower your chest between your hands. Push the floor away without letting your hips or lower back sag."
            )
        case "pike_push_up":
            guide = (
                "Schiebe die Hüfte hoch, halte den Rücken lang und senke den Kopf kontrolliert zwischen die Hände. Drücke dich über die Schultern zurück in die Ausgangsposition.",
                "Lift your hips, keep your back long, and lower your head between your hands under control. Press through your shoulders to return."
            )
        case "bodyweight_dip", "weighted_dip", "assisted_chest_dip":
            guide = (
                "Stütze dich mit tiefen Schultern ab, neige den Oberkörper leicht vor und senke dich kontrolliert. Drücke dich hoch, sobald die Brust angenehm gedehnt ist.",
                "Support yourself with your shoulders down, lean slightly forward, and lower under control. Press up once you feel a comfortable chest stretch."
            )
        case "triceps_dip", "weighted_triceps_dip", "assisted_triceps_dip", "seated_dip_machine":
            guide = (
                "Halte den Oberkörper möglichst aufrecht und die Ellenbogen nah am Körper. Beuge die Arme kontrolliert und drücke die Griffe anschließend vollständig nach unten.",
                "Keep your torso mostly upright and your elbows close to your sides. Bend your arms under control, then press the handles fully down."
            )
        case "dumbbell_chest_fly", "band_chest_fly":
            guide = (
                "Halte die Ellenbogen leicht gebeugt und öffne die Arme in einem weiten Bogen, bis die Brust angenehm gedehnt ist. Führe die Hände auf derselben Bahn zusammen.",
                "Keep a slight bend in your elbows and open your arms in a wide arc to a comfortable chest stretch. Bring your hands together along the same path."
            )
        case "chest_fly_machine":
            guide = (
                "Lehne den Rücken an, halte die Brust geöffnet und führe die Polster oder Griffe in einem Bogen zusammen. Kehre langsam zurück, ohne die Schultern nach vorn rollen zu lassen.",
                "Keep your back supported and chest open as you bring the pads or handles together in an arc. Return slowly without rolling your shoulders forward."
            )
        case "cable_crossover", "cable_fly_low_high":
            guide = (
                "Stehe versetzt und stabil, halte die Arme leicht gebeugt und führe die Kabel in einem Bogen vor dem Körper zusammen. Kontrolliere den Rückweg ohne Schultervorschub.",
                "Use a stable split stance, keep your arms slightly bent, and sweep the cables together in front of you. Control the return without pushing your shoulders forward."
            )
        case "overhead_press", "dumbbell_shoulder_press", "machine_shoulder_press":
            guide = (
                "Spanne Bauch und Gesäß an, halte die Rippen unten und drücke das Gewicht über den Kopf. Senke es kontrolliert bis etwa auf Schulterhöhe zurück.",
                "Brace your abs and glutes, keep your ribs down, and press the load overhead. Lower it under control to about shoulder height."
            )
        case "arnold_shoulder_press":
            guide = (
                "Beginne mit den Handflächen zum Körper und drehe sie beim Hochdrücken kontrolliert nach vorn. Kehre die Bewegung beim Absenken langsam um.",
                "Start with your palms facing you and rotate them forward as you press overhead. Reverse the motion slowly on the way down."
            )
        case "lateral_raise", "band_lateral_raise", "cable_lateral_raise", "single_arm_cable_lateral_raise":
            guide = (
                "Hebe die leicht gebeugten Arme seitlich bis ungefähr auf Schulterhöhe. Halte die Schultern tief und senke den Widerstand langsam ohne Schwung.",
                "Raise your slightly bent arms out to about shoulder height. Keep your shoulders down and lower the resistance slowly without swinging."
            )
        case "cable_front_raise":
            guide = (
                "Hebe den fast gestreckten Arm vor dem Körper bis etwa auf Schulterhöhe. Halte Rumpf und Schulter ruhig und senke das Kabel kontrolliert ab.",
                "Raise the nearly straight arm in front of you to about shoulder height. Keep your torso and shoulder still and lower the cable under control."
            )
        case "chest_supported_y_raise":
            guide = (
                "Lehne die Brust an die Bank und hebe die Arme schräg nach vorn zu einem Y. Ziehe die Schultern nicht hoch und senke langsam ab.",
                "Support your chest on the bench and raise your arms diagonally into a Y. Avoid shrugging and lower slowly."
            )
        case "band_face_pull", "cable_face_pull":
            guide = (
                "Ziehe Band oder Seil auf Gesichtshöhe, führe die Ellenbogen nach außen und die Hände auseinander. Kehre mit tiefen Schultern kontrolliert zurück.",
                "Pull the band or rope toward face height, driving your elbows out and separating your hands. Return under control with your shoulders down."
            )
        case "reverse_pecdeck_fly", "single_arm_reverse_cable_fly":
            guide = (
                "Halte die Brust stabil und führe den Arm seitlich nach hinten, ohne den Oberkörper zu drehen. Kehre langsam zurück und halte die Schulter tief.",
                "Keep your chest stable and move the arm out and back without rotating your torso. Return slowly while keeping the shoulder down."
            )
        case "upright_barbell_row":
            guide = (
                "Ziehe die Stange dicht am Körper nach oben und führe die Ellenbogen seitlich. Stoppe in einem schmerzfreien Bereich und senke langsam ab.",
                "Pull the bar upward close to your body, leading with your elbows. Stop within a pain-free range and lower slowly."
            )
        case "barbell_shrug", "machine_shrug", "kelso_shrug":
            guide = (
                "Hebe beziehungsweise ziehe die Schulterblätter kontrolliert in die vorgesehene Richtung und halte kurz. Senke sie vollständig ab, ohne mit Kopf oder Armen Schwung zu holen.",
                "Raise or retract your shoulder blades in the intended direction and pause briefly. Lower fully without using your head or arms for momentum."
            )
        case "barbell_row":
            guide = (
                "Beuge dich aus der Hüfte vor, halte den Rücken neutral und ziehe die Stange zum Bauch. Führe die Ellenbogen zurück und senke die Stange kontrolliert.",
                "Hinge forward with a neutral back and pull the bar toward your abdomen. Drive your elbows back and lower the bar under control."
            )
        case "dumbbell_row", "kettlebell_row":
            guide = (
                "Stütze dich stabil ab, halte den Rücken neutral und ziehe das Gewicht mit dem Ellenbogen Richtung Hüfte. Senke es, bis der Arm wieder lang ist.",
                "Brace yourself with a neutral back and pull the load by driving your elbow toward your hip. Lower until your arm is long again."
            )
        case "tbar_supported_row", "supported_chest_row", "iso_lateral_high_row":
            guide = (
                "Lass die Brust am Polster und ziehe die Griffe über die Ellenbogen nach hinten. Führe sie langsam vor, ohne den Oberkörper anzuheben.",
                "Keep your chest on the pad and pull the handles back by driving your elbows. Return slowly without lifting your torso."
            )
        case "seated_cable_row", "seated_machine_row":
            guide = (
                "Sitze aufrecht mit stabilem Rumpf und ziehe den Griff zum unteren Brustkorb oder Bauch. Strecke die Arme kontrolliert, ohne weit vor- oder zurückzulehnen.",
                "Sit tall with a braced trunk and pull the handle toward your lower ribs or abdomen. Extend your arms without excessive forward or backward lean."
            )
        case "onearm_cable_row":
            guide = (
                "Stehe oder sitze stabil und ziehe den Ellenbogen zur Hüfte, ohne den Oberkörper aufzudrehen. Strecke den Arm anschließend kontrolliert nach vorn.",
                "Stay stable and pull your elbow toward your hip without rotating your torso. Then extend the arm forward under control."
            )
        case "band_row":
            guide = (
                "Fixiere das Band sicher, halte den Rumpf aufrecht und ziehe die Ellenbogen nach hinten. Löse die Spannung langsam, ohne die Schultern nach vorn fallen zu lassen.",
                "Anchor the band securely, keep your torso upright, and drive your elbows back. Release the tension slowly without letting your shoulders collapse forward."
            )
        case "pull_up", "chinup_supinated", "weighted_pull_up", "assisted_pullup_machine":
            guide = (
                "Beginne mit langen Armen und aktiven Schultern, ziehe die Ellenbogen nach unten und bringe die Brust zur Stange. Senke dich kontrolliert bis zur Ausgangsposition.",
                "Start with long arms and active shoulders, drive your elbows down, and bring your chest toward the bar. Lower under control to the start."
            )
        case "lat_pulldown", "onearm_lat_pulldown", "close_grip_lat_pulldown", "machine_lat_pulldown":
            guide = (
                "Halte den Oberkörper ruhig und ziehe den Griff über die Ellenbogen zur oberen Brust beziehungsweise zur Seite. Lass die Arme kontrolliert wieder lang werden.",
                "Keep your torso steady and pull the handle toward your upper chest or side by driving the elbows down. Let your arms lengthen under control."
            )
        case "straightarm_pulldown", "dumbbell_pullover":
            guide = (
                "Halte die Arme fast gestreckt und die Rippen unten, während du den Widerstand in einem langen Bogen Richtung Hüfte führst. Kehre langsam in die Dehnung zurück.",
                "Keep your arms nearly straight and ribs down as you sweep the resistance toward your hips. Return slowly into the stretch."
            )
        case "barbell_back_squat", "smith_squat_machine":
            guide = (
                "Stelle die Füße stabil, spanne den Rumpf an und senke Hüfte und Knie gemeinsam ab. Drücke dich über den ganzen Fuß hoch, während die Knie den Fußspitzen folgen.",
                "Set your feet firmly, brace your trunk, and bend your hips and knees together. Drive through the whole foot while your knees track with your toes."
            )
        case "bodyweight_squat", "band_squat", "goblet_squat", "kettlebell_goblet":
            guide = (
                "Halte den Rumpf stabil und setze dich kontrolliert zwischen die Hüften. Die Knie folgen den Fußspitzen; stehe über den ganzen Fuß wieder auf.",
                "Brace your trunk and sit down between your hips under control. Let your knees track with your toes and stand through the whole foot."
            )
        case "hack_squat_machine", "pendulum_squat_machine", "leg_press":
            guide = (
                "Stelle die Füße stabil auf die Platte und senke den Schlitten so weit ab, wie Rücken und Becken am Polster bleiben. Drücke über den ganzen Fuß zurück.",
                "Plant your feet on the platform and lower as far as your back and pelvis stay supported. Press back through the whole foot."
            )
        case "reverse_lunge", "walking_dumbbell_lunge":
            guide = (
                "Setze einen ausreichend langen Schritt und senke das hintere Knie kontrolliert Richtung Boden. Drücke dich über den ganzen vorderen Fuß in den Stand.",
                "Take a long enough step and lower your rear knee toward the floor under control. Drive through the whole front foot to stand."
            )
        case "bulgarian_split_squat":
            guide = (
                "Lege den hinteren Fuß erhöht ab und platziere den vorderen Fuß so, dass du stabil absenken kannst. Drücke dich über den vorderen Fuß wieder hoch.",
                "Rest your rear foot on a bench and place the front foot far enough forward for a stable descent. Drive back up through the front foot."
            )
        case "conventional_deadlift":
            guide = (
                "Stelle die Stange über den Mittelfuß, spanne Rumpf und Latissimus an und drücke den Boden weg. Strecke Hüfte und Knie gemeinsam und senke die Stange dicht am Körper ab.",
                "Set the bar over mid-foot, brace your trunk and lats, and push the floor away. Extend hips and knees together, then lower the bar close to your body."
            )
        case "romanian_deadlift", "dumbbell_rdl", "band_rdl":
            guide = (
                "Beuge die Knie leicht und schiebe die Hüfte mit neutralem Rücken weit nach hinten. Kehre um, sobald die Beinrückseite deutlich spannt, und strecke die Hüfte.",
                "Soften your knees and push your hips far back with a neutral spine. Reverse once you feel a strong hamstring stretch and extend your hips."
            )
        case "goodmorning_barbell":
            guide = (
                "Fixiere die Stange am oberen Rücken, beuge die Knie leicht und schiebe die Hüfte nach hinten. Halte den Rücken neutral und richte dich über die Hüfte wieder auf.",
                "Secure the bar on your upper back, soften your knees, and push your hips back. Keep a neutral spine and stand by extending your hips."
            )
        case "hip_thrust", "machine_hip_thrust", "glute_bridge":
            guide = (
                "Spanne den Bauch an und strecke die Hüfte, bis Oberkörper und Oberschenkel eine Linie bilden. Drücke aus dem Gesäß, ohne den unteren Rücken zu überstrecken.",
                "Brace your abs and extend your hips until your torso and thighs form a line. Squeeze your glutes without overextending your lower back."
            )
        case "leg_extension", "single_leg_extension":
            guide = (
                "Richte Kniegelenk und Drehachse der Maschine aus und strecke das Bein kontrolliert. Senke das Polster langsam ab, ohne die Hüfte vom Sitz zu lösen.",
                "Align your knee with the machine pivot and extend the leg under control. Lower the pad slowly without lifting your hips from the seat."
            )
        case "seated_hamstring_curl", "lying_hamstring_curl", "standing_hamstring_curl":
            guide = (
                "Richte die Knie an der Maschinenachse aus und halte Hüfte und Oberschenkel am Polster. Ziehe die Fersen kontrolliert heran und strecke die Beine langsam.",
                "Align your knees with the machine pivot and keep your hips and thighs supported. Curl your heels in, then extend your legs slowly."
            )
        case "nordic_hamstring_curl":
            guide = (
                "Fixiere die Fersen, halte Hüfte und Rumpf in einer Linie und neige den Körper langsam nach vorn. Fange dich mit den Händen ab und ziehe dich aus den Beinbeugern zurück.",
                "Anchor your heels, keep hips and trunk aligned, and lean forward slowly. Catch yourself with your hands and pull back using your hamstrings."
            )
        case "hip_abduction_machine":
            guide = (
                "Lehne Becken und Rücken stabil an und drücke die Knie kontrolliert nach außen. Kehre langsam zurück, ohne die Gewichte absetzen zu lassen.",
                "Keep your pelvis and back supported and press your knees outward under control. Return slowly without letting the stack rest."
            )
        case "hip_adduction_machine":
            guide = (
                "Lehne Becken und Rücken stabil an und führe die Knie kontrolliert zusammen. Öffne die Beine anschließend langsam bis zu einer angenehmen Dehnung.",
                "Keep your pelvis and back supported and bring your knees together under control. Open slowly to a comfortable stretch."
            )
        case "cable_glute_kickback":
            guide = (
                "Halte dich stabil fest und führe das Bein mit leicht gebeugtem Knie nach hinten. Strecke aus der Hüfte, ohne Becken oder unteren Rücken mitzudrehen.",
                "Brace yourself and drive the leg back with a slight bend in the knee. Extend from the hip without rotating your pelvis or lower back."
            )
        case "standing_calf_raise", "seated_calf_machine", "donkey_calf_raise", "machine_calf_press":
            guide = (
                "Senke die Fersen kontrolliert in die Dehnung und drücke dich anschließend so hoch wie möglich auf die Fußballen. Vermeide Wippen und halte oben kurz.",
                "Lower your heels into a controlled stretch, then rise as high as possible onto the balls of your feet. Avoid bouncing and pause briefly at the top."
            )
        case "biceps_curl", "ezbar_biceps_curl", "cable_biceps_curl":
            guide = (
                "Halte die Oberarme am Körper und beuge nur die Ellenbogen, bis die Unterarme oben sind. Senke den Widerstand langsam bis fast zur vollständigen Streckung.",
                "Keep your upper arms by your sides and bend only at the elbows. Lower the resistance slowly to near full extension."
            )
        case "hammer_curl", "cable_hammer_curl":
            guide = (
                "Halte die Handflächen zueinander und die Oberarme ruhig. Beuge die Ellenbogen ohne Schwung und senke das Gewicht kontrolliert ab.",
                "Keep your palms facing each other and your upper arms still. Curl without swinging and lower the load under control."
            )
        case "preacher_biceps_curl", "dumbbell_preacher_curl", "machine_preacher_curl":
            guide = (
                "Lege die Oberarme vollständig auf das Polster und beuge die Ellenbogen ohne die Schultern anzuheben. Senke das Gewicht langsam bis kurz vor die volle Streckung.",
                "Keep your upper arms fully supported on the pad and curl without lifting your shoulders. Lower slowly to just short of full extension."
            )
        case "incline_db_biceps_curl", "bayesian_cable_curl":
            guide = (
                "Halte den Oberarm leicht hinter dem Körper und die Schulter ruhig. Beuge den Ellenbogen kontrolliert und kehre langsam in die gedehnte Position zurück.",
                "Keep your upper arm slightly behind your body and your shoulder still. Curl under control and return slowly to the stretched position."
            )
        case "concentration_curl":
            guide = (
                "Stütze den Oberarm an der Innenseite des Oberschenkels ab und beuge nur den Ellenbogen. Senke die Hantel langsam, ohne Schulter oder Oberkörper zu bewegen.",
                "Brace your upper arm against your inner thigh and bend only the elbow. Lower the dumbbell slowly without moving your shoulder or torso."
            )
        case "reverse_barbell_curl", "reverse_cable_curl":
            guide = (
                "Greife im Obergriff, halte die Handgelenke neutral und die Oberarme am Körper. Beuge die Ellenbogen kontrolliert und senke langsam ab.",
                "Use an overhand grip, keep your wrists neutral and upper arms by your sides. Curl under control and lower slowly."
            )
        case "zottman_curl":
            guide = (
                "Curle die Hanteln im Untergriff nach oben, drehe oben in den Obergriff und senke langsam ab. Drehe unten zurück, ohne die Oberarme zu bewegen.",
                "Curl the dumbbells up with palms forward, rotate to an overhand grip at the top, and lower slowly. Rotate back at the bottom without moving your upper arms."
            )
        case "wrist_roller":
            guide = (
                "Halte die Arme ruhig und rolle das Gewicht nur durch abwechselnde Bewegungen der Handgelenke auf. Lasse es anschließend ebenso kontrolliert wieder ab.",
                "Keep your arms still and wind the weight up using alternating wrist movements only. Unwind it with the same control."
            )
        case "triceps_pushdown", "rope_triceps_pushdown", "rope_triceps_pressdown":
            guide = (
                "Halte die Ellenbogen fest an den Seiten und drücke den Griff bis zur Armstreckung nach unten. Führe ihn kontrolliert zurück, ohne die Oberarme anzuheben.",
                "Pin your elbows to your sides and press the handle down until your arms are extended. Return under control without lifting your upper arms."
            )
        case "overhead_cable_triceps", "overhead_triceps_extension", "skullcrusher_ezbar":
            guide = (
                "Halte die Oberarme ruhig und beuge die Ellenbogen, bis der Trizeps deutlich gedehnt ist. Strecke die Arme kontrolliert, ohne die Schultern mitzubewegen.",
                "Keep your upper arms still and bend your elbows to a clear triceps stretch. Extend under control without moving your shoulders."
            )
        case "cable_triceps_kickback":
            guide = (
                "Beuge dich leicht vor, fixiere den Oberarm am Körper und strecke den Ellenbogen nach hinten. Kehre langsam zurück, ohne die Schulter zu bewegen.",
                "Lean forward slightly, pin your upper arm to your side, and extend the elbow behind you. Return slowly without moving the shoulder."
            )
        case "plank":
            guide = (
                "Stütze dich unter den Schultern ab, spanne Bauch und Gesäß an und halte Kopf bis Fersen in einer Linie. Atme weiter, ohne die Hüfte absinken zu lassen.",
                "Support yourself beneath your shoulders, brace your abs and glutes, and keep head to heels in one line. Keep breathing without letting your hips sag."
            )
        case "mountain_climber":
            guide = (
                "Beginne im hohen Stütz und führe die Knie abwechselnd Richtung Brust. Halte Schultern über den Händen und Becken sowie Rücken möglichst ruhig.",
                "Start in a high plank and drive your knees toward your chest in turn. Keep your shoulders over your hands and your pelvis and back steady."
            )
        case "cable_ab_crunch", "machine_ab_crunch":
            guide = (
                "Fixiere Hüfte und Becken und rolle Rippen und Brustbein kontrolliert Richtung Becken. Kehre langsam zurück, ohne nur aus der Hüfte zu arbeiten.",
                "Keep your hips and pelvis fixed and curl your ribs and sternum toward your pelvis. Return slowly without turning the movement into a hip hinge."
            )
        case "hanging_leg_raise", "captains_chair_leg_raise":
            guide = (
                "Stabilisiere die Schultern und hebe die gestreckten oder leicht gebeugten Beine aus dem Becken an. Senke sie ohne Schwung und ohne starkes Hohlkreuz.",
                "Set your shoulders and lift your straight or slightly bent legs by curling the pelvis. Lower without swinging or arching your lower back."
            )
        case "captains_chair_knee_raise":
            guide = (
                "Drücke Rücken und Unterarme stabil an die Polster und ziehe die Knie über eine Beckenkippung zur Brust. Senke sie langsam ohne Schwung.",
                "Keep your back and forearms firmly supported and draw your knees toward your chest by curling your pelvis. Lower slowly without swinging."
            )
        case "abwheel_rollout":
            guide = (
                "Spanne Bauch und Gesäß an und rolle mit stabilem Rücken nur so weit vor, wie du die Position halten kannst. Ziehe das Rad aus dem Rumpf zurück.",
                "Brace your abs and glutes and roll forward only as far as you can keep a stable back. Pull the wheel back using your trunk."
            )
        case "l_sit_hold":
            guide = (
                "Drücke die Schultern aktiv nach unten, strecke die Arme und hebe die Beine vor dem Körper an. Halte Bauch und Oberschenkel angespannt, ohne einzusinken.",
                "Press your shoulders actively down, straighten your arms, and lift your legs in front of you. Brace your abs and thighs without sinking."
            )
        case "cable_woodchop_high_low":
            guide = (
                "Stehe stabil seitlich zum Kabel und führe den Griff diagonal von oben nach unten. Drehe kontrolliert aus Brustkorb und Hüfte, ohne an den Armen zu reißen.",
                "Stand side-on to the cable and guide the handle diagonally from high to low. Rotate through your torso and hips without yanking with your arms."
            )
        case "back_extension_45deg", "machine_back_extension":
            guide = (
                "Beuge dich kontrolliert aus der Hüfte vor und halte die Wirbelsäule neutral. Richte dich bis zur geraden Körperlinie auf, ohne den unteren Rücken zu überstrecken.",
                "Hinge forward at the hips with a neutral spine. Rise to a straight body line without overextending your lower back."
            )
        case "lying_neck_curl":
            guide = (
                "Lege den Kopf frei auf die Bank und ziehe das Kinn leicht ein. Beuge den Hals langsam nach vorn und senke den Kopf kontrolliert zurück.",
                "Let your head extend beyond the bench and tuck your chin slightly. Curl your neck forward slowly, then lower your head under control."
            )
        case "lying_neck_extension":
            guide = (
                "Lege den Kopf frei auf die Bank und halte das Kinn leicht eingezogen. Hebe den Kopf kontrolliert bis zur neutralen Halsposition und senke langsam ab.",
                "Let your head extend beyond the bench with your chin slightly tucked. Raise to a neutral neck position and lower slowly."
            )
        case "tibialis_raise":
            guide = (
                "Lehne dich stabil an und lasse die Fersen am Boden. Ziehe die Fußspitzen so hoch wie möglich an und senke sie kontrolliert ab.",
                "Lean against a stable support and keep your heels on the floor. Lift your toes as high as possible and lower them under control."
            )
        case "kettlebell_swing":
            guide = (
                "Schwinge die Kettlebell zwischen die Beine und strecke die Hüfte explosiv nach vorn. Die Arme führen nur; kontrolliere den Rückweg mit neutralem Rücken.",
                "Hike the kettlebell between your legs and extend your hips explosively. Let your arms guide it and control the return with a neutral spine."
            )
        case "kettlebell_press":
            guide = (
                "Setze die Kettlebell kontrolliert in der Rack-Position ab und drücke sie mit stabilem Rumpf über den Kopf. Senke sie über Schulter und Ellenbogen zurück.",
                "Settle the kettlebell in the rack position and press it overhead with a braced trunk. Lower it back through the shoulder and elbow."
            )
        case "treadmill_run", "outdoor_run", "jogging":
            guide = (
                "Laufe aufrecht mit lockerem Oberkörper und kurzen, leisen Schritten unter deinem Körperschwerpunkt. Steigere Tempo oder Dauer nur schrittweise.",
                "Run tall with a relaxed upper body and short, quiet steps beneath your center of mass. Increase pace or duration gradually."
            )
        case "stationary_bike", "cycling":
            guide = (
                "Stelle den Sattel so ein, dass das Knie am tiefsten Pedalpunkt leicht gebeugt bleibt. Tritt gleichmäßig und halte Hüfte sowie Oberkörper ruhig.",
                "Set the saddle so your knee remains slightly bent at the bottom of the stroke. Pedal smoothly while keeping your hips and torso steady."
            )
        case "rowing_ergometer":
            guide = (
                "Drücke zuerst mit den Beinen, öffne dann die Hüfte und ziehe zuletzt den Griff zu den unteren Rippen. Auf dem Rückweg folgen Arme, Oberkörper und dann die Knie.",
                "Drive with the legs first, open the hips, then pull the handle to the lower ribs. On recovery, move arms, torso, and then knees."
            )
        case "jump_rope":
            guide = (
                "Drehe das Seil aus den Handgelenken und springe nur wenige Zentimeter aus den Fußgelenken. Lande weich und halte Schultern sowie Ellenbogen locker.",
                "Turn the rope from your wrists and make small ankle-driven jumps. Land softly and keep your shoulders and elbows relaxed."
            )
        case "elliptical_trainer":
            guide = (
                "Stehe aufrecht und führe die Pedale in einem gleichmäßigen Rhythmus. Halte die Knie in Richtung der Fußspitzen und vermeide starkes Abstützen auf den Griffen.",
                "Stand tall and move the pedals in a smooth rhythm. Track your knees with your toes and avoid leaning heavily on the handles."
            )
        case "stairclimber_cardio":
            guide = (
                "Setze den ganzen Fuß auf die Stufe und steige in gleichmäßigem Rhythmus. Bleibe aufrecht und nutze die Griffe nur leicht zur Balance.",
                "Place your whole foot on each step and climb at a steady rhythm. Stay upright and use the handles lightly for balance."
            )
        case "airbike_cardio":
            guide = (
                "Stelle den Sitz passend ein und drücke und ziehe die Griffe im Rhythmus mit den Pedalen. Halte den Rumpf ruhig und verteile die Arbeit auf Arme und Beine.",
                "Adjust the seat and push and pull the handles in rhythm with the pedals. Keep your trunk steady and share the work between arms and legs."
            )
        case "stretching":
            guide = (
                "Bewege dich langsam bis zu einer deutlichen, aber angenehmen Spannung. Halte die Position ruhig, atme weiter und vermeide federnde Bewegungen.",
                "Move slowly into a clear but comfortable stretch. Hold steadily, keep breathing, and avoid bouncing."
            )
        default:
            guide = (
                "Richte dich stabil ein und führe jede Wiederholung langsam über einen schmerzfreien Bewegungsumfang aus. Vermeide Schwung und stoppe, wenn die Technik nachlässt.",
                "Set up in a stable position and perform each repetition slowly through a pain-free range. Avoid momentum and stop when your technique breaks down."
            )
        }

        return isGerman ? guide.de : guide.en
    }
}
