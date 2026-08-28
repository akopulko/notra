import CoreGraphics
import Foundation
import ImageIO
@testable import Notra
import PDFKit
import Testing
import UniformTypeIdentifiers

@MainActor
struct NotePDFExporterTests {
    @Test
    func `exports valid empty PDF with A 4 media box`() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let item = try fixture.export(markdown: "")
        defer { removeExport(item) }

        let document = try #require(PDFDocument(url: item.fileURL))
        #expect(document.pageCount == 1)
        let mediaBox = try #require(document.page(at: 0)?.bounds(for: .mediaBox))
        #expect(abs(mediaBox.width - NotePDFExporter.pageSize.width) < 0.1)
        #expect(abs(mediaBox.height - NotePDFExporter.pageSize.height) < 0.1)
    }

    @Test
    func `exports extractable text and paginates long notes`() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let markdown = (0..<180).map { "Line \($0): unsaved printable text." }.joined(separator: "\n\n")
        let item = try fixture.export(markdown: markdown)
        defer { removeExport(item) }

        let document = try #require(PDFDocument(url: item.fileURL))
        #expect(document.pageCount > 1)
        #expect(document.page(at: 0)?.string?.contains("Line 0: unsaved printable text.") == true)
        #expect(document.page(at: document.pageCount - 1)?.string?.contains("Line 179: unsaved printable text.") == true)
        #expect(document.string?.contains("Line 0: unsaved printable text.") == true)
        #expect(document.string?.contains("Line 179: unsaved printable text.") == true)
    }

    @Test
    func `preserves exported text order`() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let item = try fixture.export(markdown: "First string. Second string. Third string.")
        defer { removeExport(item) }

        let document = try #require(PDFDocument(url: item.fileURL))
        #expect(document.string?.contains("First string. Second string. Third string.") == true)
    }

    @Test
    func `keeps exported images upright`() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.writeOrientationMarker(named: "marker.png")

        let item = try fixture.export(markdown: "![Marker](assets/marker.png)")
        defer { removeExport(item) }

        let pdf = try #require(CGPDFDocument(item.fileURL as CFURL))
        let page = try #require(pdf.page(at: 1))
        let bandCentroids = try #require(rasterize(page: page))
        #expect(bandCentroids.blackY < bandCentroids.grayY)
    }

    @Test
    func `includes only decoded local image markdown nodes`() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.writeImage(named: "valid.png")
        try fixture.writeImage(named: "unlinked.png")
        try fixture.writeAsset(named: "corrupt.png", data: Data("not an image".utf8))
        try fixture.writeAsset(named: "report.pdf", data: Data("PDF attachment".utf8))
        try fixture.writeAsset(named: "document.docx", data: Data("document attachment".utf8))
        try fixture.writeAsset(named: "archive.zip", data: Data("archive attachment".utf8))
        try fixture.writeAsset(named: "audio.mp3", data: Data("audio attachment".utf8))
        try fixture.writeAsset(named: "video.mp4", data: Data("video attachment".utf8))

        let markdown = """
        ![Valid](assets/valid.png)
        ![Duplicate](assets/valid.png)
        ![Missing](assets/missing.png)
        ![Corrupt](assets/corrupt.png)
        ![Remote](https://example.com/remote.png)
        ![Data](data:image/png;base64,AAAA)
        ![PDF](assets/report.pdf)
        ![Document](assets/document.docx)
        ![Archive](assets/archive.zip)
        ![Audio](assets/audio.mp3)
        ![Video](assets/video.mp4)
        ![Outside](../outside.png)
        [Ordinary link](assets/unlinked.png)
        """
        let item = try fixture.export(markdown: markdown)
        defer { removeExport(item) }

        #expect(item.includedImageURLs == [fixture.assetURL(named: "valid.png")])
    }

    @Test
    func `omits non image attachment cards but preserves surrounding text`() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.writeAsset(named: "report.pdf", data: Data("PDF attachment".utf8))
        try fixture.writeImage(named: "unlinked.png")

        let item = try fixture.export(
            markdown: "Before [Report](assets/report.pdf) and [Image](assets/unlinked.png) After"
        )
        defer { removeExport(item) }

        let document = try #require(PDFDocument(url: item.fileURL))
        #expect(document.string?.contains("Before") == true)
        #expect(document.string?.contains("After") == true)
        #expect(document.string?.contains("Report") == false)
        #expect(document.string?.contains("report.pdf") == false)
        #expect(document.string?.contains("Image") == false)
    }

    @Test
    func `preserves PDF inline fragment order around images`() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.writeImage(named: "image.png")

        let document = SwiftMarkdownParser().parse("Before ![Image](assets/image.png) After")
        guard case let .paragraph(_, inlines) = document.blocks.first else {
            Issue.record("Expected an image paragraph")
            return
        }

        let style = MarkdownStyle.notra(previewFontName: AppearanceFont.defaultName)
        let renderData = MarkdownAttributedStringBuilder(
            style: style,
            context: .textBundle(noteURL: fixture.bundleURL)
        ).renderData(for: inlines)
        let fragments = renderData.pdfFragments.map { fragment in
            switch fragment.content {
            case let .text(text):
                String(text.characters)
            case .image:
                "<image>"
            }
        }

        #expect(fragments == ["Before ", "<image>", " After"])
    }

    @Test
    func `assigns unique IDs to composite formatted PDF fragments`() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.writeImage(named: "image.png")

        let document = SwiftMarkdownParser().parse("**Before ![Image](assets/image.png) After**")
        guard case let .paragraph(_, inlines) = document.blocks.first else {
            Issue.record("Expected a formatted image paragraph")
            return
        }

        let style = MarkdownStyle.notra(previewFontName: AppearanceFont.defaultName)
        let renderData = MarkdownAttributedStringBuilder(
            style: style,
            context: .textBundle(noteURL: fixture.bundleURL)
        ).renderData(for: inlines)
        let fragments = renderData.pdfFragments.map { fragment in
            switch fragment.content {
            case let .text(text):
                String(text.characters)
            case .image:
                "<image>"
            }
        }

        #expect(renderData.pdfFragments.map(\.id) == [0, 1, 2])
        #expect(Set(renderData.pdfFragments.map(\.id)).count == renderData.pdfFragments.count)
        #expect(fragments == ["Before ", "<image>", " After"])
    }

    @Test
    func `coalesces mixed PDF text while preserving attributed runs`() {
        let document = SwiftMarkdownParser().parse("Normal **bold** *italic* [link](https://example.com)")
        guard case let .paragraph(_, inlines) = document.blocks.first else {
            Issue.record("Expected a mixed-format paragraph")
            return
        }

        let style = MarkdownStyle.notra(previewFontName: AppearanceFont.defaultName)
        let renderData = MarkdownAttributedStringBuilder(style: style, context: .empty)
            .renderData(for: inlines)
        let fragments = MarkdownPDFInlineFragment.coalesced(renderData.pdfFragments)
        guard case let .text(text) = fragments.first?.content else {
            Issue.record("Expected coalesced PDF text")
            return
        }

        #expect(fragments.count == 1)
        #expect(String(text.characters) == "Normal bold italic link")
        #expect(text.runs.contains { $0.inlinePresentationIntent == .stronglyEmphasized })
        #expect(text.runs.contains { $0.inlinePresentationIntent == .emphasized })
        #expect(text.runs.contains { $0.link == URL(string: "https://example.com") })
    }

    @Test
    func `applies inline presentation intents to PDF text`() {
        let document = SwiftMarkdownParser().parse("**bold** *italic* ~~strike~~")
        guard case let .paragraph(_, inlines) = document.blocks.first else {
            Issue.record("Expected a formatted paragraph")
            return
        }

        let style = MarkdownStyle.notra(previewFontName: AppearanceFont.defaultName)
        let renderData = MarkdownAttributedStringBuilder(
            style: style,
            context: .empty
        ).renderData(for: inlines)
        let intents = renderData.pdfText.runs.compactMap(\.inlinePresentationIntent)

        #expect(intents.contains(.stronglyEmphasized))
        #expect(intents.contains(.emphasized))
        #expect(intents.contains(.strikethrough))
    }

    @Test
    func `sanitizes suggested filenames`() {
        #expect(NotePDFExporter.sanitizedFilename("Project: Notes?.textbundle") == "Project- Notes.pdf")
        #expect(NotePDFExporter.sanitizedFilename("   ") == "Note.pdf")
        #expect(NotePDFExporter.sanitizedFilename("already.pdf") == "already.pdf")
    }

    @Test
    func `exports current unsaved editor snapshot`() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let item = try fixture.export(markdown: "Unsaved editor text")
        defer { removeExport(item) }

        let document = try #require(PDFDocument(url: item.fileURL))
        #expect(document.string?.contains("Unsaved editor text") == true)
    }

    private func removeExport(_ item: NotePDFShareItem) {
        try? FileManager.default.removeItem(at: item.fileURL.deletingLastPathComponent())
    }

    private func rasterize(page: CGPDFPage) -> (blackY: Double, grayY: Double)? {
        let scale = 2
        let width = Int(NotePDFExporter.pageSize.width) * scale
        let height = Int(NotePDFExporter.pageSize.height) * scale
        let bytesPerRow = width * 4
        let data = NSMutableData(length: bytesPerRow * height)!
        guard let context = CGContext(
            data: data.mutableBytes,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.noneSkipLast.rawValue
        ) else {
            return nil
        }

        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
        context.drawPDFPage(page)

        let pixels = data.bytes.assumingMemoryBound(to: UInt8.self)
        var blackTotalY = 0.0
        var blackCount = 0.0
        var grayTotalY = 0.0
        var grayCount = 0.0
        for y in 0..<height {
            for x in 0..<width {
                let offset = y * bytesPerRow + x * 4
                let first = pixels[offset]
                let second = pixels[offset + 1]
                let third = pixels[offset + 2]
                if first < 20, second < 20, third < 20 {
                    blackTotalY += Double(y)
                    blackCount += 1
                } else if (80...180).contains(first),
                          (80...180).contains(second),
                          (80...180).contains(third)
                {
                    grayTotalY += Double(y)
                    grayCount += 1
                }
            }
        }
        guard blackCount > 0, grayCount > 0 else {
            return nil
        }
        return (blackTotalY / blackCount, grayTotalY / grayCount)
    }
}

private struct Fixture {
    let bundleURL: URL
    let assetsURL: URL

    init() throws {
        bundleURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotraPDFExporterTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("Test Note.textbundle", isDirectory: true)
        assetsURL = bundleURL.appendingPathComponent(TextBundleNoteRepository.assetsFolder, isDirectory: true)
        try FileManager.default.createDirectory(at: assetsURL, withIntermediateDirectories: true)
    }

    func export(markdown: String) throws -> NotePDFShareItem {
        try NotePDFExporter().export(
            snapshot: NotePDFSnapshot(
                markdown: markdown,
                noteURL: bundleURL,
                previewFontName: AppearanceFont.defaultName,
                previewUsesEditorTheme: false,
                isDarkMode: false,
                suggestedFilename: bundleURL.lastPathComponent
            )
        )
    }

    func writeImage(named name: String) throws {
        let data = try #require(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="))
        try writeAsset(named: name, data: data)
    }

    func writeOrientationMarker(named name: String) throws {
        let width = 40
        let height = 20
        let context = try #require(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(gray: 0.5, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: height / 2, width: width, height: height / 2))
        let image = try #require(context.makeImage())
        let destination = try #require(CGImageDestinationCreateWithURL(
            assetURL(named: name) as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
    }

    func writeAsset(named name: String, data: Data) throws {
        try data.write(to: assetURL(named: name))
    }

    func assetURL(named name: String) -> URL {
        assetsURL.appendingPathComponent(name)
    }

    func remove() {
        try? FileManager.default.removeItem(at: bundleURL.deletingLastPathComponent())
    }
}
