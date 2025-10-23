//
//  MapView.swift
//  MFKGeoMeasure
//
//  Created by Szamosi Attila on 2025. 10. 19..
//

import SwiftUI
import MapKit
import Combine

struct MapView: UIViewRepresentable {
    @ObservedObject var viewModel: GeoMeasureViewModel
    
    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        return mapView
    }
    
    func updateUIView(_ uiView: MKMapView, context: Context) {
        uiView.removeAnnotations(uiView.annotations)
        uiView.removeOverlays(uiView.overlays)
        
        // Add measurement points as annotations
        let annotations = viewModel.points.map { point in
            let annotation = MKPointAnnotation()
            annotation.coordinate = point.clLocationCoordinate
            annotation.title = "Height: \(point.height) m"
            return annotation
        }
        uiView.addAnnotations(annotations)
        
        // Add imported layers as overlays
        for layer in viewModel.layerManager.importedLayers where layer.isVisible {
            switch layer.type {
            case .point:
                let pointAnnotations = layer.features.compactMap { feature -> MKPointAnnotation? in
                    if case .point(let coord) = feature.geometry {
                        let ann = MKPointAnnotation()
                        ann.coordinate = coord
                        ann.title = layer.name
                        return ann
                    }
                    return nil
                }
                uiView.addAnnotations(pointAnnotations)
            case .lineString:
                let polylines = layer.features.compactMap { feature -> MKPolyline? in
                    if case .lineString(let coords) = feature.geometry {
                        return MKPolyline(coordinates: coords, count: coords.count)
                    }
                    return nil
                }
                uiView.addOverlays(polylines)
            case .polygon:
                let polygons = layer.features.compactMap { feature -> MKPolygon? in
                    if case .polygon(let rings) = feature.geometry, let exterior = rings.first {
                        return MKPolygon(coordinates: exterior, count: exterior.count)
                    }
                    return nil
                }
                uiView.addOverlays(polygons)
            case .mixed:
                break
            }
        }
        
        // Center on current location if available
        if let coord = viewModel.currentCoordinate {
            let region = MKCoordinateRegion(center: coord, span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05))
            uiView.setRegion(region, animated: true)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MapView
        
        init(_ parent: MapView) {
            self.parent = parent
        }
        
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = .systemBlue
                renderer.lineWidth = 2.0
                return renderer
            } else if let polygon = overlay as? MKPolygon {
                let renderer = MKPolygonRenderer(polygon: polygon)
                renderer.fillColor = .systemBlue.withAlphaComponent(0.5)
                renderer.strokeColor = .systemBlue
                renderer.lineWidth = 1.0
                return renderer
            }
            return MKOverlayRenderer()
        }
    }
}

struct MapViewWrapper: View {
    @ObservedObject var viewModel: GeoMeasureViewModel
    
    var body: some View {
        ZStack {
            MapView(viewModel: viewModel)
            
            VStack(alignment: .trailing) {
                Button(action: { viewModel.toggleMode() }) {
                    Text(viewModel.mode == .gps ? "GPS" : "IMU")
                        .padding()
                        .background(viewModel.mode == .gps ? Color.green : Color.orange)
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                }
                if let height = viewModel.currentHeight {
                    HStack {
                        Text("Height: \(height, specifier: "%.2f") m")
                        if viewModel.mode == .imu {
                            Text(" ±\(viewModel.imuManager.accuracyEstimate, specifier: "%.2f") m")
                                .foregroundColor(.red)
                        }
                    }
                    .padding()
                    .background(Color.white.opacity(0.8))
                    .cornerRadius(8)
                }
                Spacer()
                Button(action: { viewModel.captureCurrentPoint() }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.largeTitle)
                        .foregroundColor(.red)
                }
                .padding()
            }
            .padding()
        }
    }
}
