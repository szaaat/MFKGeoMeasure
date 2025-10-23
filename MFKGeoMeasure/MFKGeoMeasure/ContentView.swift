//
//  ContentView.swift
//  MFKGeoMeasure
//
//  Created by Szamosi Attila on 2025. 10. 19..
//

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var viewModel = GeoMeasureViewModel()
    @State private var showingExportSheet = false
    @State private var showingImportSheet = false
    
    var body: some View {
        TabView {
            MapViewWrapper(viewModel: viewModel)
                .tabItem {
                    Label("Map", systemImage: "map")
                }
            
            AltitudeProfileView(points: viewModel.points)
                .tabItem {
                    Label("Profile", systemImage: "chart.line.uptrend.xyaxis")
                }
            
            ThreeDProfileView(points: viewModel.points)
                .tabItem {
                    Label("3D", systemImage: "cube")
                }
            
            PointsListView(viewModel: viewModel)
                .tabItem {
                    Label("Points", systemImage: "list.bullet")
                }
        }
        .overlay(alignment: .bottomTrailing) {
            VStack {
                Button(action: { showingExportSheet = true }) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.title2)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .clipShape(Circle())
                        .shadow(radius: 5)
                }
                .disabled(viewModel.points.isEmpty)
                .opacity(viewModel.points.isEmpty ? 0.5 : 1.0)
                
                Button(action: { showingImportSheet = true }) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.title2)
                        .padding()
                        .background(Color.green)
                        .foregroundColor(.white)
                        .clipShape(Circle())
                        .shadow(radius: 5)
                }
            }
            .padding()
        }
        .sheet(isPresented: $showingExportSheet) {
            ExportView(viewModel: viewModel)
        }
        .sheet(isPresented: $showingImportSheet) {
            ImportView(viewModel: viewModel)
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
