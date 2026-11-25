import AppKit
import CoreGraphics

/// Presets for the 3×3 bicubic Bézier Mesh Warp transform.
nonisolated enum WarpMeshPreset: String, CaseIterable, Sendable {
    case custom = "Custom"
    case arc = "Arc"
    case arch = "Arch"
    case bulge = "Bulge"
    case flag = "Flag"
    case wave = "Wave"
}

/// A 4×4 bicubic Bézier warp mesh (16 control points in document pixel coordinates, row-major `row * 4 + col`).
nonisolated struct WarpMesh: Equatable, Sendable {
    var points: [CGPoint] // Always 16 points.

    init(points: [CGPoint]) {
        self.points = points
    }

    var isValid: Bool {
        points.count == 16 && points.allSatisfy { $0.x.isFinite && $0.y.isFinite && abs($0.x) <= 1_000_000 && abs($0.y) <= 1_000_000 }
    }

    static func identity(for transform: LayerTransform) -> WarpMesh {
        var pts: [CGPoint] = []
        pts.reserveCapacity(16)
        for row in 0..<4 {
            let v = CGFloat(row) / 3.0
            for col in 0..<4 {
                let u = CGFloat(col) / 3.0
                pts.append(transform.point(CGPoint(x: u, y: v)))
            }
        }
        return WarpMesh(points: pts)
    }

    static func preset(_ kind: WarpMeshPreset, for transform: LayerTransform, bend: CGFloat = 0.45) -> WarpMesh {
        var mesh = identity(for: transform)
        guard kind != .custom else { return mesh }
        let b = max(-1, min(1, bend))
        let h = transform.size.height
        let w = transform.size.width
        // Axis vectors in document space (respecting layer rotation).
        let right = CGPoint(x: transform.point(CGPoint(x: 1, y: 0)).x - transform.point(.zero).x,
                            y: transform.point(CGPoint(x: 1, y: 0)).y - transform.point(.zero).y)
        let down = CGPoint(x: transform.point(CGPoint(x: 0, y: 1)).x - transform.point(.zero).x,
                           y: transform.point(CGPoint(x: 0, y: 1)).y - transform.point(.zero).y)
        let rLen = max(1e-5, hypot(right.x, right.y))
        let dLen = max(1e-5, hypot(down.x, down.y))
        let rx = right.x / rLen, ry = right.y / rLen
        let dx = down.x / dLen, dy = down.y / dLen

        for row in 0..<4 {
            let v = CGFloat(row) / 3.0 // 0..1 top to bottom
            let nv = v * 2 - 1 // -1..1
            for col in 0..<4 {
                let u = CGFloat(col) / 3.0 // 0..1 left to right
                let nu = u * 2 - 1 // -1..1
                var shiftX: CGFloat = 0
                var shiftY: CGFloat = 0
                switch kind {
                case .custom:
                    break
                case .arch:
                    shiftY = -b * h * 0.55 * (1 - nu * nu)
                case .arc:
                    shiftY = -b * h * 0.55 * (1 - nu * nu)
                    shiftX = b * w * 0.12 * nu * (1 - v)
                case .bulge:
                    shiftY = b * h * 0.45 * nv * (1 - nu * nu)
                    shiftX = b * w * 0.15 * nu * (1 - nv * nv)
                case .flag:
                    shiftY = -b * h * 0.45 * sin(nu * .pi)
                case .wave:
                    shiftY = -b * h * 0.35 * sin(nu * 2 * .pi)
                }
                let idx = row * 4 + col
                mesh.points[idx].x += rx * shiftX + dx * shiftY
                mesh.points[idx].y += ry * shiftX + dy * shiftY
            }
        }
        return mesh
    }

    /// Evaluates the bicubic Bézier surface at `(u, v) ∈ [0, 1]²`.
    func evaluate(u: CGFloat, v: CGFloat) -> CGPoint {
        let bu = Self.bernstein(u)
        let bv = Self.bernstein(v)
        var x: Double = 0, y: Double = 0
        for row in 0..<4 {
            let wy = bv[row]
            let base = row * 4
            for col in 0..<4 {
                let w = bu[col] * wy
                let p = points[base + col]
                x += Double(p.x) * w
                y += Double(p.y) * w
            }
        }
        return CGPoint(x: x, y: y)
    }

    private static func bernstein(_ t: CGFloat) -> SIMD4<Double> {
        let d = Double(t), u = 1 - d
        return SIMD4<Double>(u * u * u, 3 * u * u * d, 3 * u * d * d, d * d * d)
    }

    /// Renders `image` through this 4×4 bicubic Bézier warp mesh using subdivided triangle barycentric bilinear sampling.
    static func render(_ image: CGImage, mesh: WarpMesh, flipX: Bool = false, flipY: Bool = false,
                       isMask: Bool = false, limit: CGFloat? = nil) throws -> (image: CGImage, transform: LayerTransform) {
        guard mesh.isValid else { throw ProjectError.invalid }
        let gridN = limit != nil ? 20 : 36
        // Pre-evaluate grid vertices in document coordinates.
        let strideCount = gridN + 1
        var verts = [CGPoint](repeating: .zero, count: strideCount * strideCount)
        var minX = CGFloat.greatestFiniteMagnitude, minY = CGFloat.greatestFiniteMagnitude
        var maxX = -CGFloat.greatestFiniteMagnitude, maxY = -CGFloat.greatestFiniteMagnitude

        for j in 0...gridN {
            let v = CGFloat(j) / CGFloat(gridN)
            for i in 0...gridN {
                let u = CGFloat(i) / CGFloat(gridN)
                let p = mesh.evaluate(u: u, v: v)
                verts[j * strideCount + i] = p
                if p.x < minX { minX = p.x }
                if p.x > maxX { maxX = p.x }
                if p.y < minY { minY = p.y }
                if p.y > maxY { maxY = p.y }
            }
        }

        let bounds = CGRect(x: floor(minX), y: floor(minY),
                            width: max(1, ceil(maxX) - floor(minX)),
                            height: max(1, ceil(maxY) - floor(minY)))
        guard bounds.width <= DocumentLimits.maxSideExtent, bounds.height <= DocumentLimits.maxSideExtent,
              bounds.width * bounds.height <= DocumentLimits.maxSurfaceExtent else { throw ProjectError.tooLarge }

        let factor = limit.map { min(1, $0 / max(bounds.width, bounds.height)) } ?? 1
        let dstW = max(1, Int((bounds.width * factor).rounded(.up)))
        let dstH = max(1, Int((bounds.height * factor).rounded(.up)))

        // Read source pixels into top-left RGBA8 (or Gray8 for masks).
        let srcW = image.width, srcH = image.height
        let srcCtx = try BrushRaster.context(width: srcW, height: srcH, mask: isMask)
        srcCtx.draw(image, in: CGRect(x: 0, y: 0, width: srcW, height: srcH))
        guard let srcRaw = srcCtx.data else { throw ExportError.render }
        let src = srcRaw.assumingMemoryBound(to: UInt8.self)
        let srcStride = srcCtx.bytesPerRow
        let bpp = isMask ? 1 : 4

        let dstCtx = try BrushRaster.context(width: dstW, height: dstH, mask: isMask)
        guard let dstRaw = dstCtx.data else { throw ExportError.render }
        let dst = dstRaw.assumingMemoryBound(to: UInt8.self)
        let dstStride = dstCtx.bytesPerRow

        let invN = Float(1.0) / Float(gridN)
        let fSrcW = Float(srcW - 1), fSrcH = Float(srcH - 1)
        let originX = bounds.minX, originY = bounds.minY

        func toDst(_ p: CGPoint) -> (Float, Float) {
            (Float((p.x - originX) * factor), Float((p.y - originY) * factor))
        }

        func rasterizeTri(_ p0: (Float, Float), _ uv0: (Float, Float),
                          _ p1: (Float, Float), _ uv1: (Float, Float),
                          _ p2: (Float, Float), _ uv2: (Float, Float)) {
            let xMin = max(0, Int(floor(min(p0.0, min(p1.0, p2.0)))))
            let xMax = min(dstW - 1, Int(ceil(max(p0.0, max(p1.0, p2.0)))))
            let yMin = max(0, Int(floor(min(p0.1, min(p1.1, p2.1)))))
            let yMax = min(dstH - 1, Int(ceil(max(p0.1, max(p1.1, p2.1)))))
            guard xMin <= xMax, yMin <= yMax else { return }

            let denom = (p1.1 - p2.1) * (p0.0 - p2.0) + (p2.0 - p1.0) * (p0.1 - p2.1)
            guard abs(denom) > 1e-6 else { return }
            let invDenom = 1.0 / denom

            for y in yMin...yMax {
                let py = Float(y) + 0.5
                let dstRow = dst + y * dstStride
                for x in xMin...xMax {
                    let px = Float(x) + 0.5
                    let w0 = ((p1.1 - p2.1) * (px - p2.0) + (p2.0 - p1.0) * (py - p2.1)) * invDenom
                    let w1 = ((p2.1 - p0.1) * (px - p2.0) + (p0.0 - p2.0) * (py - p2.1)) * invDenom
                    let w2 = 1.0 - w0 - w1
                    guard w0 >= -1e-4 && w1 >= -1e-4 && w2 >= -1e-4 else { continue }

                    var u = max(0, min(1, w0 * uv0.0 + w1 * uv1.0 + w2 * uv2.0))
                    var v = max(0, min(1, w0 * uv0.1 + w1 * uv1.1 + w2 * uv2.1))
                    if flipX { u = 1 - u }
                    if flipY { v = 1 - v }

                    let sx = u * fSrcW, sy = v * fSrcH
                    let ix0 = Int(sx), iy0 = Int(sy)
                    let ix1 = min(srcW - 1, ix0 + 1), iy1 = min(srcH - 1, iy0 + 1)
                    let fx = sx - Float(ix0), fy = sy - Float(iy0)

                    let r0 = src + iy0 * srcStride
                    let r1 = src + iy1 * srcStride
                    let d = dstRow + x * bpp
                    for k in 0..<bpp {
                        let c00 = Float(r0[ix0 * bpp + k])
                        let c10 = Float(r0[ix1 * bpp + k])
                        let c01 = Float(r1[ix0 * bpp + k])
                        let c11 = Float(r1[ix1 * bpp + k])
                        let top = c00 + (c10 - c00) * fx
                        let bot = c01 + (c11 - c01) * fx
                        d[k] = UInt8(max(0, min(255, (top + (bot - top) * fy).rounded())))
                    }
                }
            }
        }

        for j in 0..<gridN {
            let v0 = Float(j) * invN, v1 = Float(j + 1) * invN
            for i in 0..<gridN {
                let u0 = Float(i) * invN, u1 = Float(i + 1) * invN
                let p00 = toDst(verts[j * strideCount + i])
                let p10 = toDst(verts[j * strideCount + i + 1])
                let p01 = toDst(verts[(j + 1) * strideCount + i])
                let p11 = toDst(verts[(j + 1) * strideCount + i + 1])
                rasterizeTri(p00, (u0, v0), p10, (u1, v0), p11, (u1, v1))
                rasterizeTri(p00, (u0, v0), p11, (u1, v1), p01, (u0, v1))
            }
        }

        guard let outImage = dstCtx.makeImage() else { throw ExportError.render }
        let outTransform = LayerTransform(origin: bounds.origin, size: bounds.size)
        return (outImage, outTransform)
    }
}

/// Active Mesh Warp session state on `EditorSession`.
struct MeshWarpEdit: Equatable {
    let layerID: UUID
    let originalTransform: LayerTransform
    var mesh: WarpMesh
    var preset: WarpMeshPreset = .custom
    var bend: Double = 0.45
}

struct MeshWarpPreviewCache {
    let mesh: WarpMesh
    let image: CGImage
    let result: (image: CGImage, transform: LayerTransform)?
}

extension LayerTransform {
    /// Rotates to `degrees` while keeping the unit pivot point `(u, v) ∈ [0, 1]²` fixed in document space.
    nonisolated func rotated(toDegrees degrees: CGFloat, aroundUnitPivot pivot: CGPoint) -> LayerTransform {
        let anchorDoc = point(pivot)
        var next = self
        next.rotation = degrees.truncatingRemainder(dividingBy: 360)
        let movedDoc = next.point(pivot)
        next.origin.x += anchorDoc.x - movedDoc.x
        next.origin.y += anchorDoc.y - movedDoc.y
        return next
    }

    /// Scales to `percent` of `pixelSize` while keeping the unit pivot point `(u, v) ∈ [0, 1]²` fixed in document space.
    nonisolated func scaled(toPercent percent: CGFloat, pixelSize: CGSize, aroundUnitPivot pivot: CGPoint) -> LayerTransform {
        guard percent > 0 else { return self }
        let anchorDoc = point(pivot)
        var next = scaled(toPercent: percent, pixelSize: pixelSize)
        let movedDoc = next.point(pivot)
        next.origin.x += anchorDoc.x - movedDoc.x
        next.origin.y += anchorDoc.y - movedDoc.y
        return next
    }

    /// Computes the 4 document-space corners of this transform sheared independently by `(skewXDeg, skewYDeg)`
    /// around unit pivot `(u, v)`.
    nonisolated func skewedCorners(skewXDegrees: CGFloat, skewYDegrees: CGFloat, pivot: CGPoint = CGPoint(x: 0.5, y: 0.5)) -> [CGPoint] {
        let tx = tan(max(-75, min(75, skewXDegrees)) * .pi / 180)
        let ty = tan(max(-75, min(75, skewYDegrees)) * .pi / 180)
        let pivotDoc = point(pivot)
        let cosR = cos(radians), sinR = sin(radians)
        let unitCorners = [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0), CGPoint(x: 1, y: 1), CGPoint(x: 0, y: 1)]
        return unitCorners.map { c in
            let lx = (c.x - pivot.x) * size.width
            let ly = (c.y - pivot.y) * size.height
            let sx = lx + tx * ly
            let sy = ly + ty * lx
            return CGPoint(x: pivotDoc.x + sx * cosR - sy * sinR,
                           y: pivotDoc.y + sx * sinR + sy * cosR)
        }
    }
}

extension EditorSession {
    /// Applies independent horizontal/vertical skew (in degrees, `-75...75`) to the active transform via live Distort corners.
    func applyTransformSkew(skewX: Double, skewY: Double) {
        let sx = skewX.isFinite ? max(-75, min(75, skewX)) : 0
        let sy = skewY.isFinite ? max(-75, min(75, skewY)) : 0
        transformSkewX = sx
        transformSkewY = sy
        if transformEdit == nil {
            beginTransform(persistent: true)
        }
        guard let edit = transformEdit else { return }
        if edit.corners == nil { beginDistort() }
        let corners = edit.draft.skewedCorners(skewXDegrees: CGFloat(sx), skewYDegrees: CGFloat(sy), pivot: transformPivot)
        previewCorners(corners)
    }

    // MARK: - 3×3 Bicubic Mesh Warp

    func beginMeshWarp(preset: WarpMeshPreset = .custom) {
        guard canTransform, let layer = activeLayer, layer.asset != nil, !layer.isGroup else { return }
        if transformEdit != nil { cancelTransform() }
        tool = .move
        let mesh = preset == .custom ? WarpMesh.identity(for: layer.transform)
                                     : WarpMesh.preset(preset, for: layer.transform, bend: 0.45)
        meshWarpEdit = MeshWarpEdit(layerID: layer.id, originalTransform: layer.transform, mesh: mesh, preset: preset, bend: 0.45)
        meshWarpPreviewCache = nil
    }

    func updateMeshWarpPreset(_ preset: WarpMeshPreset, bend: Double? = nil) {
        guard var edit = meshWarpEdit else { return }
        edit.preset = preset
        if let bend { edit.bend = max(-1, min(1, bend)) }
        if preset != .custom {
            edit.mesh = WarpMesh.preset(preset, for: edit.originalTransform, bend: CGFloat(edit.bend))
        }
        meshWarpEdit = edit
    }

    func moveMeshWarpPoint(at index: Int, to point: CGPoint) {
        guard var edit = meshWarpEdit, edit.mesh.points.indices.contains(index),
              point.x.isFinite, point.y.isFinite else { return }
        edit.mesh.points[index] = point
        edit.preset = .custom
        meshWarpEdit = edit
    }

    func resetMeshWarp() {
        guard var edit = meshWarpEdit else { return }
        edit.mesh = WarpMesh.identity(for: edit.originalTransform)
        edit.preset = .custom
        edit.bend = 0.45
        meshWarpEdit = edit
    }

    func cancelMeshWarp() {
        meshWarpEdit = nil
        meshWarpPreviewCache = nil
    }

    func meshWarpPreview(for layer: ImageLayer) -> (image: CGImage, transform: LayerTransform)? {
        guard let edit = meshWarpEdit, edit.layerID == layer.id, let image = layer.asset?.image else { return nil }
        if let cache = meshWarpPreviewCache, cache.mesh == edit.mesh, cache.image === image {
            return cache.result
        }
        let result = try? WarpMesh.render(image, mesh: edit.mesh,
                                          flipX: edit.originalTransform.flipX,
                                          flipY: edit.originalTransform.flipY,
                                          isMask: false, limit: 1024)
        meshWarpPreviewCache = MeshWarpPreviewCache(mesh: edit.mesh, image: image, result: result)
        return result
    }

    func commitMeshWarp() {
        guard let edit = meshWarpEdit,
              let index = document?.layers.firstIndex(where: { $0.id == edit.layerID }),
              let layer = document?.layers[index], let asset = layer.asset else {
            cancelMeshWarp()
            return
        }
        do {
            let warped = try WarpMesh.render(asset.image, mesh: edit.mesh,
                                             flipX: edit.originalTransform.flipX,
                                             flipY: edit.originalTransform.flipY,
                                             isMask: false)
            let thumb = try PixelInvert.thumbnail(of: warped.image)
            var warpedMask = layer.mask
            if let mask = layer.mask, mask.placement == nil && mask.isLinked {
                if let wm = try? WarpMesh.render(mask.asset.image, mesh: edit.mesh,
                                                 flipX: edit.originalTransform.flipX,
                                                 flipY: edit.originalTransform.flipY,
                                                 isMask: true),
                   let mThumb = try? PixelInvert.thumbnail(of: wm.image) {
                    warpedMask = LayerMask(asset: ImportedImage(image: wm.image, thumbnail: mThumb, name: mask.asset.name),
                                           isEnabled: mask.isEnabled, placement: nil, isLinked: mask.isLinked)
                }
            }
            finishOpacityEdit()
            beginEdit("Warp")
            document?.layers[index].asset = ImportedImage(image: warped.image, thumbnail: thumb, name: asset.name)
            document?.layers[index].transform = warped.transform
            document?.layers[index].mask = warpedMask
            document?.layers[index].shape = nil
            document?.layers[index].text = nil
            document?.layers[index].gradientFill = nil
            endEdit()
            cancelMeshWarp()
        } catch {
            brushError = error.localizedDescription
            cancelMeshWarp()
        }
    }
}
