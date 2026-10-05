import Foundation

enum DurationFormat {
    /// Editor input is deliberately compact: `5` means five minutes, while
    /// `5:30` and `1:05:00` mean minutes:seconds and hours:minutes:seconds.
    static func parse(_ input: String) -> Int? {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        let parts = value.split(separator: ":", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count),
              parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }),
              let numbers = try? parts.map({ part -> Int in
                  guard let number = Int(part) else { throw ParseError.invalid }
                  return number
              }) else { return nil }

        let seconds: Int
        switch numbers.count {
        case 1:
            seconds = numbers[0] * 60
        case 2:
            guard numbers[1] < 60 else { return nil }
            seconds = numbers[0] * 60 + numbers[1]
        case 3:
            guard numbers[1] < 60, numbers[2] < 60 else { return nil }
            seconds = numbers[0] * 3_600 + numbers[1] * 60 + numbers[2]
        default:
            return nil
        }
        guard seconds > 0, seconds <= 359_999 else { return nil }
        return seconds
    }

    static func editor(_ seconds: Int) -> String {
        let safe = max(0, seconds)
        if safe >= 3_600 {
            return String(format: "%d:%02d:%02d", safe / 3_600, (safe / 60) % 60, safe % 60)
        }
        return String(format: "%d:%02d", safe / 60, safe % 60)
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let safe = max(0, Int(floor(seconds)))
        if safe >= 3_600 {
            return String(format: "%d:%02d:%02d", safe / 3_600, (safe / 60) % 60, safe % 60)
        }
        return String(format: "%02d:%02d", safe / 60, safe % 60)
    }

    static func remaining(_ seconds: TimeInterval) -> String {
        clock(TimeInterval(max(0, Int(ceil(seconds)))))
    }

    private enum ParseError: Error {
        case invalid
    }
}
