//
//  GeoidModel.swift
//  MFKGeoMeasure
//
//  Created by Szamosi Attila on 2025. 10. 19..
//

import Foundation
import CoreGraphics
import ImageIO

class GeoidModel {
    private var grid: [[Float]]?
    private var bounds: (minLat: Double, maxLat: Double, minLon: Double, maxLon: Double)
    private var gridWidth: Int = 0
    private var gridHeight: Int = 0
    private let noDataValue: Float = -88.8888 // From metadata
    
    init() {
        // Bounds from metadata (EPSG:4326)
        bounds = (minLat: 45.551, maxLat: 48.899, minLon: 16.087, maxLon: 23.055)
        
        // Load GeoTIFF from bundle
        if let url = Bundle.main.url(forResource: "geoid_eht2014", withExtension: "tif") {
            loadGeoTIFF(from: url)
        } else {
            print("Error: geoid_eht2014.tif not found in bundle")
        }
    }
    
    private func loadGeoTIFF(from url: URL) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] else {
            print("Failed to load GeoTIFF")
            return
        }
        
        gridWidth = image.width // 268
        gridHeight = image.height // 186
        
        // Read pixel data (single band, Float32)
        let bytesPerPixel = 4 // Float32
        let bytesPerRow = bytesPerPixel * gridWidth
        let totalBytes = bytesPerRow * gridHeight
        
        guard let dataProvider = image.dataProvider,
              let pixelData = dataProvider.data as Data? else { // Changed from CGDataProviderCopyData
            print("Invalid GeoTIFF data")
            return
        }
        
        // Initialize grid
        grid = [[Float]](repeating: [Float](repeating: 0, count: gridWidth), count: gridHeight)
        
        // Parse float values using UnsafeRawBufferPointer
        pixelData.withUnsafeBytes { rawBuffer in
            let buffer = rawBuffer.bindMemory(to: Float.self)
            for y in 0..<gridHeight {
                for x in 0..<gridWidth {
                    let index = y * gridWidth + x
                    let floatValue = buffer[index]
                    grid?[y][x] = floatValue == noDataValue ? noDataValue : floatValue
                }
            }
        }
        
        // Log metadata for debugging
        if let tiffProps = properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any] {
            print("GeoTIFF metadata: \(tiffProps)")
        }
    }
    
    func value(atLatitude lat: Double, longitude lon: Double) -> Double {
        guard let grid = grid, !grid.isEmpty, gridWidth > 0, gridHeight > 0 else {
            print("Grid not loaded, using default N value")
            return 48.3 // Placeholder
        }
        
        // Normalize coordinates to grid indices
        let xRatio = (lon - bounds.minLon) / (bounds.maxLon - bounds.minLon)
        let yRatio = (lat - bounds.minLat) / (bounds.maxLat - bounds.minLat)
        
        let x = xRatio * Double(gridWidth - 1)
        let y = yRatio * Double(gridHeight - 1)
        
        // Ensure within bounds
        guard x >= 0, x < Double(gridWidth), y >= 0, y < Double(gridHeight) else {
            print("Coordinates out of bounds: (\(lat), \(lon))")
            return 48.3 // Out of bounds
        }
        
        // Bilinear interpolation
        let x0 = Int(floor(x))
        let x1 = min(x0 + 1, gridWidth - 1)
        let y0 = Int(floor(y))
        let y1 = min(y0 + 1, gridHeight - 1)
        
        let q00 = grid[y0][x0]
        let q01 = grid[y0][x1]
        let q10 = grid[y1][x0]
        let q11 = grid[y1][x1]
        
        // Check for NoData values
        guard q00 != noDataValue, q01 != noDataValue, q10 != noDataValue, q11 != noDataValue else {
            print("NoData value encountered at (\(lat), \(lon))")
            return 48.3 // Return default if NoData
        }
        
        let tx = Float(x - Double(x0))
        let ty = Float(y - Double(y0))
        
        let interpolated = q00 * (1 - tx) * (1 - ty) +
                          q01 * tx * (1 - ty) +
                          q10 * (1 - tx) * ty +
                          q11 * tx * ty
        
        return Double(interpolated)
    }
}
