import SwiftUI
import RealityKit
import ARKit

class Coordinator: NSObject, ARSessionDelegate {
    var parent: LiDARView
    var arView: ARView?
    var scannedEntities: [Entity] = []
    var boundingBoxEntity: ModelEntity?
    var isScanning: Bool = false
    var sceneAnchor: AnchorEntity?

    init(_ parent: LiDARView) {
        self.parent = parent
        super.init()
    }

    func setupARView() {
        guard let arView = arView else { return }
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        config.environmentTexturing = .automatic
        arView.session.delegate = self
        arView.session.run(config)
        
        sceneAnchor = AnchorEntity(world: .zero)
        arView.scene.addAnchor(sceneAnchor!)
        
        let boxSize: Float = 0.2 // 20cm cube
        let boxMesh = MeshResource.generateBox(size: boxSize)
        let material = SimpleMaterial(color: .green.withAlphaComponent(0.3), isMetallic: false)
        boundingBoxEntity = ModelEntity(mesh: boxMesh, materials: [material])
        
        if let boundingBoxEntity = boundingBoxEntity {
            boundingBoxEntity.position = SIMD3<Float>(0, 0, -0.3) // 30cm in front of the camera
            sceneAnchor?.addChild(boundingBoxEntity)
        }
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard isScanning else { return }
        
        let cameraTransform = frame.camera.transform
        let translation = SIMD3<Float>(0, 0, -0.3)
        boundingBoxEntity?.transform = Transform(matrix: cameraTransform * makeTranslationMatrix(translation))
        
        guard let pointCloud = frame.rawFeaturePoints else { return }
        
        let pointsInBox = pointCloud.points.filter { point in
            let localPoint = boundingBoxEntity!.convert(position: point, from: nil)
            return abs(localPoint.x) < 0.1 && abs(localPoint.y) < 0.1 && abs(localPoint.z) < 0.1
        }
        
        if !pointsInBox.isEmpty {
            visualizePoints(pointsInBox)
            updateDimensions(for: pointsInBox)
        }
    }

    func visualizePoints(_ points: [SIMD3<Float>]) {
        for entity in scannedEntities {
            entity.removeFromParent()
        }
        scannedEntities.removeAll()
        
        for point in points {
            let sphere = ModelEntity(mesh: .generateSphere(radius: 0.002), materials: [SimpleMaterial(color: .red, isMetallic: false)])
            sphere.position = point
            sceneAnchor?.addChild(sphere)
            scannedEntities.append(sphere)
        }
    }

    func updateDimensions(for points: [SIMD3<Float>]) {
        guard !points.isEmpty else { return }
        
        let xValues = points.map { $0.x }
        let yValues = points.map { $0.y }
        let zValues = points.map { $0.z }
        
        let width = (xValues.max()! - xValues.min()!) * 100
        let height = (yValues.max()! - yValues.min()!) * 100
        let depth = (zValues.max()! - zValues.min()!) * 100
        
        DispatchQueue.main.async {
            self.parent.dimensions = (width: width, height: height, depth: depth)
            self.parent.scanningStatus = "Width: \(String(format: "%.2f", width))cm, Height: \(String(format: "%.2f", height))cm, Depth: \(String(format: "%.2f", depth))cm"
        }
    }

    func startScanning() {
        isScanning = true
        for entity in scannedEntities {
            entity.removeFromParent()
        }
        scannedEntities.removeAll()
        DispatchQueue.main.async {
            self.parent.scanningStatus = "Scanning... Move your device around the object slowly"
        }
    }

    func stopScanning() {
        isScanning = false
        boundingBoxEntity?.removeFromParent()
        DispatchQueue.main.async {
            if self.scannedEntities.isEmpty {
                self.parent.scanningStatus = "No object scanned. Try again."
            } else {
                self.parent.scanningStatus = "Scan complete"
            }
        }
    }

    // Helper function to create a translation matrix
    func makeTranslationMatrix(_ translation: SIMD3<Float>) -> simd_float4x4 {
        return simd_float4x4(
            SIMD4<Float>(1, 0, 0, 0),
            SIMD4<Float>(0, 1, 0, 0),
            SIMD4<Float>(0, 0, 1, 0),
            SIMD4<Float>(translation.x, translation.y, translation.z, 1)
        )
    }
}

struct LiDARView: UIViewRepresentable {
    @Binding var dimensions: (width: Float, height: Float, depth: Float)?
    @Binding var isScanning: Bool
    @Binding var scanningStatus: String

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        context.coordinator.arView = arView
        context.coordinator.setupARView()
        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        context.coordinator.isScanning = isScanning
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
}

struct ContentView: View {
    @State private var dimensions: (width: Float, height: Float, depth: Float)?
    @State private var isScanning = false
    @State private var scanningStatus = "Ready to scan"

    var body: some View {
        VStack {
            LiDARView(dimensions: $dimensions, isScanning: $isScanning, scanningStatus: $scanningStatus)
                .edgesIgnoringSafeArea(.all)

            Button(action: {
                isScanning.toggle()
            }) {
                Text(isScanning ? "Stop Scan" : "Start Scan")
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .padding()

            Text(scanningStatus)
                .padding()

            if let dimensions = dimensions {
                Text("Width: \(String(format: "%.2f", dimensions.width)) cm")
                Text("Height: \(String(format: "%.2f", dimensions.height)) cm")
                Text("Depth: \(String(format: "%.2f", dimensions.depth)) cm")
            }
        }
    }
}

func createGeometry(from meshGeometry: ARMeshGeometry) -> SCNGeometry {
    let vertices = meshGeometry.vertices
    let normals = meshGeometry.normals
    let faces = meshGeometry.faces

    let vertexData = Data(bytes: vertices.buffer.contents(), count: vertices.count * vertices.stride)
    let vertexSource = SCNGeometrySource(data: vertexData,
                                         semantic: .vertex,
                                         vectorCount: vertices.count,
                                         usesFloatComponents: true,
                                         componentsPerVector: 3,
                                         bytesPerComponent: MemoryLayout<Float>.size,
                                         dataOffset: 0,
                                         dataStride: vertices.stride)

    let normalData = Data(bytes: normals.buffer.contents(), count: normals.count * normals.stride)
    let normalSource = SCNGeometrySource(data: normalData,
                                         semantic: .normal,
                                         vectorCount: normals.count,
                                         usesFloatComponents: true,
                                         componentsPerVector: 3,
                                         bytesPerComponent: MemoryLayout<Float>.size,
                                         dataOffset: 0,
                                         dataStride: normals.stride)

    let faceData = Data(bytes: faces.buffer.contents(), count: faces.count * faces.indexCountPerPrimitive * faces.bytesPerIndex)
    let faceElement = SCNGeometryElement(data: faceData,
                                         primitiveType: .triangles,
                                         primitiveCount: faces.count,
                                         bytesPerIndex: faces.bytesPerIndex)

    return SCNGeometry(sources: [vertexSource, normalSource], elements: [faceElement])
}
