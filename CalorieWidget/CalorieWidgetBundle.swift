import WidgetKit
import SwiftUI

@main
struct CalorieWidgetBundle: WidgetBundle {
    var body: some Widget {
        CalorieWidget()
        RemainingCaloriesWidget()
        MacroGoalsWidget()
        WaterProgressWidget()
        TrainingWeekWidget()
        TrainingLiveActivity()
    }
}
