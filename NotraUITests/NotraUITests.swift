//
//  NotraUITests.swift
//  NotraUITests
//
//

// The test bundle participates in Xcode's App Intents metadata extraction.
import AppIntents
import XCTest

#if os(iOS)
import UIKit
#endif

/// Provides the basic application launch and performance UI-test entry points.
final class NotraUITests: XCTestCase {
    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testExample() {
        // UI tests must launch the application that they test.
        let app = XCUIApplication()
        app.launch()

        // Use XCTAssert and related functions to verify your tests produce the correct results.
        // XCUIAutomation Documentation
        // https://developer.apple.com/documentation/xcuiautomation
    }

    #if os(iOS)
    /// A collapsed iPad sidebar must stay reachable while the split view has an inspector.
    @MainActor
    func testSidebarIsReachableOnLaunch() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        if UIDevice.current.userInterfaceIdiom == .pad {
            let sidebarButton = sidebarVisibilityButton(in: app)
            XCTAssertTrue(sidebarButton.waitForExistence(timeout: 10), app.debugDescription)
            XCTAssertTrue(sidebarButton.isHittable)
            if sidebarButton.label == "Hide Sidebar" {
                sidebarButton.tap()
            }

            let showSidebarButton = app.buttons["Show Sidebar"].firstMatch
            XCTAssertTrue(showSidebarButton.waitForExistence(timeout: 10), app.debugDescription)
            showSidebarButton.tap()
            XCTAssertTrue(app.buttons["Hide Sidebar"].waitForExistence(timeout: 10))
        }

        // A visible create action proves the notes sidebar can be used, including with an empty library.
        let newNoteButton = app.buttons["New Note"].firstMatch
        let isHittable = NSPredicate(format: "exists == true AND hittable == true")
        expectation(for: isHittable, evaluatedWith: newNoteButton)
        waitForExpectations(timeout: 10)
    }

    /// Ensures the regular-width iPad layout gives the editor space beside the sidebar.
    @MainActor
    func testSidebarPushesDetailInLandscape() {
        guard UIDevice.current.userInterfaceIdiom == .pad else {
            return
        }

        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }

        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        revealSidebar(in: app)

        app.buttons["New Note"].firstMatch.tap()
        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 10), app.debugDescription)
        editor.tap()
        let title = "Sidebar Layout Regression \(UUID().uuidString)"
        editor.typeText(title)

        let sidebarButton = sidebarVisibilityButton(in: app)
        XCTAssertTrue(sidebarButton.waitForExistence(timeout: 10), app.debugDescription)
        if sidebarButton.label == "Show Sidebar" {
            sidebarButton.tap()
        }

        let sidebar = sidebarCollectionView(in: app)
        XCTAssertTrue(sidebar.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(sidebar.frame.intersects(editor.frame), app.debugDescription)

        app.buttons["Hide Sidebar"].firstMatch.tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        let showSidebarButton = app.buttons["Show Sidebar"].firstMatch
        XCTAssertTrue(showSidebarButton.waitForExistence(timeout: 10), app.debugDescription)
        showSidebarButton.tap()

        XCTAssertTrue(app.buttons["Hide Sidebar"].waitForExistence(timeout: 10))
        XCTAssertFalse(sidebar.frame.intersects(editor.frame), app.debugDescription)

        app.buttons["Done"].firstMatch.tap()
        let note = app.cells.containing(.staticText, identifier: title).firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 10), app.debugDescription)
        note.press(forDuration: 1)
        app.buttons["Delete"].firstMatch.tap()
        let confirmation = app.alerts["Delete Note?"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        confirmation.buttons["Delete"].tap()
        XCTAssertTrue(note.waitForNonExistence(timeout: 10))
    }

    /// Exercises presentation changes with a note created by this test, then removes only that note.
    @MainActor
    func testNoteNavigationSurvivesInspectorAndRotation() {
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        revealSidebar(in: app)

        app.buttons["New Note"].firstMatch.tap()
        let doneButton = app.buttons["Done"].firstMatch
        XCTAssertTrue(doneButton.waitForExistence(timeout: 10))
        if !doneButton.isHittable {
            sidebarButton(in: app).tap()
        }
        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        let title = "Navigation Regression \(UUID().uuidString)"
        editor.tap()
        editor.typeText(title)
        doneButton.tap()

        let inspectorButton = app.buttons["Attachments"].firstMatch
        XCTAssertTrue(inspectorButton.waitForExistence(timeout: 10))
        inspectorButton.tap()
        XCTAssertTrue(app.textFields["Add Tag"].waitForExistence(timeout: 10))
        if UIDevice.current.userInterfaceIdiom == .pad {
            inspectorButton.tap()
            XCUIDevice.shared.orientation = .landscapeLeft
        } else {
            // SwiftUI exposes this inspector as a collection view rather than a Sheet element.
            let inspector = app.collectionViews.containing(.textField, identifier: "Add Tag").firstMatch
            XCTAssertTrue(inspector.waitForExistence(timeout: 5), app.debugDescription)
            let grabber = inspector.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0))
                .withOffset(CGVector(dx: 0, dy: 2))
            let bottom = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95))
            grabber.press(forDuration: 0.1, thenDragTo: bottom)
            XCTAssertTrue(app.textFields["Add Tag"].waitForNonExistence(timeout: 10))
        }

        revealSidebar(in: app)
        let note = app.cells.containing(.staticText, identifier: title).firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 10), app.debugDescription)
        note.tap()
        // The selected note must expose editing after returning from the inspector.
        XCTAssertTrue(app.buttons["Edit"].firstMatch.waitForExistence(timeout: 10))
        XCUIDevice.shared.orientation = .portrait
        revealSidebar(in: app)
        note.press(forDuration: 1)
        app.buttons["Delete"].firstMatch.tap()
        let confirmation = app.alerts["Delete Note?"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        confirmation.buttons["Delete"].tap()
        XCTAssertTrue(note.waitForNonExistence(timeout: 10))
        revealSidebar(in: app)
    }

    /// Uses the system sidebar control or compact back button without relying on screen coordinates.
    @MainActor
    private func revealSidebar(in app: XCUIApplication) {
        let newNoteButton = app.buttons["New Note"].firstMatch
        if !newNoteButton.isHittable {
            let button = sidebarButton(in: app)
            XCTAssertTrue(button.waitForExistence(timeout: 10), app.debugDescription)
            button.tap()
        }
        expectation(
            for: NSPredicate(format: "exists == true AND hittable == true"),
            evaluatedWith: newNoteButton
        )
        waitForExpectations(timeout: 10)
    }

    @MainActor
    private func sidebarButton(in app: XCUIApplication) -> XCUIElement {
        let sidebarButton = sidebarVisibilityButton(in: app)
        if sidebarButton.exists {
            return sidebarButton
        }

        return app.buttons["Back"].firstMatch
    }

    @MainActor
    private func sidebarVisibilityButton(in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(
            NSPredicate(format: "label == 'Hide Sidebar' OR label == 'Show Sidebar'")
        ).firstMatch
    }

    @MainActor
    private func sidebarCollectionView(in app: XCUIApplication) -> XCUIElement {
        app.collectionViews.matching(NSPredicate(format: "label == 'Sidebar'")).firstMatch
    }
    #endif

    #if os(macOS)
    /// Closing the primary window must leave the app running and allow it to reopen with Command-0.
    @MainActor
    func testPrimaryWindowCanBeReopenedFromWindowMenu() {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        let mainWindow = app.windows.firstMatch
        XCTAssertTrue(mainWindow.waitForExistence(timeout: 10), app.debugDescription)

        let fileMenu = app.menuBars.menuBarItems["File"]
        XCTAssertTrue(fileMenu.waitForExistence(timeout: 10), app.debugDescription)
        fileMenu.click()
        XCTAssertFalse(app.menuBars.menuItems["New Window"].exists, app.debugDescription)

        app.typeKey(XCUIKeyboardKey(rawValue: "w"), modifierFlags: .command)
        XCTAssertTrue(mainWindow.waitForNonExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(app.state, .runningForeground, app.debugDescription)

        let windowMenu = app.menuBars.menuBarItems["Window"]
        XCTAssertTrue(windowMenu.waitForExistence(timeout: 10), app.debugDescription)
        windowMenu.click()
        let showNotraCommand = app.menuBars.menuItems["Show Notra"]
        XCTAssertTrue(showNotraCommand.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(showNotraCommand.isEnabled, app.debugDescription)

        app.typeKey(XCUIKeyboardKey(rawValue: "0"), modifierFlags: .command)
        XCTAssertTrue(mainWindow.waitForExistence(timeout: 10), app.debugDescription)

        app.typeKey(XCUIKeyboardKey(rawValue: "0"), modifierFlags: .command)
        XCTAssertEqual(app.windows.count, 1, app.debugDescription)
    }
    #endif

    @MainActor
    func testLaunchPerformance() {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
