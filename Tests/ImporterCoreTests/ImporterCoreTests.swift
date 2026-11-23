import Foundation
import XCTest
@testable import ImporterCore

final class ImporterCoreTests: XCTestCase {
    private var base: URL!
    private var source: URL { base.appendingPathComponent("Export") }
    private var destination: URL { base.appendingPathComponent("Ziel") }

    override func setUpWithError() throws {
        base = FileManager.default.temporaryDirectory
            .appendingPathComponent("ImporterCoreTests-\(UUID().uuidString)")
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: base)
    }

    private func write(_ text: String, _ path: String) throws {
        let url = source.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    private func snapshot(_ root: URL) throws -> [String: Data] {
        var out: [String: Data] = [:]
        let rootPath = root.standardizedFileURL.path
        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey])
        while let url = enumerator?.nextObject() as? URL {
            if try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
                let path = url.standardizedFileURL.path
                XCTAssertTrue(path.hasPrefix(rootPath + "/"))
                out[String(path.dropFirst(rootPath.count + 1))] = try Data(contentsOf: url)
            }
        }
        return out
    }

    private func plan() throws -> ImportPlan {
        let library = try ExportScanner.scan(root: source)
        return ImportPlan(sourceRoot: library.root, destinationRoot: destination, photos: library.photos)
    }

    private static let packet = """
    <x:xmpmeta xmlns:x="adobe:ns:meta/"><rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
    <rdf:Description rdf:about="" xmlns:xmp="http://ns.adobe.com/xap/1.0/" xmlns:dc="http://purl.org/dc/elements/1.1/"
      xmlns:lr="http://ns.adobe.com/lightroom/1.0/" xmlns:crs="http://ns.adobe.com/camera-raw-settings/1.0/"
      xmlns:exif="http://ns.adobe.com/exif/1.0/" xmlns:xmpDM="http://ns.adobe.com/xmp/1.0/DynamicMedia/"
      xmp:Rating="4" xmp:Label="Red" crs:Exposure2012="+0.50" crs:Contrast2012="0" crs:HasCrop="True"
      exif:GPSLatitude="64,8.5N" exif:GPSLongitude="21,56.0W" xmpDM:pick="1">
    <dc:title><rdf:Alt><rdf:li xml:lang="x-default">Küste</rdf:li></rdf:Alt></dc:title>
    <dc:subject><rdf:Bag><rdf:li>Island</rdf:li><rdf:li>Meer</rdf:li></rdf:Bag></dc:subject>
    <lr:hierarchicalSubject><rdf:Bag><rdf:li>Orte|Island</rdf:li></rdf:Bag></lr:hierarchicalSubject>
    </rdf:Description></rdf:RDF></x:xmpmeta>
    """

    func testParsesAttributesAndLists() throws {
        let xmp = try XMPDocument.parse(Data(Self.packet.utf8))
        XCTAssertEqual(xmp.rating, 4)
        XCTAssertEqual(xmp.value("xmp:Label"), "Red")
        XCTAssertEqual(xmp.value("dc:title"), "Küste")
        XCTAssertEqual(xmp.properties["dc:subject"], ["Island", "Meer"])
        XCTAssertEqual(xmp.value("lr:hierarchicalSubject"), "Orte|Island")
        XCTAssertTrue(xmp.hasBasicAdjustments)
        XCTAssertTrue(xmp.hasCrop)
        XCTAssertTrue(xmp.hasGPS)
        XCTAssertTrue(xmp.hasUnreadPick)
    }

    func testResolvesUnusualPrefixes() throws {
        let packet = """
        <x:xmpmeta xmlns:x="adobe:ns:meta/"><rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
        <rdf:Description xmlns:a="http://ns.adobe.com/xap/1.0/" a:Rating="-1"/></rdf:RDF></x:xmpmeta>
        """
        let xmp = try XMPDocument.parse(Data(packet.utf8))
        XCTAssertEqual(xmp.rating, -1)
        XCTAssertTrue(xmp.isRejected)
    }

    func testRefusesEntities() {
        let hostile = #"<!DOCTYPE a [<!ENTITY b "c">]><a>&b;</a>"#
        XCTAssertThrowsError(try XMPDocument.parse(Data(hostile.utf8))) {
            XCTAssertEqual($0 as? XMPError, .forbiddenDeclaration)
        }
    }

    func testSharedStemSidecarBelongsToRaw() throws {
        try write("raw", "IMG_1.CR3")
        try write("jpeg", "IMG_1.JPG")
        try write(Self.packet, "IMG_1.xmp")
        let photos = try ExportScanner.scan(root: source).photos
        XCTAssertEqual(photos.first { $0.name == "IMG_1.CR3" }?.sidecar?.lastPathComponent, "IMG_1.xmp")
        XCTAssertNil(photos.first { $0.name == "IMG_1.JPG" }?.sidecar)
    }

    func testSkipsLinksAndHiddenFiles() throws {
        try write("outside", "../draussen.jpg")
        try write("visible", "a.jpg")
        try write("hidden", ".b.jpg")
        try FileManager.default.createSymbolicLink(
            at: source.appendingPathComponent("link.jpg"),
            withDestinationURL: base.appendingPathComponent("draussen.jpg")
        )
        XCTAssertEqual(try ExportScanner.scan(root: source).photos.map(\.id), ["a.jpg"])
    }

    func testAlbumsComeFromFolders() throws {
        try write("1", "Reisen/Island/a.nef")
        try write("2", "Reisen/Island/b.nef")
        try write("3", "c.nef")
        let albums = try ExportScanner.scan(root: source).albums
        XCTAssertEqual(albums.map(\.name), ["Island", "Ohne Album"])
        XCTAssertEqual(albums.first?.group, "Reisen")
        XCTAssertEqual(albums.first?.count, 2)
    }

    func testImportCopiesWithoutTouchingSource() throws {
        try write("raw-data", "Island/a.cr3")
        try write(Self.packet, "Island/a.xmp")
        let before = try snapshot(source)
        let report = try ImportEngine.run(plan: plan())
        XCTAssertEqual(try snapshot(source), before)
        XCTAssertEqual(report.imported, 1)
        XCTAssertEqual(report.sidecarsCopied, 1)
        XCTAssertEqual(report.editsApproximated, 1)
        XCTAssertEqual(report.picksNotTransferred, ["Island/a.cr3"])
        XCTAssertEqual(report.gpsOnlyInSidecar, ["Island/a.cr3"])
        let copied = try snapshot(destination)
        XCTAssertEqual(copied["Island/a.cr3"], before["Island/a.cr3"])
        XCTAssertEqual(copied["Island/a.xmp"], before["Island/a.xmp"])
        XCTAssertFalse(copied.keys.contains { $0.hasSuffix(".partial") })
    }

    func testExtractsEmbeddedXMPForJPEGOnly() throws {
        try write("\u{1}jpeg" + Self.packet + "tail", "a.jpg")
        try write("\u{1}dng" + Self.packet + "tail", "b.dng")
        let report = try ImportEngine.run(plan: plan())
        XCTAssertEqual(report.sidecarsExtracted, 1)
        let copied = try snapshot(destination)
        XCTAssertEqual(copied["a.jpg.xmp"], Data(Self.packet.utf8))
        XCTAssertNil(copied["b.dng.xmp"])
    }

    func testDuplicatesAreSkipped() throws {
        try write("same", "A/a.jpg")
        try write("same", "B/b.jpg")
        let report = try ImportEngine.run(plan: plan())
        XCTAssertEqual(report.imported, 1)
        XCTAssertEqual(report.duplicates, ["B/b.jpg"])
    }

    func testDuplicateKeepsTheCopyWithMetadata() throws {
        try write("same", "A/kopie.jpg")
        try write("same", "B/original.jpg")
        try write(Self.packet, "B/original.xmp")
        let report = try ImportEngine.run(plan: plan())
        XCTAssertEqual(report.duplicates, ["A/kopie.jpg"])
        let copied = try snapshot(destination)
        XCTAssertNotNil(copied["B/original.jpg"])
        XCTAssertNotNil(copied["B/original.xmp"])
        XCTAssertNil(copied["A/kopie.jpg"])
    }

    func testIdenticalFilesWithDifferentMetadataAreBothKept() throws {
        try write("same", "A/a.jpg")
        try write(Self.packet, "A/a.xmp")
        try write("same", "B/b.jpg")
        try write(Self.packet.replacingOccurrences(of: "Küste", with: "Hafen"), "B/b.xmp")
        let report = try ImportEngine.run(plan: plan())
        XCTAssertTrue(report.duplicates.isEmpty)
        XCTAssertEqual(report.imported, 2)
        XCTAssertEqual(report.sidecarsCopied, 2)
    }

    func testSecondRunRecognisesFinishedFiles() throws {
        try write("one", "a.jpg")
        try write(Self.packet, "a.xmp")
        try ImportEngine.run(plan: plan())
        let report = try ImportEngine.run(plan: plan())
        XCTAssertEqual(report.imported, 0)
        XCTAssertEqual(report.alreadyPresent, 1)
        XCTAssertEqual(report.sidecarsCopied, 0)
        XCTAssertTrue(report.sidecarConflicts.isEmpty)
    }

    func testNeverOverwritesADifferentFile() throws {
        try write("new", "a.jpg")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try Data("existing".utf8).write(to: destination.appendingPathComponent("a.jpg"))
        let report = try ImportEngine.run(plan: plan())
        XCTAssertEqual(report.imported, 1)
        let copied = try snapshot(destination)
        XCTAssertEqual(copied["a.jpg"], Data("existing".utf8))
        XCTAssertEqual(copied["a (2).jpg"], Data("new".utf8))
    }

    func testKeepsDifferentExistingSidecar() throws {
        try write("photo", "a.cr3")
        try write(Self.packet, "a.xmp")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try Data("photo".utf8).write(to: destination.appendingPathComponent("a.cr3"))
        try Data("mine".utf8).write(to: destination.appendingPathComponent("a.xmp"))
        let report = try ImportEngine.run(plan: plan())
        XCTAssertEqual(report.sidecarConflicts, ["a.cr3"])
        XCTAssertEqual(try snapshot(destination)["a.xmp"], Data("mine".utf8))
    }

    func testRefusesUnsafeDestinations() throws {
        XCTAssertThrowsError(try ImportEngine.validate(source: source, destination: source.appendingPathComponent("x"))) {
            XCTAssertEqual($0 as? ImportValidationError, .destinationInsideSource)
        }
        XCTAssertThrowsError(try ImportEngine.validate(source: source, destination: base)) {
            XCTAssertEqual($0 as? ImportValidationError, .sourceInsideDestination)
        }
        let library = base.appendingPathComponent("LightCraft Library")
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        try Data().write(to: library.appendingPathComponent("catalog.lock"))
        XCTAssertThrowsError(try ImportEngine.validate(source: source, destination: library.appendingPathComponent("Neu"))) {
            XCTAssertEqual($0 as? ImportValidationError, .destinationIsLightCraftLibrary)
        }
    }

    func testCancelLeavesNoPartialFiles() throws {
        try write(String(repeating: "x", count: 3_000_000), "a.jpg")
        let control = ImportControl()
        control.cancel()
        XCTAssertThrowsError(try ImportEngine.run(plan: plan(), control: control)) {
            XCTAssertTrue($0 is CancellationError)
        }
        XCTAssertTrue(try snapshot(destination).isEmpty)
    }

    func testFieldCatalogIsComplete() {
        XCTAssertEqual(MetadataField.groups.flatMap(\.fields).count, MetadataField.allCases.count)
        XCTAssertEqual(Set(MetadataField.groups.flatMap(\.fields)).count, MetadataField.allCases.count)
    }
}
