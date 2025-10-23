//
//  ImportView..swift
//  MFKGeoMeasure
//
//  Created by Szamosi Attila on 2025. 10. 19..
//

import SwiftUI
import UniformTypeIdentifiers
import Combine // Hozzáadva a Combine import

struct ImportView: View {
    @ObservedObject var viewModel: GeoMeasureViewModel
    @Environment(\.presentationMode) var presentationMode
    @State private var showingImporter = false
    
    var body: some View {
        NavigationView {
            List {
                Section(header: Text("Imported Layers")) {
                    if viewModel.layerManager.importedLayers.isEmpty {
                        Text("No imported layers yet")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(viewModel.layerManager.importedLayers) { layer in
                            HStack {
                                Toggle(isOn: Binding(
                                    get: { layer.isVisible },
                                    set: { _ in
                                        // Toggle visibility logic (force update map)
                                        viewModel.objectWillChange.send()
                                    }
                                )) {
                                    VStack(alignment: .leading) {
                                        Text(layer.name)
                                            .font(.headline)
                                        Text("\(layer.features.count) features")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
                
                Section {
                    Button("Import File") {
                        showingImporter = true
                    }
                }
            }
            .navigationTitle("Import Layers")
            .navigationBarItems(trailing: Button("Done") {
                presentationMode.wrappedValue.dismiss()
            })
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [
                .geoJSON,
                UTType(mimeType: "application/gpx+xml") ?? .data,
                UTType(mimeType: "application/vnd.google-earth.kml+xml") ?? .data,
                .commaSeparatedText,
                .data
            ],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                for url in urls {
                    viewModel.layerManager.importFile(url)
                }
            case .failure(let error):
                print("Import error: \(error)")
            }
        }
    }
}

struct ImportView_Previews: PreviewProvider {
    static var previews: some View {
        ImportView(viewModel: GeoMeasureViewModel())
    }
}
