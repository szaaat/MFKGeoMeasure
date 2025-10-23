//
//  ThreeDProfileView.swift
//  MFKGeoMeasure
//
//  Created by Szamosi Attila on 2025. 10. 19..
//

import SwiftUI
import SceneKit

struct ThreeDProfileView: View {
    let points: [MeasurementPoint]
    
    var body: some View {
        SceneView(scene: createScene(), options: [.allowsCameraControl])
            .navigationTitle("3D Profile")
    }
    
    private func createScene() -> SCNScene {
        let scene = SCNScene()
        
        let path = SCNNode()
        let positions = points.enumerated().map { (index, point) -> SCNVector3 in
            SCNVector3(Float(index), Float(point.height), 0)
        }
        
        let geometry = tubeGeometry(positions: positions)
        let node = SCNNode(geometry: geometry)
        path.addChildNode(node)
        
        scene.rootNode.addChildNode(path)
        
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.position = SCNVector3(x: Float(points.count)/2, y: Float(points.map { $0.height }.max() ?? 0) + 10, z: 50)
        scene.rootNode.addChildNode(cameraNode)
        
        return scene
    }
    
    private func tubeGeometry(positions: [SCNVector3]) -> SCNGeometry {
        var vertices: [SCNVector3] = []
        var indices: [Int32] = []
        
        for (i, pos) in positions.enumerated() {
            vertices.append(pos)
            if i < positions.count - 1 {
                indices.append(Int32(i))
                indices.append(Int32(i + 1))
            }
        }
        
        let vertexSource = SCNGeometrySource(vertices: vertices)
        let element = SCNGeometryElement(indices: indices, primitiveType: .line)
        
        return SCNGeometry(sources: [vertexSource], elements: [element])
    }
}
