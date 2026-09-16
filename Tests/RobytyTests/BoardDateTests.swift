import Foundation
import RobytyCore

@MainActor
enum BoardDateTests {
    static func run() {
        T.test("fridayIsWeekday") {
            try T.ok(!BoardDate.isWeekend(stamp: Fixtures.friday))
            try T.ok(!BoardDate.isWeekend(Fixtures.noon(Fixtures.friday)))
        }

        T.test("saturdayAndSundayAreWeekend") {
            try T.ok(BoardDate.isWeekend(stamp: Fixtures.saturday))
            try T.ok(BoardDate.isWeekend(stamp: Fixtures.sunday))
            try T.ok(BoardDate.isWeekend(Fixtures.noon(Fixtures.saturday)))
            try T.ok(BoardDate.isWeekend(Fixtures.noon(Fixtures.sunday)))
        }

        T.test("boardStampOnWeekendIsPreviousFriday") {
            try T.eq(BoardDate.boardStamp(Fixtures.noon(Fixtures.friday)), Fixtures.friday)
            try T.eq(BoardDate.boardStamp(Fixtures.noon(Fixtures.saturday)), Fixtures.friday)
            try T.eq(BoardDate.boardStamp(Fixtures.noon(Fixtures.sunday)), Fixtures.friday)
            try T.eq(BoardDate.boardStamp(Fixtures.noon(Fixtures.monday)), Fixtures.monday)
        }

        T.test("nextWeekdayAfterFridayIsMonday") {
            try T.eq(BoardDate.nextWeekdayStamp(after: Fixtures.friday), Fixtures.monday)
            try T.eq(BoardDate.nextWeekdayStamp(after: Fixtures.thursday), Fixtures.friday)
            try T.eq(BoardDate.nextWeekdayStamp(after: Fixtures.monday), Fixtures.tuesday)
        }

        T.test("weekdayStepsSkipWeekend") {
            try T.eq(BoardDate.weekdaySteps(from: Fixtures.thursday, to: Fixtures.friday), 1)
            try T.eq(BoardDate.weekdaySteps(from: Fixtures.friday, to: Fixtures.monday), 1)
            try T.eq(BoardDate.weekdaySteps(from: Fixtures.thursday, to: Fixtures.monday), 2)
            try T.eq(BoardDate.weekdaySteps(from: Fixtures.friday, to: Fixtures.friday), 0)
        }

        T.test("lastWeekdayStopsOnFriday") {
            let sat = Fixtures.noon(Fixtures.saturday)
            try T.eq(BoardDate.stamp(BoardDate.lastWeekday(onOrBefore: sat)), Fixtures.friday)
        }

        T.test("boardStampKeepsWeekendWhenNotSkipping") {
            try T.eq(
                BoardDate.boardStamp(Fixtures.noon(Fixtures.saturday), skipWeekends: false),
                Fixtures.saturday
            )
            try T.eq(
                BoardDate.boardStamp(Fixtures.noon(Fixtures.sunday), skipWeekends: false),
                Fixtures.sunday
            )
        }

        T.test("nextWeekdayCountsWeekendDaysWhenNotSkipping") {
            try T.eq(
                BoardDate.nextWeekdayStamp(after: Fixtures.friday, skipWeekends: false),
                Fixtures.saturday
            )
            try T.eq(
                BoardDate.nextWeekdayStamp(after: Fixtures.saturday, skipWeekends: false),
                Fixtures.sunday
            )
        }

        T.test("weekdayStepsCountsEveryDayWhenNotSkipping") {
            try T.eq(BoardDate.weekdaySteps(from: Fixtures.friday, to: Fixtures.monday, skipWeekends: false), 3)
            try T.eq(BoardDate.weekdaySteps(from: Fixtures.thursday, to: Fixtures.friday, skipWeekends: false), 1)
        }

        T.test("mondayOfFridayIsPriorMonday") {
            let monday = BoardDate.monday(of: Fixtures.friday)
            try T.ok(monday != nil, "monday(of: friday)")
            try T.eq(BoardDate.stamp(monday!), "2026-08-17")
            try T.eq(BoardDate.stamp(BoardDate.friday(ofMonday: monday!)), Fixtures.friday)
        }

        T.test("weekdayLabelIsLowercaseAmsterdam") {
            try T.eq(BoardDate.weekdayLabel(Fixtures.friday), "friday 21 aug")
            try T.eq(BoardDate.weekdayLabel(Fixtures.monday), "monday 24 aug")
            try T.eq(BoardDate.shortDay(Fixtures.friday), "21 aug")
        }
    }
}
