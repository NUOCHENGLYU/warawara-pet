import Foundation

struct EllipseHitRegion {
    let center: CGPoint
    let radiusX: CGFloat
    let radiusY: CGFloat

    func contains(_ point: CGPoint) -> Bool {
        let dx = (point.x - center.x) / radiusX
        let dy = (point.y - center.y) / radiusY
        return dx * dx + dy * dy <= 1
    }

    static func petDefault(in bounds: CGRect) -> EllipseHitRegion {
        EllipseHitRegion(
            center: PetMetrics.visualCenter,
            radiusX: 55,
            radiusY: 64
        )
    }
}
