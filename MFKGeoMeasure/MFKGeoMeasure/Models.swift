//
//  Models.swift
//  MFKGeoMeasure
//
//  Created by Szamosi Attila on 2025. 10. 19..
//

import Foundation
import CoreLocation

struct MeasurementPoint: Identifiable, Codable {
    let id: UUID
    let coordinate: Coordinate
    let height: Double
    let timestamp: Date
    let accuracy: Double?
    let mode: MeasurementMode
    
    init(id: UUID = UUID(),
         coordinate: CLLocationCoordinate2D,
         height: Double,
         timestamp: Date = Date(),
         accuracy: Double? = nil,
         mode: MeasurementMode) {
        self.id = id
        self.coordinate = Coordinate(coordinate: coordinate)
        self.height = height
        self.timestamp = timestamp
        self.accuracy = accuracy
        self.mode = mode
    }
    
    var clLocationCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }
}

struct Coordinate: Codable {
    let latitude: Double
    let longitude: Double
    
    init(coordinate: CLLocationCoordinate2D) {
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
    }
}

struct GeoJSON: Codable {
    let type: String
    let features: [GeoJSONFeature]
}

struct GeoJSONFeature: Codable {
    let type: String
    let geometry: GeoJSONPointGeometry
    let properties: [String: String] // Changed from [String: Any] to [String: String]
    
    enum CodingKeys: String, CodingKey {
        case type, geometry, properties
    }
    
    init(type: String, geometry: GeoJSONPointGeometry, properties: [String: String]) {
        self.type = type
        self.geometry = geometry
        self.properties = properties
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        geometry = try container.decode(GeoJSONPointGeometry.self, forKey: .geometry)
        properties = try container.decode([String: String].self, forKey: .properties)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(geometry, forKey: .geometry)
        try container.encode(properties, forKey: .properties)
    }
}

struct GeoJSONPointGeometry: Codable {
    let type: String
    let coordinates: [Double]
}
