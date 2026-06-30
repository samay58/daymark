import Foundation

/// One `yyyy-MM-dd` formatter for the whole app, pinned to the POSIX locale and the given
/// calendar's time zone so formatting and validation share a single convention. The previous
/// copies disagreed (some pinned UTC, some used the calendar's zone), which let date
/// validation drift from date parsing. Pass the calendar already in hand at each call site.
public enum ISODate {
    public static func formatter(calendar: Calendar = Calendar(identifier: .gregorian)) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter
    }

    public static func string(from date: Date, calendar: Calendar = Calendar(identifier: .gregorian)) -> String {
        formatter(calendar: calendar).string(from: date)
    }

    public static func date(from value: String, calendar: Calendar = Calendar(identifier: .gregorian)) -> Date? {
        formatter(calendar: calendar).date(from: value)
    }
}
