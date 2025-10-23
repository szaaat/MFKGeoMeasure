//
//  MapLayerManager.swift
//  MFKGeoMeasure
//
//  Created by Szamosi Attila on 2025. 10. 19..
//

import MapKit
import CoreLocation
import UniformTypeIdentifiers
import Combine

enum ImportFileType {
    case shapefile
    case gpx
    case kml
    case geojson
    case csv
    
    var fileExtensions: [String] {
        switch self {
        case .shapefile: return ["shp", "dbf", "shx"]
        case .gpx: return ["gpx"]
        case .kml: return ["kml"]
        case .geojson: return ["geojson", "json"]
        case .csv: return ["csv"]
        }
    }
    
    var utType: UTType {
        switch self {
        case .shapefile: return .data
        case .gpx: return UTType(mimeType: "application/gpx+xml") ?? .data
        case .kml: return UTType(mimeType: "application/vnd.google-earth.kml+xml") ?? .data
        case .geojson: return .geoJSON
        case .csv: return .commaSeparatedText
        }
    }
}

class MapLayerManager: ObservableObject {
    @Published var importedLayers: [MapLayer] = []
    @Published var isImporting: Bool = false
    
    func importFile(_ url: URL) {
        isImporting = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            let fileType = self.detectFileType(from: url)
            let layer: MapLayer?
            
            switch fileType {
            case .shapefile:
                layer = self.importShapefile(from: url)
            case .gpx:
                layer = self.importGPX(from: url)
            case .kml:
                layer = self.importKML(from: url)
            case .geojson:
                layer = self.importGeoJSON(from: url)
            case .csv:
                layer = self.importCSV(from: url)
            }
            
            DispatchQueue.main.async {
                if let layer = layer {
                    self.importedLayers.append(layer)
                }
                self.isImporting = false
            }
        }
    }
    
    private func detectFileType(from url: URL) -> ImportFileType {
        let fileExtension = url.pathExtension.lowercased()
        
        switch fileExtension {
        case "shp", "dbf", "shx": return .shapefile
        case "gpx": return .gpx
        case "kml": return .kml
        case "geojson", "json": return .geojson
        case "csv": return .csv
        default: return .geojson
        }
    }
    
    private func importShapefile(from url: URL) -> MapLayer? {
        let baseURL = url.deletingPathExtension()
        let shpURL = baseURL.appendingPathExtension("shp")
        let dbfURL = baseURL.appendingPathExtension("dbf")
        
        guard FileManager.default.fileExists(atPath: shpURL.path),
              FileManager.default.fileExists(atPath: dbfURL.path) else {
            return nil
        }
        
        // Simplified - use external lib for full
        return MapLayer(
            name: shpURL.deletingPathExtension().lastPathComponent,
            features: [],
            type: .polygon,
            style: LayerStyle.defaultStyle()
        )
    }
    
    private func importGPX(from url: URL) -> MapLayer? {
        guard let data = try? Data(contentsOf: url),
              let gpxString = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        var features: [MapFeature] = []
        let lines = gpxString.components(separatedBy: .newlines)
        var currentTrack: [CLLocationCoordinate2D] = []
        
        for line in lines {
            if line.contains("<trkpt") {
                if let coordinate = parseGPXCoordinate(from: line) {
                    currentTrack.append(coordinate)
                }
            } else if line.contains("</trkseg>") || line.contains("</trk>") {
                if !currentTrack.isEmpty {
                    features.append(MapFeature(
                        geometry: .lineString(currentTrack),
                        properties: [:]
                    ))
                    currentTrack.removeAll()
                }
            } else if line.contains("<wpt") {
                if let coordinate = parseGPXCoordinate(from: line) {
                    features.append(MapFeature(
                        geometry: .point(coordinate),
                        properties: [:]
                    ))
                }
            }
        }
        
        return MapLayer(
            name: url.deletingPathExtension().lastPathComponent,
            features: features,
            type: .mixed,
            style: LayerStyle.defaultStyle()
        )
    }
    
    private func parseGPXCoordinate(from line: String) -> CLLocationCoordinate2D? {
        guard let latRange = line.range(of: "lat=\"[^\"]+\"", options: .regularExpression),
              let lonRange = line.range(of: "lon=\"[^\"]+\"", options: .regularExpression) else {
            return nil
        }
        
        let latString = String(line[latRange]).replacingOccurrences(of: "lat=\"", with: "").replacingOccurrences(of: "\"", with: "")
        let lonString = String(line[lonRange]).replacingOccurrences(of: "lon=\"", with: "").replacingOccurrences(of: "\"", with: "")
        
        guard let lat = Double(latString), let lon = Double(lonString) else {
            return nil
        }
        
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
    
    private func importKML(from url: URL) -> MapLayer? {
        // Implement XML parsing for KML
        return nil // Placeholder
    }
    
    private func importGeoJSON(from url: URL) -> MapLayer? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        
        do {
            let geoJSON = try JSONDecoder().decode(GeoJSON.self, from: data)
            let features = geoJSON.features.map { feature in
                MapFeature(
                    geometry: .point(CLLocationCoordinate2D(
                        latitude: feature.geometry.coordinates[1],
                        longitude: feature.geometry.coordinates[0]
                    )),
                    properties: feature.properties
                )
            }
            return MapLayer(
                name: url.deletingPathExtension().lastPathComponent,
                features: features,
                type: .point,
                style: LayerStyle.defaultStyle()
            )
        } catch {
            print("GeoJSON import error: \(error)")
            return nil
        }
    }
    
    private func importCSV(from url: URL) -> MapLayer? {
        guard let data = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        
        let lines = data.components(separatedBy: .newlines)
        guard lines.count > 1 else { return nil }
        
        var features: [MapFeature] = []
        let headers = lines[0].components(separatedBy: ",")
        
        for line in lines.dropFirst() {
            let values = line.components(separatedBy: ",")
            guard values.count >= 2,
                  let lat = Double(values[0]),
                  let lon = Double(values[1]) else { continue }
            
            var properties: [String: String] = [:]
            for (index, header) in headers.enumerated() where index >= 2 && index < values.count {
                properties[header] = values[index]
            }
            
            features.append(MapFeature(
                geometry: .point(CLLocationCoordinate2D(latitude: lat, longitude: lon)),
                properties: properties
            ))
        }
        
        return MapLayer(
            name: url.deletingPathExtension().lastPathComponent,
            features: features,
            type: .point,
            style: LayerStyle.defaultStyle()
        )
    }
}

struct MapLayer: Identifiable {
    let id = UUID()
    let name: String
    let features: [MapFeature]
    let type: LayerType
    var isVisible: Bool = true
    var style: LayerStyle
    
    enum LayerType {
        case point, lineString, polygon, mixed
    }
}

struct MapFeature {
    let geometry: Geometry
    let properties: [String: String] // Changed to [String: String]
    
    enum Geometry {
        case point(CLLocationCoordinate2D)
        case lineString([CLLocationCoordinate2D])
        case polygon([[CLLocationCoordinate2D]])
    }
}

struct LayerStyle {
    let color: UIColor
    let lineWidth: CGFloat
    let pointSize: CGFloat
    
    static func defaultStyle() -> LayerStyle {
        LayerStyle(color: .systemBlue, lineWidth: 2.0, pointSize: 8.0)
    }
}
