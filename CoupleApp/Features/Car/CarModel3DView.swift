import SceneKit
import SwiftUI

/// Какая это машина (для 3D-модели).
enum CarModelKind {
    case volvoS40, audiQ3

    static func guess(from name: String) -> CarModelKind {
        let n = name.lowercased()
        return (n.contains("audi") || n.contains("ауди") || n.contains("q3")) ? .audiQ3 : .volvoS40
    }
}

/// 3D-машина сверху экрана: без фона и пола, крутится пальцем, двери открываются нажатием.
struct CarModel3DView: View {
    let name: String
    @State private var doorsOpen = false

    var body: some View {
        ZStack(alignment: .bottom) {
            CarSceneView(kind: .guess(from: name), doorsOpen: doorsOpen)
            HStack {
                Text("Крутите пальцем, нажмите на дверь")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    doorsOpen.toggle()
                } label: {
                    Label(doorsOpen ? "Закрыть двери" : "Открыть двери", systemImage: "car.side.fill")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal, 4)
        }
    }
}

private struct CarSceneView: UIViewRepresentable {
    let kind: CarModelKind
    let doorsOpen: Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> SCNView {
        let built = CarSceneBuilder.make(kind: kind)
        let view = SCNView()
        view.scene = built.scene
        view.backgroundColor = .clear
        view.isOpaque = false
        view.allowsCameraControl = true
        view.antialiasingMode = .multisampling4X
        view.defaultCameraController.interactionMode = .orbitTurntable
        view.defaultCameraController.maximumVerticalAngle = 50
        view.defaultCameraController.minimumVerticalAngle = -2
        view.defaultCameraController.inertiaEnabled = true
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped(_:)))
        view.addGestureRecognizer(tap)
        context.coordinator.doors = built.doors
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        context.coordinator.setAll(open: doorsOpen)
    }

    final class Coordinator: NSObject {
        var doors: [SCNNode] = []
        private var open: Set<String> = []
        private var lastAll = false

        func setAll(open wantOpen: Bool) {
            guard wantOpen != lastAll else { return }
            lastAll = wantOpen
            for door in doors { set(door, open: wantOpen) }
        }

        private func set(_ door: SCNNode, open wantOpen: Bool) {
            guard let name = door.name else { return }
            if wantOpen { open.insert(name) } else { open.remove(name) }
            let side: Float = name.contains(".L.") ? 1 : -1
            let angle: Float = wantOpen ? side * 1.0 : 0
            door.runAction(.rotateTo(x: 0, y: CGFloat(angle), z: 0, duration: 0.45, usesShortestUnitArc: true))
        }

        @objc func tapped(_ gesture: UITapGestureRecognizer) {
            guard let view = gesture.view as? SCNView else { return }
            let hits = view.hitTest(gesture.location(in: view), options: nil)
            for hit in hits {
                var node: SCNNode? = hit.node
                while let current = node {
                    if let name = current.name, name.hasPrefix("door.") {
                        set(current, open: !open.contains(name))
                        return
                    }
                    node = current.parent
                }
            }
        }
    }
}

// MARK: - Сборка модели

enum CarSceneBuilder {
    private struct DoorDef {
        let id: String
        let hingeX: CGFloat
        let rearX: CGFloat
        let upper: [CGPoint]
    }

    private struct Spec {
        let length: CGFloat
        let width: CGFloat
        let belt: CGFloat
        let wheelRadius: CGFloat
        let axle: CGFloat
        let outline: [CGPoint]      // от низа переда по кругу вверх и назад
        let rearBottom: CGPoint
        let cabin: [CGPoint]
        let windshield: (CGPoint, CGPoint)
        let rearGlass: (CGPoint, CGPoint)
        let doors: [DoorDef]
        let paint: UIColor
        let metal: CGFloat
        let rough: CGFloat
        let isSUV: Bool
    }

    private static func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

    private static func spec(for kind: CarModelKind) -> Spec {
        switch kind {
        case .volvoS40:
            return Spec(
                length: 4.48, width: 1.77, belt: 1.0, wheelRadius: 0.32, axle: 1.32,
                outline: [p(2.24, 0.30), p(2.27, 0.55), p(2.21, 0.72), p(1.95, 0.84), p(1.4, 0.95),
                          p(0.95, 1.0), p(-1.3, 1.02), p(-2.0, 1.0), p(-2.2, 0.92), p(-2.27, 0.62)],
                rearBottom: p(-2.24, 0.30),
                cabin: [p(-1.30, 1.0), p(-0.85, 1.38), p(-0.6, 1.44), p(0.25, 1.44), p(0.50, 1.41), p(0.98, 1.0)],
                windshield: (p(0.98, 1.0), p(0.50, 1.41)),
                rearGlass: (p(-1.30, 1.0), p(-0.85, 1.38)),
                doors: [
                    DoorDef(id: "f", hingeX: 0.92, rearX: -0.08,
                            upper: [p(0.92, 1.0), p(0.5, 1.40), p(-0.08, 1.43), p(-0.08, 1.0)]),
                    DoorDef(id: "r", hingeX: -0.12, rearX: -1.18,
                            upper: [p(-0.12, 1.0), p(-0.12, 1.43), p(-0.8, 1.40), p(-1.18, 1.0)]),
                ],
                paint: UIColor(red: 0.04, green: 0.04, blue: 0.05, alpha: 1), metal: 0.75, rough: 0.22, isSUV: false
            )
        case .audiQ3:
            return Spec(
                length: 4.39, width: 1.83, belt: 1.07, wheelRadius: 0.36, axle: 1.30,
                outline: [p(2.19, 0.30), p(2.22, 0.60), p(2.16, 0.82), p(1.9, 0.98), p(1.3, 1.06),
                          p(0.95, 1.08), p(-1.9, 1.08), p(-2.1, 1.05), p(-2.2, 0.85), p(-2.22, 0.5)],
                rearBottom: p(-2.19, 0.30),
                cabin: [p(-1.98, 1.07), p(-1.92, 1.38), p(-1.75, 1.58), p(0.2, 1.60), p(0.55, 1.56), p(1.02, 1.08)],
                windshield: (p(1.02, 1.08), p(0.55, 1.56)),
                rearGlass: (p(-1.98, 1.07), p(-1.75, 1.58)),
                doors: [
                    DoorDef(id: "f", hingeX: 0.98, rearX: -0.02,
                            upper: [p(0.98, 1.07), p(0.58, 1.54), p(-0.02, 1.58), p(-0.02, 1.07)]),
                    DoorDef(id: "r", hingeX: -0.06, rearX: -1.16,
                            upper: [p(-0.06, 1.07), p(-0.06, 1.59), p(-1.3, 1.58), p(-1.16, 1.07)]),
                ],
                paint: UIColor(red: 0.97, green: 0.97, blue: 0.95, alpha: 1), metal: 0.25, rough: 0.28, isSUV: true
            )
        }
    }

    // MARK: Помощники

    private static func v(_ x: CGFloat, _ y: CGFloat, _ z: CGFloat) -> SCNVector3 {
        SCNVector3(Float(x), Float(y), Float(z))
    }

    private static func mat(_ color: UIColor, metal: CGFloat = 0, rough: CGFloat = 0.5, clear: Bool = false) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = color
        m.metalness.contents = metal
        m.roughness.contents = rough
        if clear { m.clearCoat.contents = 1.0 }
        return m
    }

    private static func shapeNode(_ pts: [CGPoint], depth: CGFloat, chamfer: CGFloat, materials: [SCNMaterial]) -> SCNNode {
        let path = UIBezierPath()
        path.move(to: pts[0])
        for point in pts.dropFirst() { path.addLine(to: point) }
        path.close()
        let shape = SCNShape(path: path, extrusionDepth: depth)
        shape.chamferRadius = chamfer
        shape.materials = materials
        let node = SCNNode(geometry: shape)
        let (mn, mx) = node.boundingBox
        node.pivot = SCNMatrix4MakeTranslation(0, 0, (mn.z + mx.z) / 2)
        return node
    }

    private static func arch(xc: CGFloat, yc: CGFloat, r: CGFloat) -> [CGPoint] {
        (0...14).map { i in
            let a = CGFloat.pi * (1 - CGFloat(i) / 14)
            return CGPoint(x: xc + r * cos(a), y: yc + r * sin(a))
        }
    }

    private static func box(_ w: CGFloat, _ h: CGFloat, _ l: CGFloat, _ m: SCNMaterial, round: CGFloat = 0.01) -> SCNGeometry {
        let b = SCNBox(width: w, height: h, length: l, chamferRadius: round)
        b.materials = [m]
        return b
    }

    private static func environmentImage() -> UIImage {
        let size = CGSize(width: 512, height: 256)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            let colors = [
                UIColor(white: 0.98, alpha: 1).cgColor,
                UIColor(red: 0.86, green: 0.89, blue: 0.96, alpha: 1).cgColor,
                UIColor(white: 0.30, alpha: 1).cgColor,
                UIColor(white: 0.55, alpha: 1).cgColor,
            ]
            if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 0.45, 0.55, 1]) {
                ctx.cgContext.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
            }
        }
    }

    // MARK: Сборка

    static func make(kind: CarModelKind) -> (scene: SCNScene, doors: [SCNNode]) {
        let s = spec(for: kind)
        let scene = SCNScene()
        scene.background.contents = UIColor.clear
        scene.lightingEnvironment.contents = environmentImage()
        scene.lightingEnvironment.intensity = 1.3

        let paint = mat(s.paint, metal: s.metal, rough: s.rough, clear: true)
        let glass = mat(UIColor(red: 0.10, green: 0.14, blue: 0.18, alpha: 1), metal: 0.9, rough: 0.05)
        let black = mat(UIColor(white: 0.06, alpha: 1), metal: 0, rough: 0.7)
        let chrome = mat(UIColor(white: 0.85, alpha: 1), metal: 1, rough: 0.15)
        let tireMat = mat(UIColor(white: 0.04, alpha: 1), metal: 0, rough: 0.9)
        let alloy = mat(UIColor(white: 0.78, alpha: 1), metal: 1, rough: 0.25)
        let rimDark = mat(UIColor(white: 0.18, alpha: 1), metal: 0.6, rough: 0.5)

        let car = SCNNode()
        let half = s.width / 2
        let cabinW = s.width * 0.93
        let cabinHalf = cabinW / 2

        // Нижний кузов с вырезами под колёса
        let archR = s.wheelRadius + 0.08
        let base: CGFloat = 0.26
        var lower: [CGPoint] = [s.rearBottom]
        lower.append(p(-s.axle - archR, base))
        lower += arch(xc: -s.axle, yc: s.wheelRadius, r: archR)
        lower.append(p(-s.axle + archR, base))
        lower.append(p(s.axle - archR, base))
        lower += arch(xc: s.axle, yc: s.wheelRadius, r: archR)
        lower.append(p(s.axle + archR, base))
        lower += s.outline
        let body = shapeNode(lower, depth: s.width, chamfer: 0.07, materials: Array(repeating: paint, count: 5))
        car.addChildNode(body)

        // Салон: стёкла по бокам, крыша и рамки цвета кузова
        let cabin = shapeNode(s.cabin, depth: cabinW, chamfer: 0.05, materials: [glass, glass, paint, paint, paint])
        car.addChildNode(cabin)

        // Лобовое и заднее стекло
        func slopeGlass(_ a: CGPoint, _ b: CGPoint) {
            let dx = b.x - a.x, dy = b.y - a.y
            let plane = SCNPlane(width: cabinW * 0.9, height: sqrt(dx * dx + dy * dy) * 0.96)
            let gm = glass.copy() as! SCNMaterial
            gm.isDoubleSided = true
            plane.materials = [gm]
            let inner = SCNNode(geometry: plane)
            inner.eulerAngles.y = .pi / 2
            let holder = SCNNode()
            holder.addChildNode(inner)
            let phi = atan2(dy, dx)
            holder.eulerAngles.z = Float(phi - .pi / 2)
            // чуть наружу по нормали
            let nx = sin(phi), ny = -cos(phi)
            holder.position = v((a.x + b.x) / 2 + nx * 0.015, (a.y + b.y) / 2 + ny * 0.015, 0)
            car.addChildNode(holder)
        }
        slopeGlass(s.windshield.0, s.windshield.1)
        slopeGlass(s.rearGlass.0, s.rearGlass.1)

        // Двери: нижняя панель + стекло, ось у переднего края
        var doors: [SCNNode] = []
        for side in [1.0, -1.0] as [CGFloat] {
            for d in s.doors {
                let hinge = SCNNode()
                hinge.name = "door.\(side > 0 ? "L" : "R").\(d.id)"
                hinge.position = v(d.hingeX, 0, 0)

                // Нижняя панель обходит вырезы под колёса
                let notch = s.wheelRadius + archR + 0.04
                let archFront = s.axle - archR
                let archRear = -s.axle + archR
                var lowerPts: [CGPoint] = [p(d.hingeX, s.belt)]
                if d.hingeX > archFront {
                    lowerPts += [p(d.hingeX, notch), p(archFront, notch), p(archFront, 0.32)]
                } else {
                    lowerPts.append(p(d.hingeX, 0.32))
                }
                if d.rearX < archRear {
                    lowerPts += [p(archRear, 0.32), p(archRear, notch), p(d.rearX, notch)]
                } else {
                    lowerPts.append(p(d.rearX, 0.32))
                }
                lowerPts.append(p(d.rearX, s.belt))
                let panel = shapeNode(lowerPts, depth: 0.05, chamfer: 0.015, materials: Array(repeating: paint, count: 5))
                panel.position = v(-d.hingeX, 0, side * (half + 0.015))
                hinge.addChildNode(panel)

                let win = shapeNode(d.upper, depth: 0.02, chamfer: 0, materials: Array(repeating: glass, count: 3))
                win.position = v(-d.hingeX, 0, side * (cabinHalf + 0.012))
                hinge.addChildNode(win)

                let handle = SCNNode(geometry: box(0.16, 0.03, 0.035, chrome))
                handle.position = v(d.rearX + 0.18 - d.hingeX, s.belt - 0.09, side * (half + 0.055))
                hinge.addChildNode(handle)

                car.addChildNode(hinge)
                doors.append(hinge)
            }
        }

        // Передняя и задняя части
        let front = s.length / 2
        // Решётка
        let grilleW: CGFloat = s.isSUV ? 0.78 : 0.7
        let grilleH: CGFloat = s.isSUV ? 0.30 : 0.18
        let grille = SCNNode(geometry: box(0.04, grilleH, grilleW, black, round: 0.02))
        grille.position = v(front - 0.03, s.isSUV ? 0.68 : 0.66, 0)
        car.addChildNode(grille)
        if s.isSUV {
            let frame = SCNNode(geometry: box(0.035, grilleH + 0.05, grilleW + 0.05, chrome, round: 0.02))
            frame.position = v(front - 0.045, 0.68, 0)
            car.addChildNode(frame)
        }
        let nose = SCNNode(geometry: box(0.03, 0.08, 0.16, chrome, round: 0.02))
        nose.position = v(front - 0.005, s.isSUV ? 0.68 : 0.66, 0)
        car.addChildNode(nose)

        // Нижний воздухозаборник
        let intake = SCNNode(geometry: box(0.04, 0.12, s.width * 0.6, black, round: 0.03))
        intake.position = v(front - 0.04, 0.42, 0)
        car.addChildNode(intake)

        // Фары и стопы
        let lightMat = mat(UIColor(red: 1, green: 0.97, blue: 0.85, alpha: 1), metal: 0.3, rough: 0.1)
        lightMat.emission.contents = UIColor(red: 1, green: 0.97, blue: 0.85, alpha: 1)
        lightMat.emission.intensity = 0.25
        let tailMat = mat(UIColor(red: 0.75, green: 0.05, blue: 0.08, alpha: 1), metal: 0.2, rough: 0.2)
        tailMat.emission.contents = UIColor(red: 0.8, green: 0.05, blue: 0.08, alpha: 1)
        tailMat.emission.intensity = 0.2
        for side in [1.0, -1.0] as [CGFloat] {
            let head = SCNNode(geometry: box(0.05, 0.13, 0.42, lightMat, round: 0.04))
            head.position = v(front - 0.12, s.isSUV ? 0.86 : 0.84, side * (half - 0.28))
            head.eulerAngles.y = Float(-side) * 0.18
            car.addChildNode(head)
            let tail = SCNNode(geometry: box(0.05, 0.14, 0.4, tailMat, round: 0.04))
            tail.position = v(-front + 0.04, s.isSUV ? 0.88 : 0.9, side * (half - 0.28))
            car.addChildNode(tail)
            // зеркало
            let mirror = SCNNode(geometry: box(0.16, 0.12, 0.18, paint, round: 0.05))
            mirror.position = v(s.windshield.0.x - 0.12, s.belt + 0.07, side * (half + 0.1))
            car.addChildNode(mirror)
        }
        // Номера
        let plateMat = mat(UIColor(white: 0.95, alpha: 1), metal: 0, rough: 0.5)
        let plateF = SCNNode(geometry: box(0.02, 0.12, 0.52, plateMat, round: 0.01))
        plateF.position = v(front + 0.0, 0.36, 0)
        car.addChildNode(plateF)
        let plateR = SCNNode(geometry: box(0.02, 0.12, 0.52, plateMat, round: 0.01))
        plateR.position = v(-front - 0.0, 0.62, 0)
        car.addChildNode(plateR)

        // Чёрные пороги и пластик арок (особенно у Audi)
        let sillZ = half + 0.012
        for side in [1.0, -1.0] as [CGFloat] {
            let sill = SCNNode(geometry: box(s.axle * 1.4, 0.09, 0.03, black, round: 0.01))
            sill.position = v(0, 0.33, side * sillZ)
            car.addChildNode(sill)
        }

        // Рейлинги Audi
        if s.isSUV {
            for side in [1.0, -1.0] as [CGFloat] {
                let rail = SCNNode(geometry: box(1.8, 0.03, 0.04, black, round: 0.01))
                rail.position = v(-0.75, 1.625, side * 0.6)
                car.addChildNode(rail)
            }
        }

        // Колёса
        for x in [-s.axle, s.axle] {
            for side in [1.0, -1.0] as [CGFloat] {
                car.addChildNode(wheel(radius: s.wheelRadius, x: x, z: side * (half - 0.11),
                                       tire: tireMat, alloy: alloy, dark: rimDark))
            }
        }

        car.position = v(0, -0.85, 0)
        car.eulerAngles.y = -0.55
        scene.rootNode.addChildNode(car)

        // Свет
        let sun = SCNNode()
        sun.light = SCNLight()
        sun.light?.type = .directional
        sun.light?.intensity = 900
        sun.eulerAngles = SCNVector3(-0.9, 0.7, 0)
        scene.rootNode.addChildNode(sun)

        // Камера
        let camNode = SCNNode()
        camNode.camera = SCNCamera()
        camNode.camera?.fieldOfView = 30
        camNode.camera?.zNear = 0.1
        camNode.camera?.zFar = 100
        camNode.position = v(0, 1.4, 9.2)
        camNode.look(at: SCNVector3(0, 0, 0))
        scene.rootNode.addChildNode(camNode)

        return (scene, doors)
    }

    private static func wheel(radius r: CGFloat, x: CGFloat, z: CGFloat, tire: SCNMaterial, alloy: SCNMaterial, dark: SCNMaterial) -> SCNNode {
        let holder = SCNNode()
        let t = SCNCylinder(radius: r, height: 0.22)
        t.materials = [tire]
        holder.addChildNode(SCNNode(geometry: t))

        let rimR = r * 0.7
        let disc = SCNCylinder(radius: rimR, height: 0.226)
        disc.materials = [dark]
        holder.addChildNode(SCNNode(geometry: disc))

        let ring = SCNTube(innerRadius: rimR * 0.92, outerRadius: rimR, height: 0.232)
        ring.materials = [alloy]
        holder.addChildNode(SCNNode(geometry: ring))

        for k in 0..<10 {
            let arm = SCNNode()
            arm.eulerAngles.y = Float(k) * .pi / 5
            let spoke = SCNBox(width: rimR * 0.9, height: 0.234, length: 0.04, chamferRadius: 0.005)
            spoke.materials = [alloy]
            let sn = SCNNode(geometry: spoke)
            sn.position = SCNVector3(Float(rimR * 0.5), 0, 0)
            arm.addChildNode(sn)
            holder.addChildNode(arm)
        }
        let hub = SCNCylinder(radius: rimR * 0.18, height: 0.24)
        hub.materials = [alloy]
        holder.addChildNode(SCNNode(geometry: hub))

        holder.eulerAngles.x = .pi / 2
        let outer = SCNNode()
        outer.addChildNode(holder)
        outer.position = SCNVector3(Float(x), Float(r), Float(z))
        return outer
    }
}
