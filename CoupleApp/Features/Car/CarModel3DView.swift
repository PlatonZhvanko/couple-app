import SceneKit
import SwiftUI

/// Вид кузова для 3D-модели.
enum CarBody {
    case sedan, suv

    /// Определяем по названию: пока модели собираются из простых фигур.
    static func guess(from name: String) -> CarBody {
        let n = name.lowercased()
        return (n.contains("q3") || n.contains("suv") || n.contains("кросс")) ? .suv : .sedan
    }

    static func color(from name: String) -> UIColor {
        let n = name.lowercased()
        if n.contains("бел") || n.contains("white") { return UIColor(white: 0.96, alpha: 1) }
        if n.contains("audi") { return UIColor(white: 0.96, alpha: 1) }
        if n.contains("volvo") { return UIColor(red: 0.22, green: 0.27, blue: 0.38, alpha: 1) }
        return UIColor(red: 0.8, green: 0.5, blue: 0.5, alpha: 1)
    }
}

/// Простая 3D-машина (заглушка), которую можно крутить пальцем.
/// Позже её заменим на детальную модель.
struct CarModel3DView: View {
    let name: String
    @State private var scene: SCNScene

    init(name: String) {
        self.name = name
        _scene = State(initialValue: CarSceneBuilder.make(body: .guess(from: name), color: CarBody.color(from: name)))
    }

    var body: some View {
        SceneView(
            scene: scene,
            options: [.allowsCameraControl, .autoenablesDefaultLighting]
        )
        .background(
            LinearGradient(colors: [Color(red: 0.98, green: 0.90, blue: 0.88), Color(red: 0.90, green: 0.82, blue: 0.74)],
                           startPoint: .top, endPoint: .bottom)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(alignment: .bottomTrailing) {
            Label("Покрутите", systemImage: "hand.draw.fill")
                .font(.caption2)
                .padding(6)
                .foregroundStyle(.secondary)
        }
    }
}

enum CarSceneBuilder {
    static func make(body: CarBody, color: UIColor) -> SCNScene {
        let scene = SCNScene()
        let paint = SCNMaterial()
        paint.diffuse.contents = color
        paint.specular.contents = UIColor.white
        paint.lightingModel = .blinn
        let glass = SCNMaterial()
        glass.diffuse.contents = UIColor(red: 0.25, green: 0.33, blue: 0.4, alpha: 1)
        glass.specular.contents = UIColor.white
        let dark = SCNMaterial()
        dark.diffuse.contents = UIColor(white: 0.12, alpha: 1)

        let car = SCNNode()
        // Длина по оси X, ширина по Z.
        let length: CGFloat = body == .sedan ? 4.5 : 4.2
        let lower = SCNBox(width: length, height: 0.7, length: 1.9, chamferRadius: 0.2)
        lower.materials = [paint]
        let lowerNode = SCNNode(geometry: lower)
        lowerNode.position = SCNVector3(0, 0.65, 0)
        car.addChildNode(lowerNode)

        // Салон
        let cabinLength: CGFloat = body == .sedan ? 2.2 : 2.9
        let cabinHeight: CGFloat = body == .sedan ? 0.65 : 0.8
        let cabin = SCNBox(width: cabinLength, height: cabinHeight, length: 1.7, chamferRadius: 0.25)
        cabin.materials = [glass]
        let cabinNode = SCNNode(geometry: cabin)
        cabinNode.position = SCNVector3(Float(body == .sedan ? -0.15 : -0.1), Float(1.0 + cabinHeight / 2 - 0.2), 0)
        car.addChildNode(cabinNode)

        // Крыша
        let roof = SCNBox(width: cabinLength - 0.2, height: 0.08, length: 1.6, chamferRadius: 0.04)
        roof.materials = [paint]
        let roofNode = SCNNode(geometry: roof)
        roofNode.position = SCNVector3(cabinNode.position.x, cabinNode.position.y + Float(cabinHeight / 2), 0)
        car.addChildNode(roofNode)

        // Фары
        for z in [-0.65, 0.65] {
            let light = SCNBox(width: 0.06, height: 0.15, length: 0.35, chamferRadius: 0.03)
            light.firstMaterial?.diffuse.contents = UIColor(red: 1, green: 0.95, blue: 0.7, alpha: 1)
            light.firstMaterial?.emission.contents = UIColor(red: 1, green: 0.95, blue: 0.7, alpha: 1)
            let n = SCNNode(geometry: light)
            n.position = SCNVector3(Float(length / 2), 0.72, Float(z))
            car.addChildNode(n)
        }

        // Колёса
        let wheelX = Float(length / 2 - 0.9)
        for x in [-wheelX, wheelX] {
            for z in [-0.95, 0.95] as [Float] {
                let wheel = SCNCylinder(radius: 0.38, height: 0.28)
                wheel.materials = [dark]
                let n = SCNNode(geometry: wheel)
                n.eulerAngles.x = .pi / 2
                n.position = SCNVector3(x, 0.38, z)
                car.addChildNode(n)
            }
        }

        scene.rootNode.addChildNode(car)

        // Земля-тень
        let floor = SCNFloor()
        floor.reflectivity = 0.05
        floor.firstMaterial?.diffuse.contents = UIColor(red: 0.93, green: 0.86, blue: 0.80, alpha: 1)
        scene.rootNode.addChildNode(SCNNode(geometry: floor))

        // Лёгкое вращение, пока не трогают
        car.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 24)))

        let cam = SCNNode()
        cam.camera = SCNCamera()
        cam.position = SCNVector3(6.2, 2.6, 6.2)
        cam.look(at: SCNVector3(0, 0.9, 0))
        scene.rootNode.addChildNode(cam)
        return scene
    }
}
