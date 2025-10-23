//
//  AltitudeProfileView.swift
//  MFKGeoMeasure
//
//  Created by Szamosi Attila on 2025. 10. 19..
//

import SwiftUI

struct AltitudeProfileView: View {
    let points: [MeasurementPoint]
    
    var body: some View {
        GeometryReader { geometry in
            Path { path in
                guard !points.isEmpty else { return }
                
                let width = geometry.size.width
                let height = geometry.size.height
                let minHeight = points.map { $0.height }.min() ?? 0
                let maxHeight = points.map { $0.height }.max() ?? 0
                let heightRange = maxHeight - minHeight > 0 ? maxHeight - minHeight : 1
                
                path.move(to: CGPoint(x: 0, y: height - (points[0].height - minHeight) / heightRange * height))
                
                for (index, point) in points.enumerated() {
                    let x = Double(index) / Double(points.count - 1) * width
                    let y = height - (point.height - minHeight) / heightRange * height
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
            .stroke(Color.blue, lineWidth: 2)
        }
        .padding()
        .navigationTitle("Altitude Profile")
    }
}
