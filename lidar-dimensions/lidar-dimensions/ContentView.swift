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
    var spheres: [Entity] = []
    
    let sphereRadius: Float = 0.003 // Smaller sphere size
    let lineWidth: Float = 0.0005 // Thinner line
    
    func setupARView() {
        guard let arView = arView else { return }
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        arView.session.run(config)
    }
    
    func handleTap() {
        guard let arView = arView,
              let raycastResult = arView.raycast(from: arView.center, allowing: .estimatedPlane, alignment: .any).first
        else { return }
        
        let worldTransform = raycastResult.worldTransform
        let position = SIMD3(worldTransform.columns.3.x, worldTransform.columns.3.y, worldTransform.columns.3.z)
        
        if startPoint == nil {
            startPoint = position
            addSphere(at: position)
            addDebugSphere(at: position, color: .green)
            measurementStatus = "Tap to set end point"
        } else if endPoint == nil {
            endPoint = position
            addSphere(at: position)
            addDebugSphere(at: position, color: .red)
            updateMeasurement()
        } else {
            resetMeasurement()
        }
    }
    
    func addDebugSphere(at position: SIMD3<Float>, color: UIColor) {
        let sphere = ModelEntity(mesh: .generateSphere(radius: 0.002),
                                 materials: [SimpleMaterial(color: color, isMetallic: false)])
        let anchorEntity = AnchorEntity(world: position)
        anchorEntity.addChild(sphere)
        arView?.scene.addAnchor(anchorEntity)
    }

    func addSphere(at position: SIMD3<Float>) {
        let sphere = ModelEntity(mesh: .generateSphere(radius: 0.005),
                                 materials: [SimpleMaterial(color: .white, isMetallic: false)])
        let anchorEntity = AnchorEntity(world: position)
        anchorEntity.addChild(sphere)
        arView?.scene.addAnchor(anchorEntity)
        spheres.append(sphere)
    }

    func updateMeasurement() {
        guard let start = startPoint, let end = endPoint else { return }
        distance = simd_distance(start, end)
        drawLine(from: start, to: end)
    }

    func drawLine(from start: SIMD3<Float>, to end: SIMD3<Float>) {
        measurementLine?.removeFromParent()
        
        let length = simd_distance(start, end)
        let direction = simd_normalize(end - start)
        
        let dashedLine = Entity()
        let dashLength: Float = 0.02
        let gapLength: Float = 0.01
        let dashCount = Int(length / (dashLength + gapLength))
        
        for i in 0..<dashCount {
            let dashStart = start + direction * Float(i) * (dashLength + gapLength)
            let dashEnd = dashStart + direction * dashLength
            
            let dashMesh = MeshResource.generateBox(size: SIMD3(dashLength, 0.001, 0.001))
            let dashMaterial = SimpleMaterial(color: .white, isMetallic: false)
            let dashEntity = ModelEntity(mesh: dashMesh, materials: [dashMaterial])
            
            dashEntity.position = (dashStart + dashEnd) / 2
            
            let dashDirection = simd_normalize(dashEnd - dashStart)
            let rotationAxis = simd_cross([1, 0, 0], dashDirection)
            let rotationAngle = acos(simd_dot([1, 0, 0], dashDirection))
            dashEntity.orientation = simd_quaternion(rotationAngle, rotationAxis)
            
            dashedLine.addChild(dashEntity)
        }
        
        let anchorEntity = AnchorEntity(world: .zero)
        anchorEntity.addChild(dashedLine)
        arView?.scene.addAnchor(anchorEntity)
        
        measurementLine = dashedLine
    }

    func resetMeasurement() {
        startPoint = nil
        endPoint = nil
        measurementLine?.removeFromParent()
        measurementLine = nil
        for sphere in spheres {
            sphere.removeFromParent()
        }
        spheres.removeAll()
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
            
            VStack {
                Spacer()
                if let distance = viewModel.distance {
                    Text(String(format: "Distance: %.2f cm", distance * 100))
                        .padding()
                        .background(Color.black.opacity(0.7))
                        .foregroundColor(.white)
                        .cornerRadius(10)
                } else {
                    Text(viewModel.measurementStatus)
                        .padding()
                        .background(Color.black.opacity(0.7))
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                
                Button(action: {
                    viewModel.handleTap()
                }) {
                    Text("Set Point")
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .padding(.bottom, 50)
            }
            
            Image(systemName: "plus")
                .font(.system(size: 50))
                .foregroundColor(.white)
        }
    }
}
