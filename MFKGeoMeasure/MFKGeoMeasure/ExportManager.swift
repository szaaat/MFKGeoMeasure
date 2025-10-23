//
//  ExportManager.swift
//  MFKGeoMeasure
//
//  Created by Szamosi Attila on 2025. 10. 19..
//

import Foundation
import CoreLocation
import UniformTypeIdentifiers
import UIKit
import Combine

enum ExportFormat {
    case csv
    case geoJSON
    case kml
    case gpx
    case shp
    
    var fileExtension: String {
        switch self {
        case .csv: return "csv"
        case .geoJSON: return "geojson"
        case .kml: return "kml"
        case .gpx: return "gpx"
        case .shp: return "shp"
        }
    }
    
    var utType: UTType {
        switch self {
        case .csv: return .commaSeparatedText
        case .geoJSON: return .geoJSON
        case .kml: return UTType(mimeType: "application/vnd.google-earth.kml+xml") ?? .data
        case .gpx: return UTType(mimeType: "application/gpx+xml") ?? .data
        case .shp: return .data
        }
    }
    
    var displayName: String {
        switch self {
        case .csv: return "CSV"
        case .geoJSON: return "GeoJSON"
        case .kml: return "KML"
        case .gpx: return "GPX"
        case .shp: return "Shapefile"
        }
    }
}

class ExportManager: ObservableObject {
    @Published var isExporting: Bool = false
    @Published var exportProgress: Double = 0.0
    
    func exportMeasurements(_ points: [MeasurementPoint],
                            format: ExportFormat,
                            fileName: String) -> URL? {
        isExporting = true
        exportProgress = 0.0
        
        let result: URL?
        
        switch format {
        case .csv:
            result = exportToCSV(points, fileName: fileName)
        case .geoJSON:
            result = exportToGeoJSON(points, fileName: fileName)
        case .kml:
            result = exportToKML(points, fileName: fileName)
        case .gpx:
            result = exportToGPX(points, fileName: fileName)
        case .shp:
            result = exportToShapefile(points, fileName: fileName)
        }
        
        isExporting = false
        exportProgress = 1.0
        
        return result
    }
    
    private func exportToCSV(_ points: [MeasurementPoint], fileName: String) -> URL? {
        var csvString = "ID,Latitude,Longitude,Height,Timestamp,Accuracy,Mode\n"
        
        for (index, point) in points.enumerated() {
            let row = "\(point.id.uuidString),\(point.coordinate.latitude),\(point.coordinate.longitude),\(point.height),\(point.timestamp.ISO8601Format()),\(point.accuracy ?? 0),\(point.mode.rawValue)\n"
            csvString.append(row)
            exportProgress = Double(index) / Double(points.count)
        }
        
        return saveStringToFile(csvString, fileName: fileName, extension: "csv")
    }
    
    private func exportToGeoJSON(_ points: [MeasurementPoint], fileName: String) -> URL? {
        let features = points.map { point in
            GeoJSONFeature(
                type: "Feature",
                geometry: GeoJSONPointGeometry(
                    type: "Point",
                    coordinates: [point.coordinate.longitude, point.coordinate.latitude]
                ),
                properties: [
                    "id": point.id.uuidString,
                    "height": String(point.height),
                    "timestamp": point.timestamp.ISO8601Format(),
                    "accuracy": String(point.accuracy ?? 0),
                    "mode": point.mode.rawValue
                ]
            )
        }
        
        let geoJSON = GeoJSON(
            type: "FeatureCollection",
            features: features
        )
        
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(geoJSON)
            return saveDataToFile(data, fileName: fileName, extension: "geojson")
        } catch {
            print("GeoJSON export error: \(error)")
            return nil
        }
    }
    
    private func exportToKML(_ points: [MeasurementPoint], fileName: String) -> URL? {
        var kmlString = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<kml xmlns=\"http://www.opengis.net/kml/2.2\">\n<Document>\n<name>\(fileName)</name>\n<description>Exported from MFKGeoMeasure</description>\n"
        
        for (index, point) in points.enumerated() {
            kmlString += "<Placemark>\n<name>Point \(index + 1)</name>\n<description>Height: \(point.height)m\nAccuracy: \(point.accuracy ?? 0)m\nMode: \(point.mode.rawValue)\nTime: \(point.timestamp.ISO8601Format())</description>\n<Point>\n<coordinates>\(point.coordinate.longitude),\(point.coordinate.latitude),\(point.height)</coordinates>\n</Point>\n</Placemark>\n"
            exportProgress = Double(index) / Double(points.count)
        }
        
        kmlString += "</Document>\n</kml>"
        
        return saveStringToFile(kmlString, fileName: fileName, extension: "kml")
    }
    
    private func exportToGPX(_ points: [MeasurementPoint], fileName: String) -> URL? {
        var gpxString = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<gpx version=\"1.1\" creator=\"MFKGeoMeasure\">\n"
        
        for (index, point) in points.enumerated() {
            gpxString += "<wpt lat=\"\(point.coordinate.latitude)\" lon=\"\(point.coordinate.longitude)\">\n<ele>\(point.height)</ele>\n<name>Point \(index + 1)</name>\n<desc>Accuracy: \(point.accuracy ?? 0)m, Mode: \(point.mode.rawValue)</desc>\n<time>\(point.timestamp.ISO8601Format())</time>\n</wpt>\n"
            exportProgress = Double(index) / Double(points.count)
        }
        
        gpxString += "</gpx>"
        
        return saveStringToFile(gpxString, fileName: fileName, extension: "gpx")
    }
    
    private func exportToShapefile(_ points: [MeasurementPoint], fileName: String) -> URL? {
        var shpContent = "ID,WKT,Height,Timestamp,Accuracy,Mode\n"
        
        for (index, point) in points.enumerated() {
            let wkt = "POINT (\(point.coordinate.longitude) \(point.coordinate.latitude))"
            let row = "\(point.id.uuidString),\"\(wkt)\",\(point.height),\(point.timestamp.ISO8601Format()),\(point.accuracy ?? 0),\(point.mode.rawValue)\n"
            shpContent.append(row)
            exportProgress = Double(index) / Double(points.count)
        }
        
        return saveStringToFile(shpContent, fileName: fileName, extension: "csv")
    }
    
    private func saveStringToFile(_ string: String, fileName: String, extension ext: String) -> URL? {
        guard let data = string.data(using: .utf8) else { return nil }
        return saveDataToFile(data, fileName: fileName, extension: ext)
    }
    
    private func saveDataToFile(_ data: Data, fileName: String, extension ext: String) -> URL? {
        let tempDirectory = FileManager.default.temporaryDirectory
        let fileURL = tempDirectory.appendingPathComponent(fileName).appendingPathExtension(ext)
        
        do {
            try data.write(to: fileURL)
            return fileURL
        } catch {
            print("File save error: \(error)")
            return nil
        }
    }
    
    func shareFiles(_ urls: [URL]) {
        let activityVC = UIActivityViewController(activityItems: urls, applicationActivities: nil)
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            rootViewController.present(activityVC, animated: true)
        }
    }
}
