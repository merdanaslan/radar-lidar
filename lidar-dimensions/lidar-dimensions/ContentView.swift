import SwiftUI
import RealityKit
import ARKit

class ARViewModel: ObservableObject {
    @Published var measurementStatus = "Tap to set start point"
    @Published var distance: Float?
    
    var arView: ARView?
    var startPoint: SIMD3<Float>?
    var endPoint: SIMD3<Float>?
    var measurementLine: Entity?
    var pointMarkers: [Entity] = []
    
    func setupARView() {
        guard let arView = arView else { return }
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        arView.session.run(config)
    }
    
    func handleTap(at screenPoint: CGPoint) {
        guard let arView = arView else { return }
        
        if let query = arView.makeRaycastQuery(from: screenPoint, allowing: .estimatedPlane, alignment: .any) {
            if let result = arView.session.raycast(query).first {
                let worldPosition = result.worldTransform.columns.3
                let position = SIMD3(worldPosition.x, worldPosition.y, worldPosition.z)
                
                if startPoint == nil {
                    startPoint = position
                    addPointMarker(at: position)
                    measurementStatus = "Tap to set end point"
                } else if endPoint == nil {
                    endPoint = position
                    addPointMarker(at: position)
                    updateMeasurement()
                } else {
                    resetMeasurement()
                }
            }
        } else {
            print("Unable to create raycast query")
        }
    }

    func addPointMarker(at position: SIMD3<Float>) {
        let sphere = ModelEntity(mesh: .generateSphere(radius: 0.01),
                                 materials: [SimpleMaterial(color: .red, isMetallic: false)])
        sphere.position = position
        
        let anchorEntity = AnchorEntity(world: position)
        anchorEntity.addChild(sphere)
        arView?.scene.addAnchor(anchorEntity)
        
        pointMarkers.append(sphere)
    }

    func updateMeasurement() {
        guard let start = startPoint, let end = endPoint else { return }
        distance = simd_distance(start, end)
        drawLine(from: start, to: end)
        measurementStatus = String(format: "%.2f cm", (distance ?? 0) * 100)
    }

    func drawLine(from start: SIMD3<Float>, to end: SIMD3<Float>) {
        measurementLine?.removeFromParent()
        
        let distance = simd_distance(start, end)
        let midPoint = (start + end) / 2
        
        let lineMesh = MeshResource.generateBox(size: SIMD3(distance, 0.002, 0.002))
        let lineMaterial = SimpleMaterial(color: .blue, isMetallic: false)
        let lineEntity = ModelEntity(mesh: lineMesh, materials: [lineMaterial])
        
        lineEntity.position = midPoint
        
        let direction = simd_normalize(end - start)
        let rotation = simd_quatf(from: [1, 0, 0], to: direction)
        lineEntity.orientation = rotation
        
        let anchorEntity = AnchorEntity(world: midPoint)
        anchorEntity.addChild(lineEntity)
        arView?.scene.addAnchor(anchorEntity)
        
        measurementLine = lineEntity
    }

    func resetMeasurement() {
        startPoint = nil
        endPoint = nil
        measurementLine?.removeFromParent()
        measurementLine = nil
        for marker in pointMarkers {
            marker.removeFromParent()
        }
        pointMarkers.removeAll()
        arView?.scene.anchors.removeAll()
        measurementStatus = "Tap to set start point"
        distance = nil
    }
}

struct ARViewContainer: UIViewRepresentable {
    @ObservedObject var viewModel: ARViewModel
    
    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        viewModel.arView = arView
        viewModel.setupARView()
        return arView
    }
    
    func updateUIView(_ uiView: ARView, context: Context) {}
}

struct ContentView: View {
    @StateObject private var viewModel = ARViewModel()
    
    var body: some View {
        ZStack {
            ARViewContainer(viewModel: viewModel)
                .edgesIgnoringSafeArea(.all)
            
            // Crosshair
            Image(systemName: "plus")
                .font(.system(size: 40))
                .foregroundColor(.white)
            
            // Measurement display and reset button
            VStack {
                Spacer()
                Text(viewModel.measurementStatus)
                    .padding()
                    .background(Color.black.opacity(0.7))
                    .foregroundColor(.white)
                    .cornerRadius(10)
                
                Button(action: viewModel.resetMeasurement) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.title)
                        .padding()
                        .background(Color.black.opacity(0.7))
                        .foregroundColor(.white)
                        .clipShape(Circle())
                }
            }
            .padding()
        }
        .onTapGesture { location in
            viewModel.handleTap(at: location)
        }
    }
}

