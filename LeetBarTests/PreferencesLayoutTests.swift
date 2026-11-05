import AppKit
import SwiftUI
import XCTest

@MainActor
final class PreferencesLayoutTests: XCTestCase {
    func testLabelsAlignLeftAndSwitchesAlignRight() async throws {
        let host = NSHostingView(
            rootView: VStack(spacing: 12) {
                PreferencesControls(
                    showStreak: .constant(true), showQuickLinks: .constant(true),
                    showUpcomingContests: .constant(true), showTodaySection: .constant(true),
                    showStudyPlans: .constant(true))
            }
            .toggleStyle(.switch)
            .foregroundStyle(.black)
            .frame(width: 360)
            .padding(20)
            .background(.white))
        host.appearance = NSAppearance(named: .aqua)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: host.fittingSize),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)

        var switchRows: [ClosedRange<Int>] = []
        var rightEdges: [Int] = []
        for y in 0..<bitmap.pixelsHigh {
            let switchPixels = ((bitmap.pixelsWide * 3 / 4)..<bitmap.pixelsWide).filter { x in
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { return false }
                return color.alphaComponent > 0.8 && color.redComponent < 0.95
                    && color.greenComponent < 0.95 && color.blueComponent < 0.95
            }
            guard let right = switchPixels.last else { continue }
            if let last = switchRows.last, last.upperBound == y - 1 {
                switchRows[switchRows.count - 1] = last.lowerBound...y
                rightEdges[rightEdges.count - 1] = max(rightEdges.last ?? 0, right)
            } else {
                switchRows.append(y...y)
                rightEdges.append(right)
            }
        }
        XCTAssertEqual(switchRows.count, 5)
        let expectedRight = try XCTUnwrap(rightEdges.first)
        for right in rightEdges { XCTAssertEqual(right, expectedRight, accuracy: 1) }

        var leftEdges: [Int] = []
        for row in switchRows {
            let left = (0..<(bitmap.pixelsWide / 2)).first { x in
                row.contains { y in
                    guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { return false }
                    return color.alphaComponent > 0.8 && color.redComponent < 0.25
                        && color.greenComponent < 0.25 && color.blueComponent < 0.25
                }
            }
            leftEdges.append(try XCTUnwrap(left))
        }
        let expectedLeft = try XCTUnwrap(leftEdges.first)
        for left in leftEdges { XCTAssertEqual(left, expectedLeft, accuracy: 1) }
        XCTAssertGreaterThan(expectedRight - expectedLeft, 300)
    }
}
