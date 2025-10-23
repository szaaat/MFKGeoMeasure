//
//  ExportView.swift
//  MFKGeoMeasure
//
//  Created by Szamosi Attila on 2025. 10. 19..
//

import SwiftUI

struct ExportView: View {
    @ObservedObject var viewModel: GeoMeasureViewModel
    @Environment(\.presentationMode) var presentationMode
    
    @State private var selectedFormat: ExportFormat = .csv
    @State private var fileName: String = "measurements_\(Date().formatted(date: .numeric, time: .omitted))"
    @State private var exportURL: URL?
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Export Settings")) {
                    Picker("Format", selection: $selectedFormat) {
                        ForEach([ExportFormat.csv, .geoJSON, .kml, .gpx, .shp], id: \.self) { format in
                            Text(format.displayName).tag(format)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    
                    TextField("File Name", text: $fileName)
                    
                    Text("\(viewModel.points.count) measurement points to export")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Section {
                    Button(action: performExport) {
                        HStack {
                            if viewModel.exportManager.isExporting {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Exporting...")
                            } else {
                                Image(systemName: "square.and.arrow.up")
                                Text("Export")
                            }
                        }
                    }
                    .disabled(viewModel.points.isEmpty || viewModel.exportManager.isExporting)
                    
                    if viewModel.exportManager.isExporting {
                        ProgressView(value: viewModel.exportManager.exportProgress)
                            .progressViewStyle(LinearProgressViewStyle())
                    }
                }
                
                if let url = exportURL {
                    Section(header: Text("Exported File")) {
                        ShareLink(item: url) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                        
                        Button("New Export") {
                            exportURL = nil
                        }
                    }
                }
            }
            .navigationTitle("Export Data")
            .navigationBarItems(trailing: Button("Done") {
                presentationMode.wrappedValue.dismiss()
            })
        }
    }
    
    private func performExport() {
        guard !viewModel.points.isEmpty else { return }
        
        if let url = viewModel.exportManager.exportMeasurements(
            viewModel.points,
            format: selectedFormat,
            fileName: fileName
        ) {
            exportURL = url
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                viewModel.exportManager.shareFiles([url])
            }
        }
    }
}
