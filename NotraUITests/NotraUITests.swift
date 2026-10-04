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
    @MainActor
    func testLocalisedNewNoteButtonAppears() {
        let locales = [
            ("de_DE", "(de)", "Neue Notiz"),
            ("fr_FR", "(fr)", "Nouvelle note"),
            ("es_ES", "(es)", "Nueva nota"),
            ("ru_RU", "(ru)", "Новая заметка")
        ]

        for (locale, language, expectedLabel) in locales {
            let app = XCUIApplication()
            app.launchArguments += [
                "-AppleLanguages", language,
                "-AppleLocale", locale
            ]
            app.launch()

            XCTAssertTrue(
                app.buttons[expectedLabel].firstMatch.waitForExistence(timeout: 10),
                "Expected New Note button for \(locale)"
            )
            app.terminate()
        }
    }

    #if os(iOS)
    /// A collapsed iPad sidebar must stay reachable while the split view has an inspector.
    @MainActor
    func testSidebarIsReachableOnLaunch() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        let newNoteButton = app.buttons["New Note"].firstMatch
        XCTAssertTrue(newNoteButton.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(newNoteButton.isHittable, app.debugDescription)
        XCTAssertTrue(contentList(in: app).exists, app.debugDescription)

        revealFilterSidebar(in: app)
        let allNotesButton = app.buttons["notes.sidebar.allNotes"]
        XCTAssertTrue(allNotesButton.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(allNotesButton.isSelected, app.debugDescription)
        allNotesButton.tap()
        XCTAssertTrue(newNoteButton.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(newNoteButton.isHittable, app.debugDescription)
    }

    @MainActor
    func testTagSidebarFiltersNotes() throws {
        guard UIDevice.current.userInterfaceIdiom != .pad else {
            throw XCTSkip("Compact tag browsing is exercised on iPhone.")
        }
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        let alphaName = "nav-alpha-\(UUID().uuidString.lowercased())"
        let betaName = "nav-beta-\(UUID().uuidString.lowercased())"
        let titles = [
            "Tag Filter A \(UUID().uuidString)",
            "Tag Filter B \(UUID().uuidString)",
            "Tag Filter C \(UUID().uuidString)",
            "Tag Filter D \(UUID().uuidString)"
        ]
        defer {
            revealFilterSidebar(in: app)
            let allNotesButton = app.buttons["notes.sidebar.allNotes"]
            if allNotesButton.isHittable {
                allNotesButton.tap()
            }
            for title in titles {
                deleteFixtureNote(title, in: app)
            }
        }

        createTaggedNote(titles[0], tags: [alphaName], in: app)
        createTaggedNote(titles[1], tags: [betaName], in: app)
        createTaggedNote(titles[2], tags: [alphaName, betaName], in: app)
        createTaggedNote(titles[3], tags: [], in: app)
        revealFilterSidebar(in: app)

        let alphaButton = app.buttons["notes.sidebar.tag.\(alphaName)"]
        let betaButton = app.buttons["notes.sidebar.tag.\(betaName)"]
        let allNotesButton = app.buttons["notes.sidebar.allNotes"]
        XCTAssertTrue(alphaButton.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(betaButton.waitForExistence(timeout: 10), app.debugDescription)

        alphaButton.tap()
        assertFixtureRows(titles, visible: [titles[0], titles[2]], in: app)

        revealFilterSidebar(in: app)
        alphaButton.tap()
        assertFixtureRows(titles, visible: titles, in: app)

        revealFilterSidebar(in: app)
        alphaButton.tap()
        revealFilterSidebar(in: app)
        betaButton.tap()
        assertFixtureRows(titles, visible: [titles[0], titles[1], titles[2]], in: app)

        revealFilterSidebar(in: app)
        alphaButton.tap()
        assertFixtureRows(titles, visible: [titles[1], titles[2]], in: app)

        revealFilterSidebar(in: app)
        allNotesButton.tap()
        assertFixtureRows(titles, visible: titles, in: app)
    }

    @MainActor
    func testTagSidebarSelectionTraitOnIPad() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else {
            throw XCTSkip("Regular-width tag sidebar selection requires iPad.")
        }

        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }

        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        revealFilterSidebar(in: app)

        let tagButtons = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "notes.sidebar.tag.")
        )
        XCTAssertGreaterThan(tagButtons.count, 0, app.debugDescription)
        let tagButton = tagButtons.firstMatch
        XCTAssertTrue(tagButton.isHittable, app.debugDescription)
        tagButton.tap()
        XCTAssertTrue(tagButton.isSelected, app.debugDescription)

        let content = contentList(in: app)
        XCTAssertTrue(content.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertGreaterThan(content.cells.count, 0, app.debugDescription)
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
        revealNotesContent(in: app)

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

        let sidebar = filterSidebar(in: app)
        let content = contentList(in: app)
        XCTAssertTrue(sidebar.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(content.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(sidebar.frame.intersects(editor.frame), app.debugDescription)
        XCTAssertFalse(content.frame.intersects(editor.frame), app.debugDescription)

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
        revealNotesContent(in: app)

        app.buttons["New Note"].firstMatch.tap()
        let doneButton = app.buttons["Done"].firstMatch
        XCTAssertTrue(doneButton.waitForExistence(timeout: 10))
        if !doneButton.isHittable {
            contentBackButton(in: app).tap()
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
            let reopenButton = app.buttons["Attachments"].firstMatch
            let reopenButtonHittable = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "exists == true AND hittable == true"),
                object: reopenButton
            )
            XCTAssertEqual(XCTWaiter.wait(for: [reopenButtonHittable], timeout: 10), .completed)
            reopenButton.tap()
            let tagField = app.textFields["Add Tag"]
            let tagFieldHittable = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "exists == true AND hittable == true"),
                object: tagField
            )
            XCTAssertEqual(XCTWaiter.wait(for: [tagFieldHittable], timeout: 10), .completed)
            let reopenedInspector = app.collectionViews.containing(.textField, identifier: "Add Tag").firstMatch
            XCTAssertTrue(reopenedInspector.waitForExistence(timeout: 5), app.debugDescription)
            let reopenedGrabber = reopenedInspector.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0))
                .withOffset(CGVector(dx: 0, dy: 2))
            reopenedGrabber.press(forDuration: 0.1, thenDragTo: bottom)
            XCTAssertTrue(tagField.waitForNonExistence(timeout: 10))
        }

        revealNotesContent(in: app)
        let note = app.cells.containing(.staticText, identifier: title).firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 10), app.debugDescription)
        note.tap()
        // The selected note must expose editing after returning from the inspector.
        XCTAssertTrue(app.buttons["Edit"].firstMatch.waitForExistence(timeout: 10))
        XCUIDevice.shared.orientation = .portrait
        revealNotesContent(in: app)
        note.press(forDuration: 1)
        app.buttons["Delete"].firstMatch.tap()
        let confirmation = app.alerts["Delete Note?"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        confirmation.buttons["Delete"].tap()
        XCTAssertTrue(note.waitForNonExistence(timeout: 10))
        revealNotesContent(in: app)
    }

    /// Inserts a Mermaid fence through the iOS keyboard accessory and verifies its rendered preview.
    @MainActor
    func testMermaidInsertionCanBeEditedAndRendered() {
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }

        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        revealNotesContent(in: app)

        app.buttons["New Note"].firstMatch.tap()
        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 10), app.debugDescription)
        let title = "Mermaid Smoke \(UUID().uuidString)"
        editor.tap()
        editor.typeText("\(title)\n")
        defer {
            revealNotesContent(in: app)
            let note = app.cells.containing(.staticText, identifier: title).firstMatch
            if note.waitForExistence(timeout: 3) {
                note.press(forDuration: 1)
                let deleteButton = app.buttons["Delete"].firstMatch
                if deleteButton.waitForExistence(timeout: 3) {
                    deleteButton.tap()
                    let confirmation = app.alerts["Delete Note?"]
                    if confirmation.waitForExistence(timeout: 3) {
                        confirmation.buttons["Delete"].tap()
                    }
                }
            }
        }

        let mermaidButton = app.buttons["Insert Mermaid Diagram"].firstMatch
        XCTAssertTrue(mermaidButton.waitForExistence(timeout: 10), app.debugDescription)
        let accessoryScrollView = app.scrollViews.firstMatch
        for _ in 0..<3 where !mermaidButton.isHittable && accessoryScrollView.exists {
            accessoryScrollView.swipeLeft()
        }
        XCTAssertTrue(mermaidButton.isHittable, app.debugDescription)
        mermaidButton.tap()
        editor.typeText("flowchart TD\n    UIStart --> UIEnd")
        XCTAssertTrue((editor.value as? String)?.contains("UIStart --> UIEnd") == true, app.debugDescription)

        app.buttons["Done"].firstMatch.tap()
        let webView = app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 10), app.debugDescription)
        let renderedDiagram = webView.images["Mermaid diagram"].firstMatch
        XCTAssertTrue(renderedDiagram.waitForExistence(timeout: 15), app.debugDescription)
    }

    /// Verifies fixed keyboard history controls and native text-view undo/redo.
    @MainActor
    func testKeyboardAccessoryUndoRedo() {
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }

        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        revealNotesContent(in: app)
        app.buttons["New Note"].firstMatch.tap()

        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 10), app.debugDescription)
        let title = "Keyboard History \(UUID().uuidString)"
        editor.tap()
        editor.typeText("\(title)\n")
        defer {
            revealNotesContent(in: app)
            let note = app.cells.containing(.staticText, identifier: title).firstMatch
            if note.waitForExistence(timeout: 3) {
                note.press(forDuration: 1)
                let deleteButton = app.buttons["Delete"].firstMatch
                if deleteButton.waitForExistence(timeout: 3) {
                    deleteButton.tap()
                    let confirmation = app.alerts["Delete Note?"]
                    if confirmation.waitForExistence(timeout: 3) {
                        confirmation.buttons["Delete"].tap()
                    }
                }
            }
        }

        let undoButton = app.buttons["Undo"]
        let redoButton = app.buttons["Redo"]
        let formattingScrollView = app.scrollViews["editorFormattingScrollView"]
        XCTAssertTrue(undoButton.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(redoButton.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(formattingScrollView.waitForExistence(timeout: 10), app.debugDescription)
        let initiallyEnabled = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "isEnabled == true"),
            object: undoButton
        )
        XCTAssertEqual(XCTWaiter.wait(for: [initiallyEnabled], timeout: 10), .completed)

        let initialUndoFrame = undoButton.frame
        let initialRedoFrame = redoButton.frame

        func assertHistoryFrames(_ undoFrame: CGRect, _ redoFrame: CGRect, file: StaticString = #filePath, line: UInt = #line) {
            XCTAssertEqual(abs(undoButton.frame.minX - undoFrame.minX), 0, accuracy: 1, file: file, line: line)
            XCTAssertEqual(abs(undoButton.frame.minY - undoFrame.minY), 0, accuracy: 1, file: file, line: line)
            XCTAssertEqual(abs(redoButton.frame.minX - redoFrame.minX), 0, accuracy: 1, file: file, line: line)
            XCTAssertEqual(abs(redoButton.frame.minY - redoFrame.minY), 0, accuracy: 1, file: file, line: line)
            XCTAssertGreaterThanOrEqual(undoButton.frame.minY, formattingScrollView.frame.minY - 1, file: file, line: line)
            XCTAssertLessThanOrEqual(redoButton.frame.maxY, formattingScrollView.frame.maxY + 1, file: file, line: line)
        }

        func attachScreenshot(_ name: String) {
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
        }

        func waitForValue(_ value: String, timeout: TimeInterval = 10) -> Bool {
            let expectation = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "value == %@", value),
                object: editor
            )
            return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
        }

        attachScreenshot("Portrait toolbar initial")
        let mermaidButton = app.buttons["Insert Mermaid Diagram"].firstMatch
        for _ in 0..<6 where !mermaidButton.isHittable {
            formattingScrollView.swipeLeft()
            assertHistoryFrames(initialUndoFrame, initialRedoFrame)
        }
        XCTAssertTrue(mermaidButton.isHittable, app.debugDescription)
        attachScreenshot("Portrait toolbar scrolled")

        formattingScrollView.swipeRight()
        assertHistoryFrames(initialUndoFrame, initialRedoFrame)
        let headingButton = app.buttons["Headers"].firstMatch
        for _ in 0..<6 where !headingButton.isHittable {
            formattingScrollView.swipeRight()
            assertHistoryFrames(initialUndoFrame, initialRedoFrame)
        }
        XCTAssertTrue(headingButton.isHittable, app.debugDescription)
        formattingScrollView.swipeLeft()
        assertHistoryFrames(initialUndoFrame, initialRedoFrame)
        for _ in 0..<6 where !mermaidButton.isHittable {
            formattingScrollView.swipeLeft()
            assertHistoryFrames(initialUndoFrame, initialRedoFrame)
        }
        XCTAssertTrue(mermaidButton.isHittable, app.debugDescription)

        let baseline = editor.value as? String ?? ""
        mermaidButton.tap()
        let insertedBlock = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value CONTAINS %@", "```mermaid\nflowchart TD\n    A --> B\n```"),
            object: editor
        )
        XCTAssertEqual(XCTWaiter.wait(for: [insertedBlock], timeout: 10), .completed)
        let formatted = editor.value as? String ?? ""
        XCTAssertTrue(formatted.contains("```mermaid\nflowchart TD\n    A --> B\n```"), formatted)
        XCTAssertTrue(undoButton.isEnabled, app.debugDescription)
        attachScreenshot("Formatting applied")

        undoButton.tap()
        XCTAssertTrue(waitForValue(baseline), app.debugDescription)
        XCTAssertTrue(redoButton.isEnabled, app.debugDescription)
        attachScreenshot("Formatting undone")
        redoButton.tap()
        XCTAssertTrue(waitForValue(formatted), app.debugDescription)
        XCTAssertTrue(undoButton.isEnabled, app.debugDescription)
        attachScreenshot("Formatting redone")
        undoButton.tap()
        XCTAssertTrue(waitForValue(baseline), app.debugDescription)
        editor.typeText("replacement")
        let appended = baseline + "replacement"
        XCTAssertTrue(waitForValue(appended), app.debugDescription)
        let redoDisabled = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "isEnabled == false"),
            object: redoButton
        )
        XCTAssertEqual(XCTWaiter.wait(for: [redoDisabled], timeout: 10), .completed)

        var undoCount = 0
        while (editor.value as? String) != baseline, undoCount < "replacement".count + 1 {
            XCTAssertTrue(undoButton.isEnabled, app.debugDescription)
            let previousValue = editor.value as? String ?? ""
            undoButton.tap()
            let changed = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "value != %@", previousValue),
                object: editor
            )
            XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 10), .completed)
            undoCount += 1
        }
        XCTAssertEqual(editor.value as? String, baseline, app.debugDescription)
        XCTAssertGreaterThan(undoCount, 0)

        for _ in 0..<undoCount {
            XCTAssertTrue(redoButton.isEnabled, app.debugDescription)
            let previousValue = editor.value as? String ?? ""
            redoButton.tap()
            let changed = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "value != %@", previousValue),
                object: editor
            )
            XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 10), .completed)
        }
        XCTAssertTrue(waitForValue(appended), app.debugDescription)

        XCUIDevice.shared.orientation = .landscapeLeft
        let landscapeReady = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true AND hittable == true"),
            object: undoButton
        )
        XCTAssertEqual(XCTWaiter.wait(for: [landscapeReady], timeout: 10), .completed)
        let landscapeUndoFrame = undoButton.frame
        let landscapeRedoFrame = redoButton.frame
        formattingScrollView.swipeLeft()
        assertHistoryFrames(landscapeUndoFrame, landscapeRedoFrame)
        formattingScrollView.swipeRight()
        assertHistoryFrames(landscapeUndoFrame, landscapeRedoFrame)
        attachScreenshot("Landscape toolbar")
    }

    /// Verifies edit-mode content starts below the visible top toolbar.
    @MainActor
    func testEditorStartsBelowTopChromeWhenEnteringEditMode() {
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }

        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        revealNotesContent(in: app)

        app.buttons["New Note"].firstMatch.tap()
        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 10), app.debugDescription)
        let title = "Editor Top Inset Regression \(UUID().uuidString)"
        editor.tap()
        editor.typeText("\(title)\nSecond line\nThird line")
        app.buttons["Done"].firstMatch.tap()

        revealNotesContent(in: app)
        let note = app.cells.containing(.staticText, identifier: title).firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 10), app.debugDescription)
        note.tap()

        let editButton = app.buttons["Edit"].firstMatch
        XCTAssertTrue(editButton.waitForExistence(timeout: 10), app.debugDescription)
        editButton.tap()
        let doneButton = app.buttons["Done"].firstMatch
        XCTAssertTrue(doneButton.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(editor.waitForExistence(timeout: 10), app.debugDescription)

        let topChromeBottom = doneButton.frame.maxY
        XCTAssertGreaterThanOrEqual(
            editor.frame.minY,
            topChromeBottom - 1,
            app.debugDescription
        )

        doneButton.tap()
        revealNotesContent(in: app)
        note.press(forDuration: 1)
        app.buttons["Delete"].firstMatch.tap()
        let confirmation = app.alerts["Delete Note?"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5), app.debugDescription)
        confirmation.buttons["Delete"].tap()
        XCTAssertTrue(note.waitForNonExistence(timeout: 10), app.debugDescription)
    }

    /// Returns to notes content through native split-view navigation when it is not already usable.
    @MainActor
    private func revealNotesContent(in app: XCUIApplication) {
        let newNoteButton = app.buttons["New Note"].firstMatch
        if !newNoteButton.isHittable {
            let backButton = contentBackButton(in: app)
            if backButton.isHittable {
                backButton.tap()
            } else if UIDevice.current.userInterfaceIdiom == .pad {
                let hideSidebarButton = app.buttons["Hide Sidebar"].firstMatch
                if hideSidebarButton.isHittable {
                    hideSidebarButton.tap()
                }
            }
        }
        expectation(
            for: NSPredicate(format: "exists == true AND hittable == true"),
            evaluatedWith: newNoteButton
        )
        waitForExpectations(timeout: 10)
    }

    @MainActor
    private func contentBackButton(in app: XCUIApplication) -> XCUIElement {
        app.buttons["Back"].firstMatch
    }

    @MainActor
    private func contentList(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "notes.content").firstMatch
    }

    @MainActor
    private func revealFilterSidebar(in app: XCUIApplication) {
        if UIDevice.current.userInterfaceIdiom == .pad {
            let showSidebarButton = app.buttons["Show Sidebar"].firstMatch
            if showSidebarButton.isHittable {
                showSidebarButton.tap()
            }
        } else {
            revealNotesContent(in: app)
            let sidebarButton = app.navigationBars.buttons.firstMatch
            if sidebarButton.isHittable {
                sidebarButton.tap()
            }
        }
    }

    @MainActor
    private func sidebarVisibilityButton(in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(
            NSPredicate(format: "label == 'Hide Sidebar' OR label == 'Show Sidebar'")
        ).firstMatch
    }

    @MainActor
    private func filterSidebar(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "notes.sidebar").firstMatch
    }

    @MainActor
    private func createTaggedNote(_ title: String, tags: [String], in app: XCUIApplication) {
        revealNotesContent(in: app)
        app.buttons["New Note"].firstMatch.tap()
        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 10), app.debugDescription)
        editor.tap()
        editor.typeText(title)
        app.buttons["Done"].firstMatch.tap()

        guard !tags.isEmpty else { return }
        let attachmentsButton = app.buttons["info"].firstMatch
        XCTAssertTrue(attachmentsButton.waitForExistence(timeout: 10), app.debugDescription)
        attachmentsButton.tap()
        let tagField = app.textFields["Add Tag"]
        XCTAssertTrue(tagField.waitForExistence(timeout: 10), app.debugDescription)
        for tag in tags {
            tagField.tap()
            tagField.typeText(tag)
            app.buttons["Add Tag"].tap()
        }
        if UIDevice.current.userInterfaceIdiom == .pad {
            attachmentsButton.tap()
        } else {
            let inspector = app.collectionViews.containing(.textField, identifier: "Add Tag").firstMatch
            XCTAssertTrue(inspector.waitForExistence(timeout: 5), app.debugDescription)
            let grabber = inspector.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0))
                .withOffset(CGVector(dx: 0, dy: 2))
            let bottom = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95))
            grabber.press(forDuration: 0.1, thenDragTo: bottom)
            XCTAssertTrue(tagField.waitForNonExistence(timeout: 10), app.debugDescription)
        }
        revealNotesContent(in: app)
    }

    @MainActor
    private func assertFixtureRows(_ titles: [String], visible: [String], in app: XCUIApplication) {
        let content = contentList(in: app)
        XCTAssertTrue(content.waitForExistence(timeout: 10), app.debugDescription)
        for title in titles {
            let row = content.cells.containing(.staticText, identifier: title).firstMatch
            XCTAssertEqual(row.exists, visible.contains(title), "Unexpected visibility for \(title)")
        }
    }

    @MainActor
    private func deleteFixtureNote(_ title: String, in app: XCUIApplication) {
        revealNotesContent(in: app)
        let row = app.cells.containing(.staticText, identifier: title).firstMatch
        guard row.waitForExistence(timeout: 2) else { return }
        row.press(forDuration: 1)
        let deleteButton = app.buttons["Delete"].firstMatch
        guard deleteButton.waitForExistence(timeout: 5) else { return }
        deleteButton.tap()
        let confirmation = app.alerts["Delete Note?"]
        guard confirmation.waitForExistence(timeout: 5) else { return }
        confirmation.buttons["Delete"].tap()
        XCTAssertTrue(row.waitForNonExistence(timeout: 10), app.debugDescription)
    }
    #endif

#if os(macOS)
    @MainActor
    func testSidebarVisibilitySurvivesRelaunch() {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        let sidebar = app.descendants(matching: .any).matching(identifier: "notes.sidebar").firstMatch
        let initialVisibility = sidebar.exists
        if !initialVisibility {
            app.buttons["Show Sidebar"].firstMatch.tap()
            XCTAssertTrue(sidebar.waitForExistence(timeout: 10), app.debugDescription)
        }
        XCTAssertTrue(app.buttons["New Note"].firstMatch.isHittable, app.debugDescription)

        app.buttons["Hide Sidebar"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Show Sidebar"].firstMatch.waitForExistence(timeout: 10), app.debugDescription)
        app.terminate()
        app.launch()
        XCTAssertFalse(sidebar.exists, app.debugDescription)
        XCTAssertTrue(app.buttons["New Note"].firstMatch.isHittable, app.debugDescription)

        app.buttons["Show Sidebar"].firstMatch.tap()
        XCTAssertTrue(sidebar.waitForExistence(timeout: 10), app.debugDescription)
        app.terminate()
        app.launch()
        XCTAssertTrue(sidebar.waitForExistence(timeout: 10), app.debugDescription)

        if !initialVisibility {
            app.buttons["Hide Sidebar"].firstMatch.tap()
            XCTAssertTrue(app.buttons["Show Sidebar"].firstMatch.waitForExistence(timeout: 10), app.debugDescription)
        }
    }

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
