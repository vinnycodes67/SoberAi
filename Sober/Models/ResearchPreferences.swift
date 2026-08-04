import Foundation

struct ResearchPreferences: Codable, Equatable, Sendable {
  var sleepHours: Double
  var caffeineWithinSixHours: Bool
  var medicationMayAffectPerformance: Bool
  var illnessOrInjuryMayAffectPerformance: Bool
  var strenuousExerciseWithinTwoHours: Bool
  var visionCorrection: ResearchVisionCorrection

  init(
    sleepHours: Double = 8,
    caffeineWithinSixHours: Bool = false,
    medicationMayAffectPerformance: Bool = false,
    illnessOrInjuryMayAffectPerformance: Bool = false,
    strenuousExerciseWithinTwoHours: Bool = false,
    visionCorrection: ResearchVisionCorrection = .unknown
  ) {
    self.sleepHours = sleepHours
    self.caffeineWithinSixHours = caffeineWithinSixHours
    self.medicationMayAffectPerformance = medicationMayAffectPerformance
    self.illnessOrInjuryMayAffectPerformance = illnessOrInjuryMayAffectPerformance
    self.strenuousExerciseWithinTwoHours = strenuousExerciseWithinTwoHours
    self.visionCorrection = visionCorrection
  }
}
