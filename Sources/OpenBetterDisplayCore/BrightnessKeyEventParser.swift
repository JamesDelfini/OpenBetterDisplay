import CoreGraphics
import Foundation
import IOKit.hidsystem

public struct ParsedMediaBrightnessKey: Equatable, Sendable {
    public var keyCode: Int32
    public var isKeyDown: Bool
    public var isKeyUp: Bool
    public var event: BrightnessKeyEvent

    public init(
        keyCode: Int32,
        isKeyDown: Bool,
        isKeyUp: Bool,
        event: BrightnessKeyEvent
    ) {
        self.keyCode = keyCode
        self.isKeyDown = isKeyDown
        self.isKeyUp = isKeyUp
        self.event = event
    }
}

public enum BrightnessKeyEventParser {
    private static let keyDownState = 0x0A
    private static let keyUpState = 0x0B

    public static func parseMediaKeyData(
        data1: Int,
        isFineModifierActive: Bool,
        pointerLocation: CGPoint?
    ) -> ParsedMediaBrightnessKey? {
        let keyCode = Int32((data1 & 0xFFFF_0000) >> 16)
        let direction: BrightnessKeyDirection
        switch keyCode {
        case NX_KEYTYPE_BRIGHTNESS_UP:
            direction = .increase
        case NX_KEYTYPE_BRIGHTNESS_DOWN:
            direction = .decrease
        default:
            return nil
        }

        let keyFlags = data1 & 0x0000_FFFF
        let keyState = (keyFlags & 0xFF00) >> 8
        let isKeyDown = keyState == keyDownState
        let isKeyUp = keyState == keyUpState
        guard isKeyDown || isKeyUp else {
            return nil
        }

        let event = BrightnessKeyEvent(
            direction: direction,
            source: .mediaBrightness,
            isFine: isFineModifierActive,
            pointerLocation: pointerLocation
        )
        return ParsedMediaBrightnessKey(
            keyCode: keyCode,
            isKeyDown: isKeyDown,
            isKeyUp: isKeyUp,
            event: event
        )
    }

    public static func convertAppKitPointerToCoreGraphics(
        _ mouseLocation: CGPoint,
        mainDisplayHeight: CGFloat
    ) -> CGPoint? {
        guard mainDisplayHeight > 0 else {
            return nil
        }
        return CGPoint(x: mouseLocation.x, y: mainDisplayHeight - mouseLocation.y)
    }

    public static func resolveFunctionKeyMode(
        hidFKeyMode: Int?,
        cfPreferenceFnState: Bool?
    ) -> FunctionKeyMode {
        if let hidFKeyMode {
            switch hidFKeyMode {
            case 0:
                return .mediaKeys
            case 1:
                return .standardFunctionKeys
            default:
                break
            }
        }
        if let cfPreferenceFnState {
            return cfPreferenceFnState ? .standardFunctionKeys : .mediaKeys
        }
        return .unknown
    }
}
