import Foundation

// HH:MM:SS from milliseconds
func formatRemaining(_ ms: Int) -> String {
  let total = max(0, ms / 1000)
  let h = total / 3600
  let m = (total % 3600) / 60
  let s = total % 60
  return String(format: "%02d:%02d:%02d", h, m, s)
}
