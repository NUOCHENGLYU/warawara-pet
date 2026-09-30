import Foundation

final class PetPositionStore {
    private let defaults: UserDefaults
    private let xKey: String
    private let yKey: String

    init(defaults: UserDefaults = .standard, keyPrefix: String = "pet.position") {
        self.defaults = defaults
        xKey = keyPrefix + ".x"
        yKey = keyPrefix + ".y"
    }

    func loadOrigin() -> CGPoint? {
        guard let x = defaults.object(forKey: xKey) as? Double,
              let y = defaults.object(forKey: yKey) as? Double else {
            return nil
        }
        return CGPoint(x: x, y: y)
    }

    func saveOrigin(_ origin: CGPoint) {
        defaults.set(origin.x, forKey: xKey)
        defaults.set(origin.y, forKey: yKey)
    }
}
