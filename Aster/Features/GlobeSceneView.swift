import AppKit
import SceneKit
import SwiftUI

/// Night-lights Earth on a starfield with flag markers and glowing arcs back
/// to this Mac — the globe.gl reference rebuilt with SceneKit. Geometry and
/// marker placement both come from GlobeGeometry so they always agree.
struct GlobeSceneView: NSViewRepresentable {
  let markers: [GlobeMarker]
  let home: (lat: Double, lon: Double)?
  let isDark: Bool
  @Binding var selected: GlobeMarker?

  private static let radius = 1.0
  private static let dashDuration = 1.75
  private static let ringPeriod = 1.25
  private static let rotationDuration = 110.0

  func makeNSView(context: Context) -> SCNView {
    let view = SCNView()
    view.scene = makeScene()
    view.backgroundColor = .black
    view.antialiasingMode = .multisampling4X
    view.allowsCameraControl = true
    view.defaultCameraController.interactionMode = .orbitTurntable
    view.defaultCameraController.inertiaEnabled = true

    let click = NSClickGestureRecognizer(
      target: context.coordinator, action: #selector(Coordinator.handleClick(_:)))
    view.addGestureRecognizer(click)
    context.coordinator.view = view
    return view
  }

  func updateNSView(_ view: SCNView, context: Context) {
    context.coordinator.parent = self
    guard let scene = view.scene else { return }
    if context.coordinator.appliedSignature != signature {
      context.coordinator.appliedSignature = signature
      applyTexture(to: scene)
      rebuildOverlays(in: scene)
    }
    context.coordinator.highlight(selected)
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(parent: self)
  }

  private var signature: String {
    markers.map { "\($0.code)\($0.names.count)\($0.allOnline)" }.joined()
      + (home.map { "\($0.lat),\($0.lon)" } ?? "") + (isDark ? "d" : "l")
  }

  // MARK: - Scene

  private func makeScene() -> SCNScene {
    let scene = SCNScene()
    scene.background.contents = GlobeArt.starfield()

    let globeNode = SCNNode(geometry: GlobeGeometry.sphere(radius: Self.radius))
    globeNode.name = "globe"
    scene.rootNode.addChildNode(globeNode)
    globeNode.runAction(
      .repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: Self.rotationDuration)))

    scene.rootNode.addChildNode(atmosphereNode())

    let cameraNode = SCNNode()
    let camera = SCNCamera()
    camera.fieldOfView = 30
    camera.zNear = 0.05
    camera.zFar = 200
    cameraNode.camera = camera
    let start = home ?? (lat: 20, lon: 110)
    cameraNode.position = GlobeGeometry.position(
      lat: start.lat * 0.5, lon: start.lon, radius: 5.0)
    cameraNode.look(at: SCNVector3Zero, up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))
    scene.rootNode.addChildNode(cameraNode)

    let ambient = SCNLight()
    ambient.type = .ambient
    ambient.intensity = isDark ? 1000 : 600
    let ambientNode = SCNNode()
    ambientNode.light = ambient
    scene.rootNode.addChildNode(ambientNode)

    if !isDark {
      let key = SCNLight()
      key.type = .directional
      key.intensity = 750
      let keyNode = SCNNode()
      keyNode.light = key
      keyNode.position = SCNVector3(4, 3, 6)
      keyNode.look(at: SCNVector3Zero)
      scene.rootNode.addChildNode(keyNode)
    }

    applyTexture(to: scene)
    rebuildOverlays(in: scene)
    return scene
  }

  private func applyTexture(to scene: SCNScene) {
    guard let node = scene.rootNode.childNode(withName: "globe", recursively: false) else {
      return
    }
    let material = SCNMaterial()
    let texture = NSImage(named: isDark ? "earth-night" : "earth-day")
    material.diffuse.contents = texture
    material.diffuse.mipFilter = .linear
    if isDark {
      material.lightingModel = .constant
    } else {
      material.specular.contents = NSColor(white: 0.28, alpha: 1)
      material.shininess = 0.1
      material.lightingModel = .blinn
    }
    node.geometry?.materials = [material]
  }

  /// Thin fresnel rim hugging the surface. The visible band spans from the
  /// globe's silhouette out to the shell's, so a wide shell renders as a
  /// donut instead of an atmosphere — keep the offset tiny.
  private func atmosphereNode() -> SCNNode {
    let shell = SCNSphere(radius: Self.radius * 1.025)
    shell.segmentCount = 96
    let material = SCNMaterial()
    material.lightingModel = .constant
    material.blendMode = .add
    material.writesToDepthBuffer = false
    material.cullMode = .front
    material.shaderModifiers = [
      .surface: """
        #pragma arguments
        float3 atmoColor;
        #pragma body
        float rim = pow(1.0 - abs(dot(normalize(_surface.normal), normalize(_surface.view))), 2.5);
        _surface.diffuse = float4(atmoColor * rim * 0.75, rim * 0.35);
        """
    ]
    let accent = NSColor(AsterColor.accent).usingColorSpace(.deviceRGB) ?? .systemBlue
    material.setValue(
      SCNVector3(accent.redComponent * 0.55, accent.greenComponent * 0.8, 1.0),
      forKey: "atmoColor")
    shell.materials = [material]
    return SCNNode(geometry: shell)
  }

  private func rebuildOverlays(in scene: SCNScene) {
    guard let globe = scene.rootNode.childNode(withName: "globe", recursively: false) else {
      return
    }
    globe.childNodes.forEach { $0.removeFromParentNode() }

    for marker in markers {
      let flag = SCNNode(geometry: flagPlate(marker))
      flag.position = GlobeGeometry.position(
        lat: marker.lat, lon: marker.lon, radius: Self.radius * 1.07)
      flag.constraints = [SCNBillboardConstraint()]
      flag.name = "marker:\(marker.code)"
      globe.addChildNode(flag)
      globe.addChildNode(pulseRing(at: marker))

      if let home {
        globe.addChildNode(arcNode(from: (marker.lat, marker.lon), to: home))
      }
    }

    if let home {
      let node = SCNNode(geometry: homePlate())
      node.position = GlobeGeometry.position(
        lat: home.lat, lon: home.lon, radius: Self.radius * 1.04)
      node.constraints = [SCNBillboardConstraint()]
      node.runAction(
        .repeatForever(
          .sequence([
            .group([.scale(to: 1.3, duration: 1), .fadeOpacity(to: 0.5, duration: 1)]),
            .group([.scale(to: 1, duration: 1), .fadeOpacity(to: 1, duration: 1)]),
          ])))
      globe.addChildNode(node)
    }
  }

  private func flagPlate(_ marker: GlobeMarker) -> SCNGeometry {
    let plane = SCNPlane(width: 0.19, height: 0.135)
    let material = SCNMaterial()
    material.diffuse.contents = GlobeArt.flagImage(
      marker.flag, glow: NSColor(marker.allOnline ? AsterColor.online : AsterColor.offline))
    material.diffuse.mipFilter = .linear
    material.lightingModel = .constant
    material.isDoubleSided = true
    material.writesToDepthBuffer = false
    plane.materials = [material]
    return plane
  }

  private func pulseRing(at marker: GlobeMarker) -> SCNNode {
    let plane = SCNPlane(width: 0.3, height: 0.3)
    let material = SCNMaterial()
    material.diffuse.contents = GlobeArt.ringImage(NSColor(AsterColor.accent))
    material.lightingModel = .constant
    material.blendMode = .add
    material.writesToDepthBuffer = false
    material.isDoubleSided = true
    plane.materials = [material]

    let node = SCNNode(geometry: plane)
    node.position = GlobeGeometry.position(
      lat: marker.lat, lon: marker.lon, radius: Self.radius * 1.005)
    node.constraints = [SCNBillboardConstraint()]
    node.opacity = 0
    node.runAction(
      .repeatForever(
        .sequence([
          .group([.scale(to: 0.25, duration: 0), .fadeOpacity(to: 0.85, duration: 0)]),
          .group([
            .scale(to: 1.5, duration: Self.ringPeriod),
            .fadeOpacity(to: 0, duration: Self.ringPeriod),
          ]),
        ])))
    return node
  }

  private func homePlate() -> SCNGeometry {
    let plane = SCNPlane(width: 0.12, height: 0.12)
    let material = SCNMaterial()
    material.diffuse.contents = GlobeArt.homeImage(NSColor(AsterColor.accent))
    material.lightingModel = .constant
    material.writesToDepthBuffer = false
    material.isDoubleSided = true
    plane.materials = [material]
    return plane
  }

  private func arcNode(from: (lat: Double, lon: Double), to: (lat: Double, lon: Double))
    -> SCNNode
  {
    let geometry = GlobeGeometry.arc(
      from: from, to: to, globeRadius: Self.radius, thickness: 0.008)
    let material = SCNMaterial()
    material.diffuse.contents = GlobeArt.dashImage(NSColor(AsterColor.accent))
    material.diffuse.wrapS = .repeat
    material.diffuse.wrapT = .clamp
    material.diffuse.contentsTransform = SCNMatrix4MakeScale(7, 1, 1)
    material.lightingModel = .constant
    material.blendMode = .add
    material.writesToDepthBuffer = false
    geometry.materials = [material]

    let scroll = CABasicAnimation(keyPath: "contentsTransform")
    scroll.fromValue = SCNMatrix4MakeScale(7, 1, 1)
    scroll.toValue = SCNMatrix4Mult(
      SCNMatrix4MakeScale(7, 1, 1), SCNMatrix4MakeTranslation(-1, 0, 0))
    scroll.duration = Self.dashDuration
    scroll.repeatCount = .infinity
    material.diffuse.addAnimation(scroll, forKey: "dash")

    return SCNNode(geometry: geometry)
  }

  final class Coordinator: NSObject {
    var parent: GlobeSceneView
    weak var view: SCNView?
    var appliedSignature = ""
    private var highlighted: SCNNode?

    init(parent: GlobeSceneView) {
      self.parent = parent
    }

    @objc func handleClick(_ gesture: NSClickGestureRecognizer) {
      guard let view else { return }
      let hits = view.hitTest(
        gesture.location(in: view), options: [.searchMode: SCNHitTestSearchMode.all.rawValue])
      for hit in hits {
        guard let name = hit.node.name, name.hasPrefix("marker:") else { continue }
        let code = String(name.dropFirst("marker:".count))
        parent.selected =
          parent.selected?.code == code ? nil : parent.markers.first { $0.code == code }
        return
      }
      parent.selected = nil
    }

    func highlight(_ marker: GlobeMarker?) {
      highlighted?.scale = SCNVector3(1, 1, 1)
      guard let marker, let view,
        let node = view.scene?.rootNode.childNode(withName: "globe", recursively: false)?
          .childNode(withName: "marker:\(marker.code)", recursively: false)
      else {
        highlighted = nil
        return
      }
      node.scale = SCNVector3(1.5, 1.5, 1.5)
      highlighted = node
    }
  }
}

struct GlobeMarker: Identifiable {
  let id: String
  let code: String
  let flag: String
  let lat: Double
  let lon: Double
  let names: [String]
  let allOnline: Bool
}
