# Read all pieces of the training UI for source-level regression checks.
module TrainingViewSources
  def self.read(root = File.expand_path('..', __dir__))
    app = File.join(root, 'CalorieTrackerApp')
    source = %w[TrainingViews.swift TrainingExerciseRoutineViews.swift TrainingHistoryHealthViews.swift]
      .map { |file| File.read(File.join(app, file)) }.join("\n")
    active = File.read(File.join(app, 'ActiveWorkoutViews.swift'))
    share_anchor = 'private struct WorkoutConfettiView: View {'
    active = active.sub(share_anchor, File.read(File.join(app, 'WorkoutShareViews.swift')) + "\n" + share_anchor)
    active += File.read(File.join(app, 'TrainingSetViews.swift'))
    {
      'private struct TrainingSectionBar: View {' => 'TrainingCommunityViews.swift',
      'struct BodyMeasurementHistoryView: View {' => 'TrainingSocialViews.swift'
    }.each do |anchor, file|
      source = source.sub(anchor, File.read(File.join(app, file)) + "\n" + anchor)
    end
    source.sub('struct ExerciseLibraryView: View {', active + "\nstruct ExerciseLibraryView: View {")
  end
end
