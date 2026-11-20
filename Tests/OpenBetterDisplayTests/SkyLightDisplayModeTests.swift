import Foundation
import XCTest
@testable import OpenBetterDisplayCore

final class SkyLightDisplayModeTests: XCTestCase {
    func testParsesSkyLightHiDPIModeDescriptionWithFixedPointRefreshRateAndNativeFlag() {
        var bytes = [UInt8](repeating: 0, count: Int(SkyLightDisplayModeDescription.byteLength))
        writeInt32LE(54, into: &bytes, offset: 0x00)          // modeNumber
        writeUInt32LE(0x0200_0007, into: &bytes, offset: 0x04) // flags (native + valid + safe + default)
        writeUInt32LE(1512, into: &bytes, offset: 0x08)        // width
        writeUInt32LE(982, into: &bytes, offset: 0x0C)         // height
        writeUInt32LE(8, into: &bytes, offset: 0x10)           // depth
        writeUInt32LE(120, into: &bytes, offset: 0x24)         // integer freq
        writeUInt32LE(120 << 16, into: &bytes, offset: 0xBC)   // fixed 16.16 Hz = 120.0
        writeUInt32LE(0x0200_0007, into: &bytes, offset: 0xC0) // ioFlags
        writeInt32LE(54, into: &bytes, offset: 0xC4)           // ioDisplayModeID
        writeUInt32LE(3024, into: &bytes, offset: 0xC8)        // pixelsWide
        writeUInt32LE(1964, into: &bytes, offset: 0xCC)        // pixelsHigh
        writeUInt32LE(Float(2.0).bitPattern, into: &bytes, offset: 0xD0)

        let parsed = SkyLightDisplayModeDescription.parse(bytes: bytes)
        XCTAssertEqual(parsed?.modeID, 54)
        XCTAssertEqual(parsed?.width, 1512)
        XCTAssertEqual(parsed?.height, 982)
        XCTAssertEqual(parsed?.pixelWidth, 3024)
        XCTAssertEqual(parsed?.pixelHeight, 1964)
        XCTAssertEqual(parsed?.refreshRate ?? -1, 120.0, accuracy: 0.001)
        XCTAssertEqual(parsed?.isUsableForDesktopGUI, true)
        XCTAssertEqual(parsed?.isNative, true)
    }

    func testMarksUnsafeOrLowResSkyLightModesAsNotUsableForDesktopGUI() {
        var bytes = [UInt8](repeating: 0, count: Int(SkyLightDisplayModeDescription.byteLength))
        writeInt32LE(99, into: &bytes, offset: 0x00)
        writeUInt32LE(0x4000_0000, into: &bytes, offset: 0x04) // unsafe/stretched flag
        writeUInt32LE(1600, into: &bytes, offset: 0x08)
        writeUInt32LE(1200, into: &bytes, offset: 0x0C)
        writeUInt32LE(8, into: &bytes, offset: 0x10)
        writeUInt32LE(60, into: &bytes, offset: 0x24)
        writeUInt32LE(0x0000_0001, into: &bytes, offset: 0xC0) // valid only, not safe
        writeInt32LE(99, into: &bytes, offset: 0xC4)
        writeUInt32LE(1600, into: &bytes, offset: 0xC8)
        writeUInt32LE(1200, into: &bytes, offset: 0xCC)
        writeUInt32LE(Float(1.0).bitPattern, into: &bytes, offset: 0xD0)

        let parsed = SkyLightDisplayModeDescription.parse(bytes: bytes)
        XCTAssertEqual(parsed?.modeID, 99)
        XCTAssertEqual(parsed?.refreshRate ?? -1, 60.0, accuracy: 0.001)
        XCTAssertEqual(parsed?.isUsableForDesktopGUI, false)
        XCTAssertEqual(parsed?.isNative, false)
    }

    func testRejectsTruncatedSkyLightModeDescriptionBuffer() {
        XCTAssertNil(SkyLightDisplayModeDescription.parse(bytes: [UInt8](repeating: 0, count: 64)))
    }

    private func writeUInt32LE(_ value: UInt32, into bytes: inout [UInt8], offset: Int) {
        bytes[offset] = UInt8(value & 0xFF)
        bytes[offset + 1] = UInt8((value >> 8) & 0xFF)
        bytes[offset + 2] = UInt8((value >> 16) & 0xFF)
        bytes[offset + 3] = UInt8((value >> 24) & 0xFF)
    }

    private func writeInt32LE(_ value: Int32, into bytes: inout [UInt8], offset: Int) {
        writeUInt32LE(UInt32(bitPattern: value), into: &bytes, offset: offset)
    }
}
