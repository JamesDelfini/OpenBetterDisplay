import Foundation
import XCTest

@testable import OpenBetterDisplayCore

final class SkyLightDisplayModeTests: XCTestCase {
    func testParsesSkyLightHiDPIModeDescriptionWithFixedPointRefreshRateAndNativeFlag() {
        var bytes = [UInt8](repeating: 0, count: Int(SkyLightDisplayModeDescription.byteLength))
        writeInt32LE(54, into: &bytes, offset: 0x00) // modeNumber
        writeUInt32LE(0x0200_0007, into: &bytes, offset: 0x04) // flags (native + valid + safe + default)
        writeUInt32LE(1512, into: &bytes, offset: 0x08) // width
        writeUInt32LE(982, into: &bytes, offset: 0x0C) // height
        writeUInt32LE(8, into: &bytes, offset: 0x10) // depth
        writeUInt32LE(120, into: &bytes, offset: 0x24) // integer freq
        writeUInt32LE(120 << 16, into: &bytes, offset: 0xBC) // fixed 16.16 Hz = 120.0
        writeUInt32LE(0x0200_0007, into: &bytes, offset: 0xC0) // ioFlags
        writeInt32LE(54, into: &bytes, offset: 0xC4) // ioDisplayModeID
        writeUInt32LE(3024, into: &bytes, offset: 0xC8) // pixelsWide
        writeUInt32LE(1964, into: &bytes, offset: 0xCC) // pixelsHigh
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
        XCTAssertEqual(parsed?.isDefault, true)
        XCTAssertEqual(parsed?.isStretched, false)
        XCTAssertEqual(parsed?.bitsPerSample, 8)
    }

    func testExtracts10BitDepthFromBitsPerSampleFieldDespiteDepth8() {
        var bytes = makeValidModeBuffer(
            modeID: 646,
            flags: 0x0200_0007,
            ioFlags: 0x0200_0007,
            width: 1920,
            height: 1080,
            pixelWidth: 3840,
            pixelHeight: 2160,
            refreshRateFixed: 120 << 16
        )
        writeUInt32LE(8, into: &bytes, offset: 0x10) // depth is 8 even on 10-bit modes
        writeUInt32LE(10, into: &bytes, offset: 0x1C) // bitsPerSample
        writeASCII("--RRRRRRRRRRGGGGGGGGGGBBBBBBBBBB", into: &bytes, offset: 0x30)

        let parsed = SkyLightDisplayModeDescription.parse(bytes: bytes)
        XCTAssertEqual(parsed?.bitsPerSample, 10)
        XCTAssertEqual(parsed?.isDefault, true)
        XCTAssertEqual(parsed?.isNative, true)
        XCTAssertEqual(parsed?.isStretched, false)
        XCTAssertEqual(parsed?.isUsableForDesktopGUI, true)
    }

    func testFallsBackToPixelEncodingStringWhenBitsPerSampleOffsetIsZero() {
        var bytes = makeValidModeBuffer(
            modeID: 12,
            flags: 0x0000_0003,
            ioFlags: 0x0000_0003,
            width: 2560,
            height: 1440,
            pixelWidth: 5120,
            pixelHeight: 2880,
            refreshRateFixed: 60 << 16
        )
        writeUInt32LE(0, into: &bytes, offset: 0x1C)
        writeASCII("--RRRRRRRRRRGGGGGGGGGGBBBBBBBBBB", into: &bytes, offset: 0x30)

        let parsedTenBit = SkyLightDisplayModeDescription.parse(bytes: bytes)
        XCTAssertEqual(parsedTenBit?.bitsPerSample, 10)

        writeASCII("--------RRRRRRRRGGGGGGGGBBBBBBBB", into: &bytes, offset: 0x30)
        let parsedEightBit = SkyLightDisplayModeDescription.parse(bytes: bytes)
        XCTAssertEqual(parsedEightBit?.bitsPerSample, 8)
        XCTAssertEqual(parsedEightBit?.isDefault, false)
    }

    func testMarksStretchedAndSub720pModesAsNotUsableForDesktopGUI() {
        let stretchedBytes = makeValidModeBuffer(
            modeID: 40,
            flags: 0x0000_0803,
            ioFlags: 0x0000_0803,
            width: 1920,
            height: 1080,
            pixelWidth: 1920,
            pixelHeight: 1080,
            refreshRateFixed: 60 << 16
        )
        let stretched = SkyLightDisplayModeDescription.parse(bytes: stretchedBytes)
        XCTAssertEqual(stretched?.isStretched, true)
        XCTAssertEqual(stretched?.isUsableForDesktopGUI, false)

        let sub720Bytes = makeValidModeBuffer(
            modeID: 41,
            flags: 0x0000_0003,
            ioFlags: 0x0000_0003,
            width: 1024,
            height: 665,
            pixelWidth: 2048,
            pixelHeight: 1330,
            refreshRateFixed: 60 << 16
        )
        let sub720 = SkyLightDisplayModeDescription.parse(bytes: sub720Bytes)
        XCTAssertEqual(sub720?.isUsableForDesktopGUI, false)

        let exact720Bytes = makeValidModeBuffer(
            modeID: 42,
            flags: 0x0000_0003,
            ioFlags: 0x0000_0003,
            width: 1280,
            height: 720,
            pixelWidth: 1280,
            pixelHeight: 720,
            refreshRateFixed: 60 << 16
        )
        let exact720 = SkyLightDisplayModeDescription.parse(bytes: exact720Bytes)
        XCTAssertEqual(exact720?.isUsableForDesktopGUI, true)
    }

    func testMergingSkyLightModesPreservesBitsPerSampleDefaultNativeStretchedAndSafetyFlags() {
        let cgModes: [RawDisplayMode] = [
            RawDisplayMode(
                modeID: 646,
                width: 1920,
                height: 1080,
                pixelWidth: 3840,
                pixelHeight: 2160,
                refreshRate: 120.0,
                isUsableForDesktopGUI: true,
                isNative: false,
                bitsPerSample: 8,
                isDefault: false,
                isStretched: false
            ),
            RawDisplayMode(
                modeID: 71,
                width: 1600,
                height: 1200,
                pixelWidth: 1600,
                pixelHeight: 1200,
                refreshRate: 60.0,
                isUsableForDesktopGUI: true,
                isNative: false,
                bitsPerSample: 8,
                isDefault: false,
                isStretched: false
            )
        ]

        let skyLightModes: [RawDisplayMode] = [
            RawDisplayMode(
                modeID: 646,
                width: 1920,
                height: 1080,
                pixelWidth: 3840,
                pixelHeight: 2160,
                refreshRate: 120.0,
                isUsableForDesktopGUI: true,
                isNative: true,
                bitsPerSample: 10,
                isDefault: true,
                isStretched: false
            ),
            RawDisplayMode(
                modeID: 71,
                width: 1600,
                height: 1200,
                pixelWidth: 1600,
                pixelHeight: 1200,
                refreshRate: 60.0,
                isUsableForDesktopGUI: false,
                isNative: false,
                bitsPerSample: 10,
                isDefault: false,
                isStretched: true
            ),
            RawDisplayMode(
                modeID: 900,
                width: 1280,
                height: 960,
                pixelWidth: 2560,
                pixelHeight: 1920,
                refreshRate: 60.0,
                isUsableForDesktopGUI: true,
                isNative: false,
                bitsPerSample: 10,
                isDefault: false,
                isStretched: false
            )
        ]

        let merged = MacOSDisplayDriver.mergeDisplayModes(cgModes: cgModes, skyLightModes: skyLightModes)
        // Unexposed SkyLight-only mode 900 must not be injected when CoreGraphics exposed modes exist.
        XCTAssertEqual(merged.map(\.modeID), [646, 71])

        XCTAssertEqual(merged[0].bitsPerSample, 10)
        XCTAssertEqual(merged[0].isDefault, true)
        XCTAssertEqual(merged[0].isNative, true)
        XCTAssertEqual(merged[0].isStretched, false)
        XCTAssertEqual(merged[0].isUsableForDesktopGUI, true)

        XCTAssertEqual(merged[1].bitsPerSample, 10)
        XCTAssertEqual(merged[1].isStretched, true)
        XCTAssertEqual(merged[1].isUsableForDesktopGUI, false)
    }

    func testSkyLightFallbackWhenCGModesEmptyExcludesMirroringOnlyModes() throws {
        let normalFallback = try XCTUnwrap(
            SkyLightDisplayModeDescription.parse(
                bytes: makeValidModeBuffer(
                    modeID: 32,
                    flags: 0x0200_0007,
                    ioFlags: 0x0200_0007,
                    width: 1920,
                    height: 1080,
                    pixelWidth: 1920,
                    pixelHeight: 1080,
                    refreshRateFixed: 60 << 16
                )
            )
        )
        let mirroringOnly = try XCTUnwrap(
            SkyLightDisplayModeDescription.parse(
                bytes: makeValidModeBuffer(
                    modeID: 48,
                    flags: 0x0020_0001,
                    ioFlags: 0x0020_0003,
                    width: 1920,
                    height: 1080,
                    pixelWidth: 3840,
                    pixelHeight: 2160,
                    refreshRateFixed: 75 << 16
                )
            )
        )

        XCTAssertFalse(normalFallback.isMirroringOnly)
        XCTAssertTrue(mirroringOnly.isMirroringOnly)

        let mergedFallback = MacOSDisplayDriver.mergeDisplayModes(
            cgModes: [],
            skyLightModes: [normalFallback, mirroringOnly]
        )
        XCTAssertEqual(mergedFallback.map(\.modeID), [32])
        XCTAssertFalse(MacOSDisplayDriver.shouldFallbackToSkyLightModeConfiguration(catalogModeCount: 10, matchedCatalogMode: false))
        XCTAssertTrue(MacOSDisplayDriver.shouldFallbackToSkyLightModeConfiguration(catalogModeCount: 10, matchedCatalogMode: true))
        XCTAssertTrue(MacOSDisplayDriver.shouldFallbackToSkyLightModeConfiguration(catalogModeCount: 0, matchedCatalogMode: false))
    }

    func testMergeDisplayModesExcludesUnexposedSkyLightMirroringAndOutOfPanelModesWhenCGModesExist() throws {
        let p2217hCGModes: [RawDisplayMode] = [
            RawDisplayMode(
                modeID: 32,
                width: 1920,
                height: 1080,
                pixelWidth: 1920,
                pixelHeight: 1080,
                refreshRate: 60.0,
                isUsableForDesktopGUI: true,
                isNative: true,
                bitsPerSample: 8,
                isDefault: true
            ),
            RawDisplayMode(
                modeID: 33,
                width: 1920,
                height: 1080,
                pixelWidth: 1920,
                pixelHeight: 1080,
                refreshRate: 50.0,
                isUsableForDesktopGUI: true,
                isNative: true,
                bitsPerSample: 8
            ),
            RawDisplayMode(
                modeID: 49,
                width: 1920,
                height: 1080,
                pixelWidth: 3840,
                pixelHeight: 2160,
                refreshRate: 60.0,
                isUsableForDesktopGUI: true,
                isNative: false,
                bitsPerSample: 8
            ),
            RawDisplayMode(
                modeID: 21,
                width: 1280,
                height: 1024,
                pixelWidth: 1280,
                pixelHeight: 1024,
                refreshRate: 75.0,
                isUsableForDesktopGUI: true,
                isNative: false,
                bitsPerSample: 8
            )
        ]

        let mirror75Hz = try XCTUnwrap(
            SkyLightDisplayModeDescription.parse(
                bytes: makeValidModeBuffer(
                    modeID: 48,
                    flags: 0x0020_0001,
                    ioFlags: 0x0020_0003,
                    width: 1920,
                    height: 1080,
                    pixelWidth: 3840,
                    pixelHeight: 2160,
                    refreshRateFixed: 75 << 16
                )
            )
        )
        let mirror60Hz = try XCTUnwrap(
            SkyLightDisplayModeDescription.parse(
                bytes: makeValidModeBuffer(
                    modeID: 49,
                    flags: 0x0020_0001,
                    ioFlags: 0x0020_0003,
                    width: 1920,
                    height: 1080,
                    pixelWidth: 3840,
                    pixelHeight: 2160,
                    refreshRateFixed: 60 << 16
                )
            )
        )
        let mirror50Hz = try XCTUnwrap(
            SkyLightDisplayModeDescription.parse(
                bytes: makeValidModeBuffer(
                    modeID: 50,
                    flags: 0x0020_0001,
                    ioFlags: 0x0020_0003,
                    width: 1920,
                    height: 1080,
                    pixelWidth: 3840,
                    pixelHeight: 2160,
                    refreshRateFixed: 50 << 16
                )
            )
        )
        let outOfPanel1600x1200 = try XCTUnwrap(
            SkyLightDisplayModeDescription.parse(
                bytes: makeValidModeBuffer(
                    modeID: 29,
                    flags: 0x0000_0001,
                    ioFlags: 0x0000_0003,
                    width: 1600,
                    height: 1200,
                    pixelWidth: 1600,
                    pixelHeight: 1200,
                    refreshRateFixed: 60 << 16
                )
            )
        )
        var tenBitNative60Bytes = makeValidModeBuffer(
            modeID: 32,
            flags: 0x0200_0007,
            ioFlags: 0x0200_0007,
            width: 1920,
            height: 1080,
            pixelWidth: 1920,
            pixelHeight: 1080,
            refreshRateFixed: 60 << 16
        )
        writeUInt32LE(10, into: &tenBitNative60Bytes, offset: 0x1C)
        let tenBitNative60 = try XCTUnwrap(SkyLightDisplayModeDescription.parse(bytes: tenBitNative60Bytes))

        var mirror49Bytes = makeValidModeBuffer(
            modeID: 49,
            flags: 0x0020_0001,
            ioFlags: 0x0020_0003,
            width: 1920,
            height: 1080,
            pixelWidth: 3840,
            pixelHeight: 2160,
            refreshRateFixed: 60 << 16
        )
        writeUInt32LE(10, into: &mirror49Bytes, offset: 0x1C)
        let tenBitMirror49 = try XCTUnwrap(SkyLightDisplayModeDescription.parse(bytes: mirror49Bytes))
        _ = mirror60Hz

        let merged = MacOSDisplayDriver.mergeDisplayModes(
            cgModes: p2217hCGModes,
            skyLightModes: [tenBitNative60, outOfPanel1600x1200, mirror75Hz, tenBitMirror49, mirror50Hz]
        )

        XCTAssertEqual(merged.map(\.modeID), [32, 33, 49, 21])
        XCTAssertEqual(merged.first(where: { $0.modeID == 32 })?.bitsPerSample, 10)
        // modeID 49 is in CGDisplayCopyAllDisplayModes even with 0x0020_0000 and must remain usable.
        let preservedHiDPI60 = merged.first(where: { $0.modeID == 49 })
        XCTAssertEqual(preservedHiDPI60?.isUsableForDesktopGUI, true)
        XCTAssertEqual(preservedHiDPI60?.bitsPerSample, 10)
        // Unexposed 75 Hz HiDPI, 50 Hz HiDPI, and 1600x1200 must never leak into the desktop catalog.
        XCTAssertFalse(merged.contains(where: { $0.modeID == 48 || $0.modeID == 50 || $0.modeID == 29 }))
    }

    func testMergingSkyLightModesPreservesVariableRefreshRateAndMinRefreshRate() {
        let cgModes: [RawDisplayMode] = [
            RawDisplayMode(
                modeID: 928,
                width: 2560,
                height: 1440,
                pixelWidth: 5120,
                pixelHeight: 2880,
                refreshRate: 120.0,
                bitsPerSample: 8
            ),
            RawDisplayMode(
                modeID: 54,
                width: 1512,
                height: 982,
                pixelWidth: 3024,
                pixelHeight: 1964,
                refreshRate: 120.0,
                bitsPerSample: 8
            )
        ]

        let skyLightModes: [RawDisplayMode] = [
            RawDisplayMode(
                modeID: 928,
                width: 2560,
                height: 1440,
                pixelWidth: 5120,
                pixelHeight: 2880,
                refreshRate: 120.0,
                bitsPerSample: 10,
                isVariableRefreshRate: true,
                minRefreshRate: 48.0
            ),
            RawDisplayMode(
                modeID: 54,
                width: 1512,
                height: 982,
                pixelWidth: 3024,
                pixelHeight: 1964,
                refreshRate: 120.0,
                isNative: true,
                bitsPerSample: 10,
                isDefault: true,
                isVariableRefreshRate: true,
                isProMotion: true,
                minRefreshRate: 24.0
            )
        ]

        let merged = MacOSDisplayDriver.mergeDisplayModes(cgModes: cgModes, skyLightModes: skyLightModes)
        XCTAssertEqual(merged.count, 2)

        XCTAssertEqual(merged[0].isVariableRefreshRate, true)
        XCTAssertEqual(merged[0].isProMotion, false)
        XCTAssertEqual(merged[0].minRefreshRate ?? -1, 48.0, accuracy: 0.001)

        XCTAssertEqual(merged[1].isVariableRefreshRate, true)
        XCTAssertEqual(merged[1].isProMotion, true)
        XCTAssertEqual(merged[1].minRefreshRate ?? -1, 24.0, accuracy: 0.001)
    }

    func testResolvesVariableRefreshRateMinRefreshRateWithActiveScreenFallbackAnd24HzFloor() {
        // External Variable Refresh Rate mode (e.g. 48-120Hz) uses SkyLight minHz directly and is not ProMotion
        let externalVariableRate = MacOSDisplayDriver.resolveVariableRefreshRateMetadata(
            isVariableRefreshRate: true,
            usesAdaptiveFloorFallback: false,
            reportedMinRefreshRate: 48.0,
            maxRefreshRate: 120.0,
            isCurrentMode: false,
            activeScreenMaxRefreshInterval: nil
        )
        XCTAssertEqual(externalVariableRate.isVariableRefreshRate, true)
        XCTAssertEqual(externalVariableRate.isProMotion, false)
        XCTAssertEqual(externalVariableRate.minRefreshRate ?? -1, 48.0, accuracy: 0.001)

        // Active adaptive mode where SkyLight returns minHz == maxHz (120.0) derives 24Hz via NSScreen.maximumRefreshInterval
        let activeBuiltInAdaptive = MacOSDisplayDriver.resolveVariableRefreshRateMetadata(
            isVariableRefreshRate: true,
            usesAdaptiveFloorFallback: true,
            reportedMinRefreshRate: 120.0,
            maxRefreshRate: 120.0,
            isCurrentMode: true,
            activeScreenMaxRefreshInterval: 1.0 / 24.0
        )
        XCTAssertEqual(activeBuiltInAdaptive.isVariableRefreshRate, true)
        XCTAssertEqual(activeBuiltInAdaptive.isProMotion, true)
        XCTAssertEqual(activeBuiltInAdaptive.minRefreshRate ?? -1, 24.0, accuracy: 0.001)

        // Inactive Variable Refresh Rate mode ignores active NSScreen interval (which might be 60Hz) and falls back to 24Hz floor
        let inactiveBuiltInAdaptive = MacOSDisplayDriver.resolveVariableRefreshRateMetadata(
            isVariableRefreshRate: true,
            usesAdaptiveFloorFallback: true,
            reportedMinRefreshRate: 120.0,
            maxRefreshRate: 120.0,
            isCurrentMode: false,
            activeScreenMaxRefreshInterval: 1.0 / 60.0
        )
        XCTAssertEqual(inactiveBuiltInAdaptive.isVariableRefreshRate, true)
        XCTAssertEqual(inactiveBuiltInAdaptive.isProMotion, true)
        XCTAssertEqual(inactiveBuiltInAdaptive.minRefreshRate ?? -1, 24.0, accuracy: 0.001)

        // Fixed mode stays non-Variable Refresh Rate with nil minRefreshRate
        let fixedMode = MacOSDisplayDriver.resolveVariableRefreshRateMetadata(
            isVariableRefreshRate: false,
            usesAdaptiveFloorFallback: false,
            reportedMinRefreshRate: 60.0,
            maxRefreshRate: 60.0,
            isCurrentMode: true,
            activeScreenMaxRefreshInterval: 1.0 / 60.0
        )
        XCTAssertEqual(fixedMode.isVariableRefreshRate, false)
        XCTAssertEqual(fixedMode.isProMotion, false)
        XCTAssertNil(fixedMode.minRefreshRate)
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

        let ioUnsafeBytes = makeValidModeBuffer(
            modeID: 100,
            flags: 0x0000_0003,
            ioFlags: 0x4000_0003, // unsafe bit set only in ioFlags
            width: 1920,
            height: 1080,
            pixelWidth: 1920,
            pixelHeight: 1080,
            refreshRateFixed: 60 << 16
        )
        let ioUnsafeParsed = SkyLightDisplayModeDescription.parse(bytes: ioUnsafeBytes)
        XCTAssertEqual(ioUnsafeParsed?.modeID, 100)
        XCTAssertEqual(ioUnsafeParsed?.isUsableForDesktopGUI, false)
    }

    func testRejectsTruncatedSkyLightModeDescriptionBuffer() {
        XCTAssertNil(SkyLightDisplayModeDescription.parse(bytes: [UInt8](repeating: 0, count: 64)))
    }

    private func makeValidModeBuffer(
        modeID: Int32,
        flags: UInt32,
        ioFlags: UInt32,
        width: UInt32,
        height: UInt32,
        pixelWidth: UInt32,
        pixelHeight: UInt32,
        refreshRateFixed: UInt32
    ) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: Int(SkyLightDisplayModeDescription.byteLength))
        writeInt32LE(modeID, into: &bytes, offset: 0x00)
        writeUInt32LE(flags, into: &bytes, offset: 0x04)
        writeUInt32LE(width, into: &bytes, offset: 0x08)
        writeUInt32LE(height, into: &bytes, offset: 0x0C)
        writeUInt32LE(8, into: &bytes, offset: 0x10)
        writeUInt32LE(60, into: &bytes, offset: 0x24)
        writeUInt32LE(refreshRateFixed, into: &bytes, offset: 0xBC)
        writeUInt32LE(ioFlags, into: &bytes, offset: 0xC0)
        writeInt32LE(modeID, into: &bytes, offset: 0xC4)
        writeUInt32LE(pixelWidth, into: &bytes, offset: 0xC8)
        writeUInt32LE(pixelHeight, into: &bytes, offset: 0xCC)
        let scale: Float = pixelWidth > width ? Float(pixelWidth) / Float(max(1, width)) : 1.0
        writeUInt32LE(scale.bitPattern, into: &bytes, offset: 0xD0)
        return bytes
    }

    private func writeASCII(_ text: String, into bytes: inout [UInt8], offset: Int) {
        for index in 0..<128 {
            bytes[offset + index] = 0
        }
        for (index, byte) in text.utf8.prefix(127).enumerated() {
            bytes[offset + index] = byte
        }
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
