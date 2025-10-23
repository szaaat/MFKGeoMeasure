//
//  PointsListView.swift
//  MFKGeoMeasure
//
//  Created by Szamosi Attila on 2025. 10. 19..
//

import SwiftUI

struct PointsListView: View {
    @ObservedObject var viewModel: GeoMeasureViewModel
    
    var body: some View {
        List {
            ForEach(viewModel.points) { point in
                VStack(alignment: .leading) {
                    Text("Height: \(String(format: "%.2f", point.height)) m")
                    Text("Lat: \(String(format: "%.6f", point.coordinate.latitude)), Lon: \(String(format: "%.6f", point.coordinate.longitude))")
                    Text("Time: \(point.timestamp.formatted())")
                    if let accuracy = point.accuracy {
                        Text("Accuracy: ±\(String(format: "%.2f", accuracy)) m")
                    }
                    Text("Mode: \(point.mode.rawValue.uppercased())")
                }
            }
            .onDelete(perform: viewModel.deletePoint)
        }
        .navigationTitle("Measurement Points")
    }
}
