import XCTest
@testable import Ember

@MainActor
final class VideoFeatureTests: XCTestCase {
    func testBundledCatalogKeepsTheBenchLessonAndTwoSections() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Ember/VideoCatalog.json")
        let data = try Data(contentsOf: url)
        let catalog = try VideoCatalog.decode(data)

        let bench = try XCTUnwrap(catalog.items.first { $0.youtubeID == "vcBig73ojpE" })
        XCTAssertEqual(bench.title, "How To Get A Huge Bench Press with Perfect Technique")
        XCTAssertEqual(bench.sourceCredit, "Jeff Nippard")
        XCTAssertEqual(bench.category, .followAlong)
        XCTAssertEqual(bench.durationSeconds, 734)

        let follow = catalog.items(in: .followAlong)
        let shorts = catalog.items(in: .lightShort)
        XCTAssertEqual(follow.first?.youtubeID, "vcBig73ojpE")
        XCTAssertEqual(follow.count, 3)
        XCTAssertEqual(shorts.count, 3)
        XCTAssertEqual(Set(catalog.items.map(\.category)), Set(VideoCategory.allCases))
        XCTAssertTrue(follow.allSatisfy { (8 * 60)...(30 * 60) ~= $0.durationSeconds })
        XCTAssertTrue(shorts.allSatisfy { (2 * 60)...(6 * 60) ~= $0.durationSeconds })
        XCTAssertTrue(catalog.items.allSatisfy { YouTubeVideoID.isValid($0.youtubeID) })
        XCTAssertTrue(catalog.items.allSatisfy { !$0.youtubeID.contains(".") && !$0.youtubeID.contains("/") })
        XCTAssertTrue(catalog.items.allSatisfy { !$0.sourceCredit.isEmpty })
    }

    func testCatalogRejectsMediaPathsAndDuplicateIDs() {
        XCTAssertTrue(YouTubeVideoID.isValid("vcBig73ojpE"))
        XCTAssertFalse(YouTubeVideoID.isValid("vcBig73ojpE.mp4"))
        XCTAssertFalse(YouTubeVideoID.isValid("https://youtu.be/vcBig73ojpE"))
        XCTAssertFalse(YouTubeVideoID.isValid("not-an-id"))

        let page = YouTubeIFrameHTML.page(for: "vcBig73ojpE")
        XCTAssertNotNil(page)
        XCTAssertTrue(page?.contains("https://www.youtube.com/iframe_api") == true)
        XCTAssertTrue(page?.contains("videoId: 'vcBig73ojpE'") == true)
        XCTAssertFalse(page?.contains(".mp4") == true)
        XCTAssertNil(YouTubeIFrameHTML.page(for: "vcBig73ojpE.mp4"))
        XCTAssertNil(YouTubeIFrameHTML.page(for: "https://youtu.be/vcBig73ojpE"))

        let duplicate = """
        {"items":[
          {"title":"A","durationSeconds":60,"category":"followAlong","youtubeID":"vcBig73ojpE","sourceCredit":"Jeff Nippard"},
          {"title":"B","durationSeconds":60,"category":"lightShort","youtubeID":"vcBig73ojpE","sourceCredit":"Jeff Nippard"}
        ]}
        """.data(using: .utf8)!
        XCTAssertThrowsError(try VideoCatalog.decode(duplicate))
    }

    func testRestReminderDefaultsToThreeMinutesAndPausesWhenItEnds() {
        let notifier = SpyNotifier()
        let lounge = VideoLounge(notifier: notifier, receivesNotifications: false)
        XCTAssertEqual(RestReminderClock.defaultMinutes, 3)
        XCTAssertEqual(RestReminderClock.clampedMinutes(0), 1)
        XCTAssertEqual(RestReminderClock.clampedMinutes(3), 3)
        XCTAssertEqual(RestReminderClock.clampedMinutes(9), 5)

        let start = Date(timeIntervalSince1970: 1_000)
        lounge.startRest(minutes: 3, now: start)
        XCTAssertEqual(lounge.restMinutes, 3)
        XCTAssertEqual(lounge.remaining, 180)
        XCTAssertEqual(notifier.scheduled, [180])

        lounge.tick(now: start.addingTimeInterval(179))
        XCTAssertEqual(lounge.remaining, 1)
        XCTAssertFalse(lounge.showRestAlert)
        XCTAssertEqual(lounge.pauseRequests, 0)

        lounge.tick(now: start.addingTimeInterval(180))
        XCTAssertNil(lounge.remaining)
        XCTAssertTrue(lounge.showRestAlert)
        XCTAssertEqual(lounge.pauseRequests, 1)
        XCTAssertEqual(notifier.cancelled, 1)

        lounge.tick(now: start.addingTimeInterval(200))
        XCTAssertEqual(lounge.pauseRequests, 1)
    }

    func testReplacingOrCancelingTheRestClearsThePreviousAlarm() {
        let notifier = SpyNotifier()
        let lounge = VideoLounge(notifier: notifier, receivesNotifications: false)
        let start = Date(timeIntervalSince1970: 5_000)
        lounge.startRest(minutes: 1, now: start)
        lounge.startRest(minutes: 5, now: start)
        XCTAssertEqual(lounge.remaining, 300)
        XCTAssertEqual(notifier.scheduled, [60, 300])
        XCTAssertEqual(notifier.cancelled, 1)

        lounge.cancelRest()
        XCTAssertNil(lounge.remaining)
        XCTAssertFalse(lounge.showRestAlert)
        XCTAssertEqual(lounge.pauseRequests, 0)
        XCTAssertEqual(notifier.cancelled, 2)
    }

    func testDailyPickRoutesDoNotIncludeVideo() {
        switch Route.setup {
        case .setup, .plan, .active, .feedback, .log, .settings:
            break
        }
        let tabs: [AppTab] = [.dailyPick, .video]
        XCTAssertEqual(tabs, [.dailyPick, .video])
    }
}

@MainActor
private final class SpyNotifier: RestNotifying {
    var scheduled: [Int] = []
    var cancelled = 0

    func schedule(after seconds: Int) {
        scheduled.append(seconds)
    }

    func cancel() {
        cancelled += 1
    }
}
