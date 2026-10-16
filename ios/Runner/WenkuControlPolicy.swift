import Foundation

enum WenkuControlPolicy {
  static func shouldBeginPan(horizontal: Double, vertical: Double) -> Bool {
    horizontal.isFinite && vertical.isFinite && abs(horizontal) > abs(vertical)
  }
}
