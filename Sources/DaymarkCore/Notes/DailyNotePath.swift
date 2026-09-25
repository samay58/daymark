import Foundation

/// Parses a `daily/YYYY/MM/YYYY-MM-DD.md` note path into a midnight `Date` in the given
/// calendar. Nil for any other path shape.
enum DailyNotePath {
    private static let regex = try! NSRegularExpression(pattern: #"^daily/(\d{4})/(\d{2})/(\d{4})-(\d{2})-(\d{2})\.md$"#)

    static func date(from path: String, calendar: Calendar) -> Date? {
        let range = NSRange(path.startIndex..<path.endIndex, in: path)
        guard let match = regex.firstMatch(in: path, range: range),
              let yearRange = Range(match.range(at: 3), in: path),
              let monthRange = Range(match.range(at: 4), in: path),
              let dayRange = Range(match.range(at: 5), in: path),
              let year = Int(path[yearRange]),
              let month = Int(path[monthRange]),
              let day = Int(path[dayRange]) else {
            return nil
        }

        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        return calendar.date(from: components)
    }
}
