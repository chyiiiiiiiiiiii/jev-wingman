import AppKit
import SceneKit
import SwiftUI
import WingmanCore

/// 〈訊息偵探社〉 (promo/reel-03): a rainy-night noir in 3D, built from SceneKit primitives and rendered
/// offscreen, frame by frame. A client bursts into a detective's office with a message they cannot read;
/// the detective is Wingman, in a fedora, and the verdict and the panel he hands over are Wingman's real
/// ones for that made-up chat (staged.json).
@MainActor
final class NoirStage {
    private let context: ReelContext
    private let scene = SCNScene()
    private let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
    private let eye = SCNNode()
    private let lead = NoirLead()
    private let detective = NoirDetective()
    private let laptop = NoirLaptop()
    private let office = SCNNode()
    private let street = SCNNode()
    private let lampLight = SCNNode()
    private let lampStand = SCNNode()
    private let windowLight = SCNNode()
    private let flash = SCNNode()
    private let neon = SCNNode()
    private let rain = SCNNode()
    private let folder = SCNNode()
    private let folderPage = SCNMaterial()
    private let board = SCNNode()
    private let verdictCard = SCNNode()
    private var strings: [SCNNode] = []
    private var pictures: [String: NSImage] = [:]

    /// Where the street is, far enough from the office that neither sees the other.
    private static let outside = SCNVector3(60, 0, 0)

    init(context: ReelContext) {
        self.context = context
        renderer.scene = scene
        scene.background.contents = NSColor(red: 0.02, green: 0.03, blue: 0.06, alpha: 1)
        scene.lightingEnvironment.contents = NoirArt.gradient([NSColor(red: 0.05, green: 0.06, blue: 0.12, alpha: 1),
                                                                NSColor(red: 0.30, green: 0.24, blue: 0.20, alpha: 1)], angle: 90)
        scene.lightingEnvironment.intensity = 0.6
        scene.fogStartDistance = 4
        scene.fogEndDistance = 16
        scene.fogColor = NSColor(red: 0.03, green: 0.05, blue: 0.10, alpha: 1)
        buildCamera()
        buildOffice()
        buildStreet()
        scene.rootNode.addChildNode(lead.root)
        scene.rootNode.addChildNode(detective.root)
        scene.rootNode.addChildNode(laptop.root)
        scene.rootNode.addChildNode(rain)
        buildRain()
    }

    func image(_ shot: String, t: Double) -> NSImage {
        SCNTransaction.begin()
        SCNTransaction.disableActions = true
        SCNTransaction.animationDuration = 0
        pose(shot, t)
        SCNTransaction.commit()
        return renderer.snapshot(atTime: t, with: CGSize(width: 540, height: 960), antialiasingMode: .multisampling4X)
    }

    // MARK: - Building

    private func buildCamera() {
        let camera = SCNCamera()
        camera.wantsHDR = true
        camera.wantsExposureAdaptation = false
        camera.exposureOffset = -0.9
        camera.bloomIntensity = 0.3
        camera.bloomThreshold = 1.25
        camera.bloomBlurRadius = 14
        camera.vignettingIntensity = 0.9
        camera.vignettingPower = 1.2
        camera.screenSpaceAmbientOcclusionIntensity = 0.7
        camera.screenSpaceAmbientOcclusionRadius = 0.3
        camera.saturation = 0.9
        camera.contrast = 0.12
        camera.colorFringeStrength = 0.4
        camera.wantsDepthOfField = true
        camera.focalBlurSampleCount = 24
        camera.sensorHeight = 24
        camera.zNear = 0.05
        camera.zFar = 80
        eye.camera = camera
        scene.rootNode.addChildNode(eye)
        renderer.pointOfView = eye
    }

    private func buildOffice() {
        scene.rootNode.addChildNode(office)
        let floor = SCNFloor()
        floor.reflectivity = 0.12
        floor.reflectionFalloffEnd = 3
        floor.materials = [Noir.material(NoirArt.pattern("wood"), rough: 0.45, scale: 2.5)]
        scene.rootNode.addChildNode(SCNNode(geometry: floor))

        let wall = Noir.node(SCNPlane(width: 12, height: 6), Noir.material(NoirArt.pattern("wall"), rough: 0.85, scale: 4), at: SCNVector3(0, 3, -2.2))
        wall.castsShadow = false
        office.addChildNode(wall)
        let side = Noir.node(SCNPlane(width: 8, height: 6), Noir.material(NoirArt.pattern("wall"), rough: 0.85, scale: 3), at: SCNVector3(-2.6, 3, 1))
        side.eulerAngles.y = .pi / 2
        side.castsShadow = false
        office.addChildNode(side)

        // The window: the city behind wet glass, blinds in front, rain between.
        let city = Noir.node(SCNPlane(width: 1.7, height: 1.3), Noir.material(NoirArt.pattern("city"), emission: NoirArt.pattern("city")),
                             at: SCNVector3(1.0, 2.0, -2.19))
        city.castsShadow = false
        office.addChildNode(city)
        let wood = Noir.material(NSColor(red: 0.20, green: 0.12, blue: 0.08, alpha: 1), rough: 0.5)
        for (size, position) in [(SCNVector3(1.86, 0.08, 0.08), SCNVector3(1.0, 2.69, -2.15)), (SCNVector3(1.86, 0.08, 0.1), SCNVector3(1.0, 1.31, -2.13)),
                                 (SCNVector3(0.08, 1.4, 0.08), SCNVector3(0.1, 2.0, -2.15)), (SCNVector3(0.08, 1.4, 0.08), SCNVector3(1.9, 2.0, -2.15))] {
            office.addChildNode(Noir.node(SCNBox(width: size.x, height: size.y, length: size.z, chamferRadius: 0.01), wood, at: position))
        }
        let slat = Noir.material(NSColor(red: 0.75, green: 0.70, blue: 0.60, alpha: 1), rough: 0.6)
        for i in 0..<13 {
            let blade = Noir.node(SCNBox(width: 1.72, height: 0.075, length: 0.006, chamferRadius: 0), slat, at: SCNVector3(1.0, 1.38 + Double(i) * 0.1, -2.08))
            blade.eulerAngles.x = 0.9
            office.addChildNode(blade)
        }

        // Moonlight and a streetlamp through the blinds: stripes across the desk and whoever is at it.
        let window = SCNLight()
        window.type = .spot
        window.color = NSColor(red: 0.55, green: 0.70, blue: 1.0, alpha: 1)
        window.intensity = 1000
        window.spotInnerAngle = 18
        window.spotOuterAngle = 34
        window.castsShadow = true
        window.shadowRadius = 3
        window.shadowSampleCount = 8
        window.shadowMapSize = CGSize(width: 2048, height: 2048)
        window.gobo?.contents = NoirArt.blinds
        window.gobo?.intensity = 0.85
        windowLight.light = window
        windowLight.position = SCNVector3(1.4, 2.6, -4.2)
        windowLight.look(at: SCNVector3(0.2, 1.1, 0.4))
        office.addChildNode(windowLight)

        // The desk, a green banker's lamp, a mug, a stack of files.
        let desk = Noir.material(NoirArt.pattern("wood"), rough: 0.35, scale: 1)
        office.addChildNode(Noir.node(SCNBox(width: 2.3, height: 0.08, length: 1.0, chamferRadius: 0.025), desk, at: SCNVector3(0, 0.92, -0.45)))
        office.addChildNode(Noir.node(SCNBox(width: 2.2, height: 0.86, length: 0.06, chamferRadius: 0.02), desk, at: SCNVector3(0, 0.45, 0.02)))
        let brass = Noir.material(NSColor(red: 0.78, green: 0.58, blue: 0.28, alpha: 1), rough: 0.3, metal: 0.9)
        office.addChildNode(lampStand)
        lampStand.addChildNode(Noir.node(SCNCylinder(radius: 0.11, height: 0.03), brass, at: SCNVector3(-0.75, 0.975, -0.55)))
        lampStand.addChildNode(Noir.node(SCNCylinder(radius: 0.014, height: 0.32), brass, at: SCNVector3(-0.75, 1.13, -0.55)))
        let shade = Noir.node(SCNCylinder(radius: 0.1, height: 0.42),
                              Noir.material(NSColor(red: 0.05, green: 0.35, blue: 0.18, alpha: 1), rough: 0.15,
                                            emission: NSColor(red: 0.02, green: 0.25, blue: 0.10, alpha: 1)),
                              at: SCNVector3(-0.75, 1.32, -0.5))
        shade.eulerAngles.z = .pi / 2
        lampStand.addChildNode(shade)
        let lamp = SCNLight()
        lamp.type = .spot
        lamp.temperature = 2700
        lamp.intensity = 750
        lamp.spotInnerAngle = 40
        lamp.spotOuterAngle = 95
        lamp.castsShadow = true
        lamp.shadowRadius = 10
        lamp.shadowSampleCount = 16
        lamp.shadowMapSize = CGSize(width: 2048, height: 2048)
        lamp.attenuationStartDistance = 0.5
        lamp.attenuationEndDistance = 5
        lampLight.light = lamp
        lampLight.position = SCNVector3(-0.7, 1.26, -0.42)
        lampLight.look(at: SCNVector3(-0.1, 0.9, 0.1))
        office.addChildNode(lampLight)
        let mug = Noir.material(NSColor(red: 0.85, green: 0.84, blue: 0.80, alpha: 1), rough: 0.25)
        office.addChildNode(Noir.node(SCNCylinder(radius: 0.06, height: 0.13), mug, at: SCNVector3(0.85, 1.025, -0.5)))
        office.addChildNode(Noir.node(SCNTorus(ringRadius: 0.035, pipeRadius: 0.012), mug, at: SCNVector3(0.92, 1.03, -0.5)).rotated(x: .pi / 2))
        let manila = Noir.material(NSColor(red: 0.86, green: 0.72, blue: 0.48, alpha: 1), rough: 0.8)
        for i in 0..<3 {
            office.addChildNode(Noir.node(SCNBox(width: 0.42, height: 0.012, length: 0.32, chamferRadius: 0.003), manila,
                                          at: SCNVector3(0.62, 0.97 + Double(i) * 0.013, -0.75)).rotated(y: Double(i) * 0.12 - 0.1))
        }

        // The open case file, flat on the desk for the shot from above.
        // Unlit, so the panel on it reads exactly as the app draws it.
        folderPage.lightingModel = .constant
        folderPage.diffuse.contents = NSColor.white
        folder.addChildNode(Noir.node(SCNBox(width: 0.68, height: 0.006, length: 0.9, chamferRadius: 0.004), folderPage, at: .init(0, 0, 0)))
        folder.position = SCNVector3(0, 0.97, -0.35)
        folder.isHidden = true
        office.addChildNode(folder)

        // The evidence board on the side wall, red string waiting to be pinned.
        board.position = SCNVector3(-2.55, 1.75, -0.4)
        board.eulerAngles.y = .pi / 2
        office.addChildNode(board)
        board.addChildNode(Noir.node(SCNBox(width: 1.3, height: 2.0, length: 0.05, chamferRadius: 0.01), Noir.material(NoirArt.pattern("cork"), rough: 0.9)))
        board.addChildNode(Noir.node(SCNBox(width: 1.4, height: 2.1, length: 0.04, chamferRadius: 0.01), wood, at: SCNVector3(0, 0, -0.01)))

        // A little fill, so the shadows are not holes.
        let fill = SCNLight()
        fill.type = .omni
        fill.color = NSColor(red: 0.55, green: 0.45, blue: 0.85, alpha: 1)
        fill.intensity = 80
        let fillNode = SCNNode()
        fillNode.light = fill
        fillNode.position = SCNVector3(-1.8, 1.2, 1.8)
        office.addChildNode(fillNode)
        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.color = NSColor(red: 0.35, green: 0.42, blue: 0.6, alpha: 1)
        ambient.intensity = 70
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        scene.rootNode.addChildNode(ambientNode)

        // Lightning.
        let bolt = SCNLight()
        bolt.type = .omni
        bolt.color = NSColor(red: 0.75, green: 0.85, blue: 1, alpha: 1)
        bolt.intensity = 0
        flash.light = bolt
        flash.position = SCNVector3(1.0, 2.2, -3)
        scene.rootNode.addChildNode(flash)
    }

    private func buildStreet() {
        street.position = Self.outside
        scene.rootNode.addChildNode(street)
        let wall = Noir.node(SCNPlane(width: 14, height: 8), Noir.material(NoirArt.pattern("brick"), rough: 0.8, scale: 6), at: SCNVector3(0, 4, -1.6))
        street.addChildNode(wall)
        // A door with frosted glass, lit from within.
        street.addChildNode(Noir.node(SCNBox(width: 1.2, height: 2.3, length: 0.1, chamferRadius: 0.02),
                                      Noir.material(NSColor(red: 0.16, green: 0.10, blue: 0.07, alpha: 1), rough: 0.5), at: SCNVector3(0.9, 1.15, -1.55)))
        street.addChildNode(Noir.node(SCNPlane(width: 0.8, height: 1.0),
                                      Noir.material(NSColor(red: 1, green: 0.8, blue: 0.5, alpha: 1), emission: NSColor(red: 1, green: 0.72, blue: 0.4, alpha: 1)),
                                      at: SCNVector3(0.9, 1.65, -1.49)))
        // The sign.
        let sign = SCNText(string: "訊息偵探社", extrusionDepth: 0.06)
        sign.font = NSFont(name: "PingFang TC Semibold", size: 0.42)
        sign.flatness = 0.003
        sign.chamferRadius = 0.01
        sign.materials = [Noir.material(NSColor(red: 1, green: 0.3, blue: 0.6, alpha: 1), emission: NSColor(red: 0.85, green: 0.16, blue: 0.48, alpha: 1))]
        let signNode = SCNNode(geometry: sign)
        let (low, high) = signNode.boundingBox
        signNode.pivot = SCNMatrix4MakeTranslation((high.x + low.x) / 2, (high.y + low.y) / 2, 0)
        signNode.position = SCNVector3(-0.6, 3.0, -1.45)
        neon.addChildNode(signNode)
        let small = SCNText(string: "WINGMAN · 24H", extrusionDepth: 0.03)
        small.font = NSFont.systemFont(ofSize: 0.17, weight: .bold)
        small.flatness = 0.003
        small.materials = [Noir.material(NSColor(red: 0.3, green: 0.9, blue: 1, alpha: 1), emission: NSColor(red: 0.16, green: 0.6, blue: 0.75, alpha: 1))]
        let smallNode = SCNNode(geometry: small)
        let (l2, h2) = smallNode.boundingBox
        smallNode.pivot = SCNMatrix4MakeTranslation((h2.x + l2.x) / 2, (h2.y + l2.y) / 2, 0)
        smallNode.position = SCNVector3(-0.6, 2.55, -1.45)
        neon.addChildNode(smallNode)
        let glow = SCNLight()
        glow.type = .omni
        glow.color = NSColor(red: 1, green: 0.3, blue: 0.6, alpha: 1)
        glow.intensity = 380
        glow.attenuationEndDistance = 5
        let glowNode = SCNNode()
        glowNode.light = glow
        glowNode.position = SCNVector3(-0.6, 2.8, -0.9)
        neon.addChildNode(glowNode)
        street.addChildNode(neon)
        // A streetlamp's cone of light.
        let lamp = SCNLight()
        lamp.type = .spot
        lamp.temperature = 3200
        lamp.intensity = 1300
        lamp.spotOuterAngle = 60
        lamp.castsShadow = true
        lamp.shadowRadius = 8
        lamp.shadowSampleCount = 12
        let lampNode = SCNNode()
        lampNode.light = lamp
        lampNode.position = SCNVector3(1.8, 4.2, 0.6)
        lampNode.look(at: SCNVector3(0.6, 0, -0.6))
        street.addChildNode(lampNode)
    }

    private func buildRain() {
        let drop = Noir.material(NSColor(red: 0.7, green: 0.8, blue: 1, alpha: 1), emission: NSColor(red: 0.45, green: 0.55, blue: 0.75, alpha: 1))
        drop.transparency = 0.45
        drop.blendMode = .add
        drop.writesToDepthBuffer = false
        let streak = SCNBox(width: 0.006, height: 0.32, length: 0.006, chamferRadius: 0)
        streak.materials = [drop]
        for _ in 0..<260 {
            let node = SCNNode(geometry: streak)
            node.castsShadow = false
            node.eulerAngles.z = 0.12
            rain.addChildNode(node)
        }
    }

    // MARK: - Shots

    /// Points the camera; a camera looking straight down needs another up than the sky, and `roll` tilts it.
    private func camera(at position: SCNVector3, looking target: SCNVector3, focus: Double? = nil, fStop: Double = 2.8, lens: Double = 35,
                        down: Bool = false, roll: Double = 0) {
        eye.position = position
        eye.look(at: target, up: down ? SCNVector3(0, 0, -1) : SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))
        if roll != 0 { eye.simdLocalRotate(by: simd_quatf(angle: Float(roll), axis: SIMD3<Float>(0, 0, 1))) }
        eye.camera?.focalLength = lens
        eye.camera?.fStop = fStop
        eye.camera?.focusDistance = focus ?? Double(simd_distance(simd_float3(position), simd_float3(target)))
    }

    /// Rain falling at `t`, inside a box around `centre`.
    private func fall(_ t: Double, centre: SCNVector3, size: SCNVector3) {
        for (i, node) in rain.childNodes.enumerated() {
            let seed = Double(i)
            let x = (seed * 0.6180339).truncatingRemainder(dividingBy: 1)
            let z = (seed * 0.4142135).truncatingRemainder(dividingBy: 1)
            let y = (1 - ((seed * 0.7320508) + t * 2.6).truncatingRemainder(dividingBy: 1))
            node.position = SCNVector3(centre.x + (x - 0.5) * size.x, centre.y + (y - 0.5) * size.y, centre.z + (z - 0.5) * size.z)
        }
    }

    private func reset() {
        lead.root.isHidden = false
        detective.root.isHidden = false
        laptop.root.isHidden = false
        folder.isHidden = true
        verdictCard.isHidden = true
        lampStand.isHidden = false
        flash.light?.intensity = 0
        lampLight.light?.intensity = 750
        lead.pose(.init())
        detective.pose(.init())
        detective.root.position = SCNVector3(0, 0, -0.85)
        detective.root.eulerAngles = SCNVector3(0, 0, 0)
        lead.root.position = SCNVector3(0.2, 0, 0.75)
        lead.root.eulerAngles = SCNVector3(0, CGFloat.pi, 0)
        lead.root.scale = SCNVector3(0.72, 0.72, 0.72)
        laptop.place(on: SCNVector3(0.25, 0.96, -0.2), facing: .pi, scale: 0.7)
        laptop.screen(chatImage())
        eye.camera?.exposureOffset = -0.9
        windowLight.light?.intensity = 1000
        // Rain stays outside the window unless a shot takes it into the street.
        fall(0, centre: SCNVector3(1.0, 2.0, -2.17), size: SCNVector3(1.6, 1.3, 0.02))
    }

    private func pose(_ shot: String, _ t: Double) {
        reset()
        fall(t, centre: SCNVector3(1.0, 2.0, -2.17), size: SCNVector3(1.6, 1.3, 0.02))
        switch shot {
        case "open":
            // In the dark, the message is the only light; then the sky cracks.
            lead.root.isHidden = true
            detective.root.isHidden = true
            lampLight.light?.intensity = 0
            laptop.place(on: SCNVector3(0, 0.96, -0.3), facing: 0)
            flash.light?.intensity = t > 1.15 && t < 1.32 ? 30000 : t > 1.38 && t < 1.45 ? 18000 : 0
            let push = Self.smooth(t / 2.6)
            camera(at: SCNVector3(0.02, 1.19 - 0.03 * push, -0.08 - 0.08 * push), looking: SCNVector3(0, 1.13, -0.55), fStop: 1.8, lens: 22)
        case "street":
            lead.root.isHidden = true
            detective.root.isHidden = true
            laptop.root.isHidden = true
            let o = Self.outside
            fall(t, centre: SCNVector3(o.x, 1.8, 0.8), size: SCNVector3(5, 4, 3.5))
            // The sign stutters on.
            neon.isHidden = !(t > 0.25 && !(t > 0.38 && t < 0.46) && !(t > 0.6 && t < 0.64))
            let rise = Self.smooth(t / 1.9)
            camera(at: SCNVector3(o.x - 0.3, 0.6 + 0.5 * rise, 4.6), looking: SCNVector3(o.x - 0.45, 2.0 + 0.4 * rise, -1.4), fStop: 5, lens: 24)
        case "enter":
            // The door flies open; the client runs in clutching a laptop.
            let run = Self.smooth(min(1, t / 1.3))
            lead.root.position = SCNVector3(2.3 - 1.5 * run, abs(sin(t * 11)) * 0.05 * (1 - run), 0.85)
            lead.root.eulerAngles.y = CGFloat(-Double.pi / 2 - 0.7 * run)
            lead.pose(.init(face: .init(eyes: 1, brows: -1, mouth: .open, sweat: true), arms: .carry))
            laptop.carry(by: lead)
            detective.pose(.init(face: .init(eyes: t < 1.2 ? 0.55 : 1, look: CGPoint(x: 0.6, y: 0)), lookUp: 0.3 * run))
            camera(at: SCNVector3(-1.4, 1.6, 3.6), looking: SCNVector3(0.4, 1.1, -0.2), fStop: 4, lens: 26)
        case "client":
            lead.root.position = SCNVector3(0.3, 0, 0.75)
            lead.root.eulerAngles.y = CGFloat(Double.pi + 0.25)
            lead.pose(.init(face: .init(eyes: t > 1.6 && t < 1.7 ? 0.1 : 1, brows: -1, mouth: .frown, blush: 0.6, sweat: true), arms: .showing))
            laptop.show(by: lead, image: chatImage())
            windowLight.light?.intensity = 420
            camera(at: SCNVector3(1.05, 1.2, -0.65), looking: SCNVector3(0.3, 0.95, 0.75), fStop: 2.6, lens: 22)
        case "detective":
            // Up comes the glass, and the eye behind it swells.
            lead.root.isHidden = true
            let lift = Self.smooth(min(1, t / 0.8))
            detective.pose(.init(face: .init(eyes: 1, look: .zero, brows: 0.6), glass: lift, glassEye: lift))
            camera(at: SCNVector3(0.35, 1.62, 1.15), looking: SCNVector3(0.05, 1.6, -0.85), fStop: 2.8, lens: 30)
        case "evidence":
            lead.root.isHidden = true
            let found = t < 0.7 ? 0 : t < 1.4 ? 1 : t < 2.1 ? 2 : 3
            laptop.place(on: SCNVector3(0, 0.96, -0.3), facing: 0)
            laptop.screen(chatImage(circled: found))
            detective.root.position = SCNVector3(0.9, 0, -1.4)
            detective.pose(.init(glass: 1, glassAt: SCNVector3(-0.1 + 0.06 * Double(max(0, found - 1)), 1.08, -0.47)))
            camera(at: SCNVector3(0.02, 1.17, -0.08), looking: SCNVector3(0, 1.09, -0.55), fStop: 2.2, lens: 22)
        case "board":
            lead.root.isHidden = true
            laptop.root.isHidden = true
            detective.root.isHidden = true
            lampStand.isHidden = true
            pinBoard(t)
            let push = Self.smooth(t / 3.2)
            camera(at: SCNVector3(0.75 - 0.5 * push, 1.75, -0.4), looking: SCNVector3(-2.55, 1.75, -0.4), fStop: 4, lens: 28)
        case "casefile":
            lead.root.isHidden = true
            detective.root.isHidden = true
            laptop.root.isHidden = true
            folder.isHidden = false
            folderPage.diffuse.contents = picture("case01") {
                NoirArt.caseFile(number: "01", title: "你很忙齁", panel: context.panel(context.chat))
            }
            eye.camera?.exposureOffset = -0.15
            camera(at: SCNVector3(0, 2.4 - 0.12 * Self.smooth(t / 3.4), -0.5), looking: SCNVector3(0, 0.97, -0.5), fStop: 6, lens: 28,
                   down: true, roll: 0.03 * sin(t))
        case "case02", "case03":
            lead.root.isHidden = true
            detective.root.isHidden = true
            laptop.root.isHidden = true
            folder.isHidden = false
            let id = shot == "case02" ? "boss" : "notice"
            folderPage.diffuse.contents = picture(shot) {
                NoirArt.caseFile(number: shot == "case02" ? "02" : "03", title: shot == "case02" ? "主管半夜來訊" : "系統公告",
                                 message: context.lines(id).last { !$0.isMe }, app: context.app(id), verdict: context.verdict(id))
            }
            let slide = Self.smooth(min(1, t / 0.35))
            folder.position = SCNVector3(0.8 * (1 - slide), 0.97, -0.35)
            eye.camera?.exposureOffset = -0.15
            camera(at: SCNVector3(0, 2.4, -0.5), looking: SCNVector3(0, 0.97, -0.5), fStop: 6, lens: 28,
                   down: true, roll: shot == "case02" ? -0.05 : 0.05)
        case "send":
            // The client at the desk, typing; the detective watches from the side.
            lead.root.position = SCNVector3(0.2, 0, 0.55)
            lead.root.eulerAngles.y = CGFloat.pi
            let press = t > 0.9 && t < 1.2
            lead.pose(.init(face: .init(eyes: t > 1.2 ? 0.15 : 1, brows: t > 1.2 ? 0 : 0.5, mouth: t > 1.2 ? .smile : .flat, blush: 0.5),
                            arms: press ? .press : .type))
            laptop.place(on: SCNVector3(0.2, 0.96, 0.12), facing: 0, scale: 0.7)
            windowLight.light?.intensity = 420
            detective.root.position = SCNVector3(-0.85, 0, -0.85)
            detective.pose(.init(face: .init(eyes: 1, look: CGPoint(x: 0.7, y: -0.3), mouth: .smile)))
            camera(at: SCNVector3(1.35, 1.55, -0.75), looking: SCNVector3(0.15, 1.05, 0.5), fStop: 3.2, lens: 22)
        case "reply":
            lead.root.isHidden = true
            detective.root.isHidden = true
            laptop.place(on: SCNVector3(0, 0.96, -0.3), facing: 0)
            laptop.screen(t > 0.35 ? chatImage(sent: true, reply: true) : chatImage(sent: true))
            lampLight.light?.intensity = 250
            camera(at: SCNVector3(0.02, 1.19, -0.08), looking: SCNVector3(0, 1.11, -0.55), fStop: 2.0, lens: 22)
        case "closed":
            let jump = abs(sin(min(t, 1.6) * 6)) * 0.16
            lead.root.position = SCNVector3(0.55, jump, 0.8)
            lead.root.eulerAngles.y = CGFloat(Double.pi - 0.55)
            lead.pose(.init(face: .init(eyes: 0.15, mouth: .open, blush: 1), arms: .cheer))
            laptop.place(on: SCNVector3(0.25, 0.96, -0.2), facing: .pi, scale: 0.7)
            detective.pose(.init(face: .init(eyes: 0.15, mouth: .smile), hatTip: Self.smooth(min(1, max(0, t - 0.3) / 0.5))))
            camera(at: SCNVector3(-1.2, 1.55, 3.4), looking: SCNVector3(0.2, 1.15, -0.2), fStop: 4, lens: 26)
        default:    // "end": the detective in the doorway under the sign
            lead.root.isHidden = true
            laptop.root.isHidden = true
            let o = Self.outside
            fall(t, centre: SCNVector3(o.x, 1.8, 0.8), size: SCNVector3(5, 4, 3.5))
            neon.isHidden = false
            detective.root.position = SCNVector3(o.x + 0.9, -0.25, -1.0)
            detective.pose(.init(face: .init(eyes: 1, mouth: .smile), hatTip: Self.smooth(min(1, max(0, t - 0.8) / 0.5))))
            camera(at: SCNVector3(o.x - 0.1, 1.3, 4.8), looking: SCNVector3(o.x - 0.15, 2.0, -1.2), fStop: 5, lens: 24)
        }
        street.isHidden = !(shot == "street" || shot == "end")
        office.isHidden = !street.isHidden
    }

    /// The evidence board fills up: the message, what came before it, the words in question; then string,
    /// and the card in the middle turns over to show Wingman's verdict.
    private func pinBoard(_ t: Double) {
        if board.childNodes.count == 2 {
            let lines = context.lines(context.chat)
            let before = lines.last { $0.isMe }?.text ?? ""
            let message = context.incoming?.text ?? ""
            let cards: [(NSImage, SCNVector3, Double)] = [
                (NoirArt.card("證物 A · 她的訊息", message), SCNVector3(-0.3, 0.68, 0.04), -0.05),
                (NoirArt.card("證物 B · 前一句（我）", before), SCNVector3(0.3, 0.22, 0.04), 0.06),
                (NoirArt.card("證物 C", "「哈哈」？\n「好啦」？\n「齁」？", tint: Color(red: 1, green: 0.93, blue: 0.55)), SCNVector3(-0.3, -0.18, 0.04), 0.04),
            ]
            for (image, position, tilt) in cards {
                let card = Noir.node(SCNPlane(width: 0.57, height: 0.38), Noir.material(image, rough: 0.9), at: position)
                card.eulerAngles.z = CGFloat(tilt)
                board.addChildNode(card)
                board.addChildNode(Noir.node(SCNSphere(radius: 0.022), Noir.material(NSColor.systemRed, rough: 0.3),
                                             at: SCNVector3(position.x, position.y + 0.16, 0.07)))
            }
            if let v = context.verdict(context.chat), let said = context.said[context.chat] {
                let front = Noir.node(SCNPlane(width: 0.9, height: 0.6), Noir.material(NoirArt.verdict(v, said: said), rough: 0.6,
                                                                                         emission: NSColor(white: 0.12, alpha: 1)))
                let back = Noir.node(SCNPlane(width: 0.9, height: 0.6), Noir.material(NoirArt.card("鑑定中", "？"), rough: 0.9))
                back.eulerAngles.y = .pi
                verdictCard.addChildNode(front)
                verdictCard.addChildNode(back)
                verdictCard.position = SCNVector3(0, -0.66, 0.07)
                board.addChildNode(verdictCard)
            }
            let red = Noir.material(NSColor(red: 0.85, green: 0.1, blue: 0.12, alpha: 1), rough: 0.5)
            for from in [SCNVector3(-0.3, 0.84, 0.07), SCNVector3(0.3, 0.38, 0.07), SCNVector3(-0.3, -0.02, 0.07)] {
                let string = SCNNode(geometry: SCNCylinder(radius: 0.006, height: 1))
                string.geometry?.materials = [red]
                string.name = "\(from.x),\(from.y)"
                strings.append(string)
                board.addChildNode(string)
            }
        }
        verdictCard.isHidden = false
        // Strings run out to the verdict one after another, then it turns over.
        let target = SCNVector3(0, -0.4, 0.07)
        for (i, string) in strings.enumerated() {
            let parts = string.name!.split(separator: ",").compactMap { Double($0) }
            let from = SCNVector3(parts[0], parts[1], 0.07)
            let grow = Self.smooth(min(1, max(0, (t - 0.5 - Double(i) * 0.3) / 0.35)))
            let end = SCNVector3(from.x + (target.x - from.x) * grow, from.y + (target.y - from.y) * grow, 0.07)
            let length = sqrt(pow(end.x - from.x, 2) + pow(end.y - from.y, 2))
            string.isHidden = grow <= 0
            string.scale = SCNVector3(1, max(0.001, length), 1)
            string.position = SCNVector3((from.x + end.x) / 2, (from.y + end.y) / 2, 0.07)
            string.eulerAngles.z = atan2(end.y - from.y, end.x - from.x) - .pi / 2
        }
        let turn = Self.smooth(min(1, max(0, (t - 1.7) / 0.45)))
        verdictCard.eulerAngles.y = CGFloat(.pi * (1 - turn))
        verdictCard.scale = SCNVector3(1 + 0.15 * sin(.pi * turn), 1 + 0.15 * sin(.pi * turn), 1)
    }

    private func picture(_ key: String, _ make: () -> NSImage) -> NSImage {
        if let image = pictures[key] { return image }
        let image = make()
        pictures[key] = image
        return image
    }

    private func chatImage(circled: Int = 0, sent: Bool = false, reply: Bool = false) -> NSImage {
        picture("chat-\(circled)-\(sent)-\(reply)") {
            NoirArt.chat(lines: context.lines(context.chat), circled: circled, sent: sent ? context.best : nil,
                         reply: reply ? context.text : nil)
        }
    }

    static func smooth(_ x: Double) -> Double {
        let c = min(1, max(0, x))
        return c * c * (3 - 2 * c)
    }
}

// MARK: - Helpers

enum Noir {
    static func material(_ contents: Any, rough: CGFloat = 0.6, metal: CGFloat = 0, emission: Any? = nil, scale: CGFloat = 1,
                         clearCoat: CGFloat = 0) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = contents
        m.roughness.contents = rough
        m.metalness.contents = metal
        if let emission { m.emission.contents = emission }
        if scale != 1 {
            m.diffuse.contentsTransform = SCNMatrix4MakeScale(scale, scale, 1)
            m.diffuse.wrapS = .repeat
            m.diffuse.wrapT = .repeat
        }
        if clearCoat > 0 {
            m.clearCoat.contents = clearCoat
            m.clearCoatRoughness.contents = 0.08
        }
        return m
    }

    static func node(_ geometry: SCNGeometry, _ material: SCNMaterial, at position: SCNVector3 = SCNVector3(0, 0, 0)) -> SCNNode {
        geometry.materials = [material]
        let node = SCNNode(geometry: geometry)
        node.position = position
        return node
    }

    /// A crescent, for a mouth: a smile when `up`, a frown otherwise.
    static func crescent(width: CGFloat, depth: CGFloat, up: Bool) -> SCNShape {
        let path = NSBezierPath()
        let w = width / 2
        path.move(to: NSPoint(x: -w, y: 0))
        path.curve(to: NSPoint(x: w, y: 0), controlPoint1: NSPoint(x: -w * 0.5, y: up ? -depth * 1.6 : depth * 1.6),
                   controlPoint2: NSPoint(x: w * 0.5, y: up ? -depth * 1.6 : depth * 1.6))
        path.curve(to: NSPoint(x: -w, y: 0), controlPoint1: NSPoint(x: w * 0.4, y: up ? -depth * 0.5 : depth * 0.5),
                   controlPoint2: NSPoint(x: -w * 0.4, y: up ? -depth * 0.5 : depth * 0.5))
        path.close()
        path.flatness = 0.001
        let shape = SCNShape(path: path, extrusionDepth: 0.012)
        shape.chamferRadius = 0.003
        return shape
    }
}

extension SCNNode {
    func rotated(x: Double = 0, y: Double = 0, z: Double = 0) -> SCNNode {
        eulerAngles = SCNVector3(x, y, z)
        return self
    }
}

// MARK: - The client

struct NoirFace {
    enum Mouth { case flat, smile, frown, open }
    /// 1 open … 0 shut.
    var eyes: CGFloat = 1
    var look = CGPoint.zero
    /// -1 worried … 1 stern.
    var brows: CGFloat = 0
    var mouth: Mouth = .flat
    var blush: CGFloat = 0.35
    var sweat = false
}

/// The lead as a vinyl toy: a big round head, clay hair, a hoodie in the app's indigo.
@MainActor
final class NoirLead {
    struct Pose {
        enum Arms { case down, carry, showing, type, press, cheer }
        var face = NoirFace()
        var arms: Arms = .down
    }

    let root = SCNNode()
    private let head = SCNNode()
    private let leftArm = SCNNode(), rightArm = SCNNode()
    private var eyes: [SCNNode] = []
    private var brows: [SCNNode] = []
    private var cheeks: [SCNNode] = []
    private var mouths: [NoirFace.Mouth: SCNNode] = [:]
    private let sweat = SCNNode()
    let hands = SCNNode()       // between the hands, where a carried laptop goes

    init() {
        let skin = Noir.material(NSColor(red: 0.94, green: 0.77, blue: 0.65, alpha: 1), rough: 0.75)
        let hair = Noir.material(NSColor(red: 0.10, green: 0.08, blue: 0.11, alpha: 1), rough: 0.5, clearCoat: 0.12)
        let hoodie = Noir.material(NSColor(red: 0.30, green: 0.26, blue: 0.86, alpha: 1), rough: 0.85)
        let hoodieDark = Noir.material(NSColor(red: 0.22, green: 0.19, blue: 0.66, alpha: 1), rough: 0.85)
        let jeans = Noir.material(NSColor(red: 0.18, green: 0.22, blue: 0.30, alpha: 1), rough: 0.8)
        let white = Noir.material(NSColor(white: 0.95, alpha: 1), rough: 0.5)
        let ink = Noir.material(NSColor(red: 0.05, green: 0.04, blue: 0.06, alpha: 1), rough: 0.08, clearCoat: 1)

        for x in [-0.14, 0.14] {
            root.addChildNode(Noir.node(SCNCapsule(capRadius: 0.12, height: 0.6), jeans, at: SCNVector3(x, 0.34, 0)))
            root.addChildNode(Noir.node(SCNBox(width: 0.21, height: 0.12, length: 0.32, chamferRadius: 0.06), white, at: SCNVector3(x, 0.06, 0.05)))
        }
        let body = Noir.node(SCNCapsule(capRadius: 0.36, height: 1.0), hoodie, at: SCNVector3(0, 1.0, 0))
        body.scale = SCNVector3(1.08, 1, 0.86)
        root.addChildNode(body)
        root.addChildNode(Noir.node(SCNBox(width: 0.38, height: 0.17, length: 0.05, chamferRadius: 0.04), hoodieDark, at: SCNVector3(0, 0.88, 0.29)))
        root.addChildNode(Noir.node(SCNTorus(ringRadius: 0.27, pipeRadius: 0.1), hoodieDark, at: SCNVector3(0, 1.43, -0.02)).rotated(x: -0.15))
        for x in [-0.07, 0.07] {
            root.addChildNode(Noir.node(SCNCylinder(radius: 0.012, height: 0.22), white, at: SCNVector3(x, 1.27, 0.3)))
            root.addChildNode(Noir.node(SCNSphere(radius: 0.022), white, at: SCNVector3(x, 1.15, 0.3)))
        }
        for (arm, x) in [(leftArm, -0.37), (rightArm, 0.37)] {
            arm.position = SCNVector3(x, 1.33, 0)
            arm.addChildNode(Noir.node(SCNCapsule(capRadius: 0.105, height: 0.6), hoodie, at: SCNVector3(0, -0.27, 0)))
            arm.addChildNode(Noir.node(SCNSphere(radius: 0.095), skin, at: SCNVector3(0, -0.58, 0)))
            root.addChildNode(arm)
        }
        hands.position = SCNVector3(0, 1.0, 0.5)
        root.addChildNode(hands)

        head.position = SCNVector3(0, 1.82, 0)
        root.addChildNode(head)
        head.addChildNode(Noir.node(SCNSphere(radius: 0.42), skin))
        for x in [-0.41, 0.41] { head.addChildNode(Noir.node(SCNSphere(radius: 0.085), skin, at: SCNVector3(x, -0.02, 0))) }
        head.addChildNode(Noir.node(SCNSphere(radius: 0.026), Noir.material(NSColor(red: 0.97, green: 0.72, blue: 0.62, alpha: 1), rough: 0.5),
                                    at: SCNVector3(0, -0.06, 0.415)))
        // Hair: clay blobs over the crown and back, a fringe, and one strand that will not lie down.
        for (radius, position) in [(0.40, SCNVector3(0, 0.13, -0.06)), (0.41, SCNVector3(0, 0.0, -0.11)),
                                   (0.2, SCNVector3(-0.32, 0.1, 0.04)), (0.2, SCNVector3(0.32, 0.1, 0.04))] {
            head.addChildNode(Noir.node(SCNSphere(radius: radius), hair, at: position))
        }
        for (i, x) in [-0.25, -0.12, 0.0, 0.12, 0.25].enumerated() {
            let fringe = Noir.node(SCNCapsule(capRadius: 0.075, height: 0.3), hair, at: SCNVector3(x, 0.27, 0.27 - abs(x) * 0.25))
            fringe.eulerAngles = SCNVector3(-1.0, 0, -x * 1.3 + (i.isMultiple(of: 2) ? 0.08 : -0.08))
            head.addChildNode(fringe)
        }
        head.addChildNode(Noir.node(SCNCapsule(capRadius: 0.03, height: 0.26), hair, at: SCNVector3(0.06, 0.53, 0.02)).rotated(z: -0.7))

        for x in [-0.15, 0.15] {
            let eye = SCNNode()
            eye.position = SCNVector3(x, -0.02, 0.385)
            let ball = Noir.node(SCNSphere(radius: 0.07), ink)
            ball.scale = SCNVector3(0.82, 1.18, 0.45)
            eye.addChildNode(ball)
            eye.addChildNode(Noir.node(SCNSphere(radius: 0.02), Noir.material(NSColor.white, emission: NSColor.white), at: SCNVector3(0.022, 0.035, 0.03)))
            eye.addChildNode(Noir.node(SCNSphere(radius: 0.01), Noir.material(NSColor.white, emission: NSColor.white), at: SCNVector3(-0.02, -0.03, 0.03)))
            head.addChildNode(eye)
            eyes.append(eye)
            let brow = Noir.node(SCNCapsule(capRadius: 0.017, height: 0.11), hair, at: SCNVector3(x, 0.13, 0.39))
            head.addChildNode(brow)
            brows.append(brow)
            let cheek = Noir.node(SCNSphere(radius: 0.075), Noir.material(NSColor(red: 1, green: 0.45, blue: 0.5, alpha: 1), rough: 0.6),
                                  at: SCNVector3(x * 1.7, -0.1, 0.34))
            cheek.scale = SCNVector3(1, 0.5, 0.3)
            head.addChildNode(cheek)
            cheeks.append(cheek)
        }
        let lips = Noir.material(NSColor(red: 0.35, green: 0.10, blue: 0.12, alpha: 1), rough: 0.4)
        for (kind, geometry) in [(NoirFace.Mouth.smile, Noir.crescent(width: 0.13, depth: 0.03, up: true)),
                                 (.frown, Noir.crescent(width: 0.11, depth: 0.025, up: false)),
                                 (.flat, SCNCapsule(capRadius: 0.012, height: 0.09) as SCNGeometry),
                                 (.open, SCNSphere(radius: 0.045) as SCNGeometry)] {
            let mouth = Noir.node(geometry, lips, at: SCNVector3(0, -0.16, 0.4))
            if kind == .flat { mouth.eulerAngles.z = .pi / 2 }
            if kind == .open { mouth.scale = SCNVector3(1, 0.8, 0.4) }
            head.addChildNode(mouth)
            mouths[kind] = mouth
        }
        sweat.geometry = SCNSphere(radius: 0.04)
        sweat.geometry?.materials = [Noir.material(NSColor(red: 0.6, green: 0.85, blue: 1, alpha: 1), rough: 0.05, clearCoat: 1)]
        sweat.scale = SCNVector3(0.8, 1.2, 0.6)
        sweat.position = SCNVector3(0.33, 0.2, 0.3)
        head.addChildNode(sweat)
    }

    func pose(_ pose: Pose) {
        let face = pose.face
        for (i, eye) in eyes.enumerated() {
            eye.scale = SCNVector3(1, max(0.08, face.eyes), 1)
            eye.position = SCNVector3((i == 0 ? -0.15 : 0.15) + face.look.x * 0.02, -0.02 + face.look.y * 0.02, 0.385)
        }
        for (i, brow) in brows.enumerated() {
            let side: CGFloat = i == 0 ? -1 : 1
            brow.eulerAngles.z = .pi / 2 - side * face.brows * 0.35
            brow.position.y = 0.13 + (face.brows < 0 ? 0.02 : 0)
        }
        for cheek in cheeks { cheek.opacity = face.blush * 0.8 }
        for (kind, mouth) in mouths { mouth.isHidden = kind != face.mouth }
        sweat.isHidden = !face.sweat
        let (left, right): (SCNVector3, SCNVector3) = {
            switch pose.arms {
            case .down: return (SCNVector3(0, 0, -0.08), SCNVector3(0, 0, 0.08))
            case .carry, .showing: return (SCNVector3(-1.25, 0, -0.25), SCNVector3(-1.25, 0, 0.25))
            case .type: return (SCNVector3(-1.0, 0, -0.2), SCNVector3(-1.0, 0, 0.2))
            case .press: return (SCNVector3(-1.0, 0, -0.2), SCNVector3(-0.85, 0, 0.12))
            case .cheer: return (SCNVector3(0, 0, -2.6), SCNVector3(0, 0, 2.6))
            }
        }()
        leftArm.eulerAngles = left
        rightArm.eulerAngles = right
        head.eulerAngles = SCNVector3(pose.arms == .type || pose.arms == .press ? 0.12 : 0, 0, 0)
    }
}

// MARK: - The detective

/// Wingman as a detective: the app's speech bubble in glossy candy plastic, a fedora, a magnifying glass.
@MainActor
final class NoirDetective {
    struct Pose {
        var face = NoirFace(eyes: 1, look: .zero, brows: 0.3, mouth: .smile, blush: 0)
        /// 0 at the side … 1 raised.
        var glass: Double = 0
        /// Where the glass hovers, when it is over something rather than before an eye.
        var glassAt: SCNVector3? = nil
        /// How much the eye behind the glass swells.
        var glassEye: Double = 0
        var lookUp: Double = 0
        var hatTip: Double = 0
    }

    let root = SCNNode()
    private let body = SCNNode()
    private let hat = SCNNode()
    private let glass = SCNNode()
    private var eyes: [SCNNode] = []
    private var mouths: [NoirFace.Mouth: SCNNode] = [:]
    private let arm = SCNNode()

    init() {
        body.position = SCNVector3(0, 1.48, 0)
        root.addChildNode(body)
        let candy = Noir.material(NoirArt.gradient([NSColor(red: 0.31, green: 0.27, blue: 0.95, alpha: 1), NSColor(red: 0.15, green: 0.80, blue: 0.85, alpha: 1)]),
                                  rough: 0.25, emission: NSColor(red: 0.04, green: 0.05, blue: 0.16, alpha: 1), clearCoat: 1)
        body.addChildNode(Noir.node(SCNBox(width: 0.92, height: 0.74, length: 0.6, chamferRadius: 0.3), candy))
        let tail = Noir.node(SCNCone(topRadius: 0, bottomRadius: 0.11, height: 0.26), candy, at: SCNVector3(-0.26, -0.4, 0))
        tail.eulerAngles.z = -0.5
        body.addChildNode(tail)
        let white = Noir.material(NSColor.white, rough: 0.2, clearCoat: 1)
        let ink = Noir.material(NSColor(red: 0.04, green: 0.04, blue: 0.10, alpha: 1), rough: 0.05, clearCoat: 1)
        for x in [-0.17, 0.17] {
            let eye = SCNNode()
            eye.position = SCNVector3(x, 0.06, 0.29)
            let ball = Noir.node(SCNSphere(radius: 0.1), white)
            ball.scale = SCNVector3(0.85, 1.05, 0.4)
            eye.addChildNode(ball)
            eye.addChildNode(Noir.node(SCNSphere(radius: 0.052), ink, at: SCNVector3(0, -0.01, 0.03)))
            eye.addChildNode(Noir.node(SCNSphere(radius: 0.015), Noir.material(NSColor.white, emission: NSColor.white), at: SCNVector3(0.018, 0.02, 0.07)))
            body.addChildNode(eye)
            eyes.append(eye)
        }
        let lips = Noir.material(NSColor(red: 0.06, green: 0.05, blue: 0.16, alpha: 1), rough: 0.3)
        for (kind, geometry) in [(NoirFace.Mouth.smile, Noir.crescent(width: 0.14, depth: 0.03, up: true) as SCNGeometry),
                                 (.flat, SCNCapsule(capRadius: 0.012, height: 0.1) as SCNGeometry),
                                 (.open, SCNSphere(radius: 0.045) as SCNGeometry), (.frown, Noir.crescent(width: 0.12, depth: 0.025, up: false) as SCNGeometry)] {
            let mouth = Noir.node(geometry, lips, at: SCNVector3(0, -0.13, 0.305))
            if kind == .flat { mouth.eulerAngles.z = .pi / 2 }
            if kind == .open { mouth.scale = SCNVector3(1, 0.8, 0.4) }
            body.addChildNode(mouth)
            mouths[kind] = mouth
        }
        // A bow tie.
        let bow = Noir.material(NSColor(red: 0.6, green: 0.08, blue: 0.1, alpha: 1), rough: 0.5)
        for side in [-1.0, 1.0] {
            body.addChildNode(Noir.node(SCNCone(topRadius: 0, bottomRadius: 0.05, height: 0.1), bow, at: SCNVector3(side * 0.05, -0.33, 0.25))
                .rotated(z: side * .pi / 2))
        }
        // The fedora.
        let felt = Noir.material(NSColor(red: 0.14, green: 0.13, blue: 0.13, alpha: 1), rough: 0.75)
        hat.addChildNode(Noir.node(SCNCylinder(radius: 0.55, height: 0.025), felt))
        let crown = Noir.node(SCNCylinder(radius: 0.31, height: 0.26), felt, at: SCNVector3(0, 0.14, 0))
        crown.scale = SCNVector3(1, 1, 0.88)
        hat.addChildNode(crown)
        hat.addChildNode(Noir.node(SCNCylinder(radius: 0.315, height: 0.065), Noir.material(NSColor(red: 0.45, green: 0.08, blue: 0.08, alpha: 1), rough: 0.6),
                                   at: SCNVector3(0, 0.05, 0)))
        hat.position = SCNVector3(0.04, 0.4, 0)
        hat.eulerAngles.z = -0.14
        body.addChildNode(hat)
        // A stubby arm in a trench-coat sleeve, holding the glass.
        let coat = Noir.material(NSColor(red: 0.74, green: 0.62, blue: 0.42, alpha: 1), rough: 0.8)
        arm.position = SCNVector3(0.42, -0.12, 0.05)
        arm.addChildNode(Noir.node(SCNCapsule(capRadius: 0.07, height: 0.3), coat, at: SCNVector3(0, -0.1, 0)))
        arm.addChildNode(Noir.node(SCNSphere(radius: 0.075), Noir.material(NSColor.white, rough: 0.6), at: SCNVector3(0, -0.24, 0)))
        body.addChildNode(arm)
        let brass = Noir.material(NSColor(red: 0.85, green: 0.65, blue: 0.3, alpha: 1), rough: 0.25, metal: 1)
        glass.addChildNode(Noir.node(SCNTorus(ringRadius: 0.15, pipeRadius: 0.02), brass).rotated(x: .pi / 2))
        glass.addChildNode(Noir.node(SCNCylinder(radius: 0.022, height: 0.24), Noir.material(NSColor(red: 0.25, green: 0.12, blue: 0.06, alpha: 1), rough: 0.4),
                                     at: SCNVector3(0, -0.27, 0)))
        root.addChildNode(glass)
        let stand = SCNNode(geometry: SCNSphere(radius: 0.4))
        stand.isHidden = true
        root.addChildNode(stand)
    }

    func pose(_ pose: Pose) {
        let face = pose.face
        for (i, eye) in eyes.enumerated() {
            let swell = i == 1 ? 1 + 0.7 * pose.glassEye : 1
            eye.scale = SCNVector3(swell, swell * max(0.08, face.eyes), swell)
            eye.position = SCNVector3((i == 0 ? -0.17 : 0.17) + face.look.x * 0.03, 0.06 + face.look.y * 0.03, 0.29 + (swell - 1) * 0.03)
        }
        for (kind, mouth) in mouths { mouth.isHidden = kind != face.mouth }
        body.eulerAngles = SCNVector3(-pose.lookUp * 0.3, 0, 0)
        hat.position = SCNVector3(0.04, 0.4 + 0.12 * pose.hatTip, 0.04 * pose.hatTip)
        hat.eulerAngles = SCNVector3(-0.25 * pose.hatTip, 0, -0.14 + 0.2 * pose.hatTip)
        // The glass rests by the side, comes up before the right eye, or hovers over a clue.
        if let at = pose.glassAt {
            glass.position = SCNVector3(at.x - root.position.x, at.y, at.z - root.position.z)
            glass.eulerAngles = SCNVector3(-1.2, 0, 0)
        } else {
            let g = pose.glass
            glass.position = SCNVector3(0.55 - 0.38 * g, 1.2 + 0.36 * g, 0.2 + 0.18 * g)
            glass.eulerAngles = SCNVector3(0, 0, -0.5 * (1 - g))
        }
        arm.eulerAngles = SCNVector3(-1.2 * pose.glass, 0, 0.5 * pose.glass)
    }
}

// MARK: - The laptop

@MainActor
final class NoirLaptop {
    let root = SCNNode()
    private let lid = SCNNode()
    private let display = SCNMaterial()

    init() {
        let aluminium = Noir.material(NSColor(red: 0.30, green: 0.30, blue: 0.33, alpha: 1), rough: 0.45, metal: 0.7)
        root.addChildNode(Noir.node(SCNBox(width: 0.62, height: 0.022, length: 0.42, chamferRadius: 0.01), aluminium))
        root.addChildNode(Noir.node(SCNBox(width: 0.54, height: 0.004, length: 0.2, chamferRadius: 0.002),
                                    Noir.material(NSColor(white: 0.08, alpha: 1), rough: 0.6), at: SCNVector3(0, 0.012, -0.05)))
        lid.position = SCNVector3(0, 0.011, -0.21)
        lid.eulerAngles.x = -0.3
        lid.addChildNode(Noir.node(SCNBox(width: 0.62, height: 0.41, length: 0.012, chamferRadius: 0.006), aluminium, at: SCNVector3(0, 0.205, 0)))
        display.lightingModel = .constant
        display.diffuse.contents = NSColor.black
        let screen = SCNNode(geometry: SCNPlane(width: 0.58, height: 0.3625))
        screen.geometry?.materials = [display]
        screen.position = SCNVector3(0, 0.205, 0.0065)
        screen.castsShadow = false
        lid.addChildNode(screen)
        // The app's icon as a sticker on the back of the lid.
        let sticker = Noir.node(SCNPlane(width: 0.1, height: 0.1),
                                Noir.material(NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath), rough: 0.5), at: SCNVector3(0, 0.22, -0.0065))
        sticker.eulerAngles.y = .pi
        sticker.eulerAngles.z = 0.15
        lid.addChildNode(sticker)
        root.addChildNode(lid)
        // The screen lights whatever is in front of it.
        let glow = SCNLight()
        glow.type = .omni
        glow.color = NSColor(red: 0.6, green: 0.65, blue: 1, alpha: 1)
        glow.intensity = 6
        glow.attenuationEndDistance = 0.7
        let glowNode = SCNNode()
        glowNode.light = glow
        glowNode.position = SCNVector3(0, 0.25, 0.15)
        lid.addChildNode(glowNode)
    }

    func screen(_ image: NSImage) { display.diffuse.contents = image }

    /// On the desk; `scale` below 1 sizes it for the client's small hands rather than for a close-up.
    func place(on point: SCNVector3, facing angle: Double, scale: Double = 1) {
        root.position = point
        root.eulerAngles = SCNVector3(0, angle, 0)
        root.scale = SCNVector3(scale, scale, scale)
        lid.eulerAngles.x = -0.3
    }

    /// Closed, under the client's arms as they run in.
    func carry(by lead: NoirLead) {
        let at = lead.root.convertPosition(SCNVector3(0, 1.0, 0.42), to: nil)
        root.position = at
        root.eulerAngles = SCNVector3(-1.3, lead.root.eulerAngles.y, 0)
        root.scale = SCNVector3(0.7, 0.7, 0.7)
        lid.eulerAngles.x = -1.55
    }

    /// Held open towards whoever the client faces, the chat on it.
    func show(by lead: NoirLead, image: NSImage) {
        let at = lead.root.convertPosition(SCNVector3(0, 1.0, 0.55), to: nil)
        root.position = at
        // The screen faces where the client faces: towards the detective.
        root.eulerAngles = SCNVector3(0.25, lead.root.eulerAngles.y, 0)
        root.scale = SCNVector3(0.7, 0.7, 0.7)
        lid.eulerAngles.x = -0.25
        screen(image)
    }
}
