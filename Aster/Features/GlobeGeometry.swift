import SceneKit

/// Globe geometry built by hand. SceneKit's own SCNSphere does not document
/// how it lays out texture coordinates, and guessing put every flag on the
/// wrong meridian — here the sphere's UVs and the marker placement share one
/// formula, so they cannot drift apart.
enum GlobeGeometry {
  /// Equirectangular convention: longitude −180…180 maps to u 0…1 and
  /// latitude 90…−90 maps to v 0…1.
  static func position(lat: Double, lon: Double, radius: Double) -> SCNVector3 {
    let phi = lat * .pi / 180
    let lambda = lon * .pi / 180
    return SCNVector3(
      radius * cos(phi) * cos(lambda),
      radius * sin(phi),
      -radius * cos(phi) * sin(lambda))
  }

  static func sphere(radius: Double, columns: Int = 144, rows: Int = 72) -> SCNGeometry {
    var vertices: [SCNVector3] = []
    var normals: [SCNVector3] = []
    var texcoords: [CGPoint] = []

    for row in 0...rows {
      let v = Double(row) / Double(rows)
      let lat = 90 - v * 180
      for column in 0...columns {
        let u = Double(column) / Double(columns)
        let lon = -180 + u * 360
        let point = position(lat: lat, lon: lon, radius: radius)
        vertices.append(point)
        normals.append(
          SCNVector3(point.x / radius, point.y / radius, point.z / radius))
        texcoords.append(CGPoint(x: u, y: v))
      }
    }

    var indices: [Int32] = []
    let stride = columns + 1
    for row in 0..<rows {
      for column in 0..<columns {
        let topLeft = Int32(row * stride + column)
        let topRight = topLeft + 1
        let bottomLeft = Int32((row + 1) * stride + column)
        let bottomRight = bottomLeft + 1
        indices.append(contentsOf: [topLeft, bottomLeft, topRight])
        indices.append(contentsOf: [topRight, bottomLeft, bottomRight])
      }
    }

    return SCNGeometry(
      sources: [
        SCNGeometrySource(vertices: vertices),
        SCNGeometrySource(normals: normals),
        SCNGeometrySource(textureCoordinates: texcoords),
      ],
      elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
  }

  /// Thick arc: a tube swept along the great-circle-ish path so the link
  /// reads as a solid ribbon instead of a hairline.
  static func arc(
    from: (lat: Double, lon: Double), to: (lat: Double, lon: Double),
    globeRadius: Double, thickness: Double, steps: Int = 72, sides: Int = 6
  ) -> SCNGeometry {
    var deltaLon = to.lon - from.lon
    if deltaLon > 180 { deltaLon -= 360 }
    if deltaLon < -180 { deltaLon += 360 }
    let deltaLat = to.lat - from.lat
    // Longer hops arc higher, mirroring arcAltitudeAutoScale in the reference.
    let span = min(sqrt(deltaLat * deltaLat + deltaLon * deltaLon) / 180, 1)
    let peak = 0.12 + span * 0.55

    var path: [SCNVector3] = []
    for step in 0...steps {
      let t = Double(step) / Double(steps)
      let lift = globeRadius * (1.01 + sin(t * .pi) * peak)
      path.append(
        position(lat: from.lat + deltaLat * t, lon: from.lon + deltaLon * t, radius: lift))
    }

    var vertices: [SCNVector3] = []
    var normals: [SCNVector3] = []
    var texcoords: [CGPoint] = []

    for (index, point) in path.enumerated() {
      let previous = path[max(index - 1, 0)]
      let next = path[min(index + 1, path.count - 1)]
      let tangent = normalize(subtract(next, previous))
      // Any vector off the tangent works as a seed for the tube frame.
      let seed = abs(tangent.y) > 0.9 ? SCNVector3(1, 0, 0) : SCNVector3(0, 1, 0)
      let side = normalize(cross(tangent, seed))
      let up = normalize(cross(side, tangent))

      for ring in 0...sides {
        let angle = Double(ring) / Double(sides) * 2 * .pi
        let offset = SCNVector3(
          side.x * cos(angle) * thickness + up.x * sin(angle) * thickness,
          side.y * cos(angle) * thickness + up.y * sin(angle) * thickness,
          side.z * cos(angle) * thickness + up.z * sin(angle) * thickness)
        vertices.append(
          SCNVector3(point.x + offset.x, point.y + offset.y, point.z + offset.z))
        normals.append(normalize(offset))
        texcoords.append(
          CGPoint(x: Double(index) / Double(steps), y: Double(ring) / Double(sides)))
      }
    }

    var indices: [Int32] = []
    let stride = sides + 1
    for segment in 0..<steps {
      for ring in 0..<sides {
        let a = Int32(segment * stride + ring)
        let b = a + 1
        let c = Int32((segment + 1) * stride + ring)
        let d = c + 1
        indices.append(contentsOf: [a, c, b])
        indices.append(contentsOf: [b, c, d])
      }
    }

    return SCNGeometry(
      sources: [
        SCNGeometrySource(vertices: vertices),
        SCNGeometrySource(normals: normals),
        SCNGeometrySource(textureCoordinates: texcoords),
      ],
      elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
  }

  private static func subtract(_ a: SCNVector3, _ b: SCNVector3) -> SCNVector3 {
    SCNVector3(a.x - b.x, a.y - b.y, a.z - b.z)
  }

  private static func cross(_ a: SCNVector3, _ b: SCNVector3) -> SCNVector3 {
    SCNVector3(
      a.y * b.z - a.z * b.y,
      a.z * b.x - a.x * b.z,
      a.x * b.y - a.y * b.x)
  }

  private static func normalize(_ v: SCNVector3) -> SCNVector3 {
    let length = sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
    guard length > 0 else { return SCNVector3(0, 1, 0) }
    return SCNVector3(v.x / length, v.y / length, v.z / length)
  }
}
