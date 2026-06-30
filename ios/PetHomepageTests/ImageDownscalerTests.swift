// ios/PetHomepageTests/ImageDownscalerTests.swift
import XCTest
import UIKit
@testable import PetHomepage

final class ImageDownscalerTests: XCTestCase {
    private func solidImage(size: CGSize) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
    }

    func testProducesNonEmptyJPEGData() {
        let data = ImageDownscaler.scaledJPEG(from: solidImage(size: CGSize(width: 200, height: 200)))
        XCTAssertNotNil(data)
        XCTAssertGreaterThan(data?.count ?? 0, 0)
        XCTAssertNotNil(UIImage(data: data!))
    }

    func testScalesDownLargeImage() {
        let data = ImageDownscaler.scaledJPEG(from: solidImage(size: CGSize(width: 4000, height: 4000)), maxDimension: 100)
        let result = UIImage(data: data!)!
        XCTAssertLessThanOrEqual(max(result.size.width, result.size.height), 200) // allow scale slack
    }
}
