import Foundation

final class ActiveInstanceLease {
  private static let lock = NSLock()
  private static var activeToken: Int = 0

  static func claim() -> Int {
    lock.lock()
    defer { lock.unlock() }
    activeToken &+= 1
    return activeToken
  }

  static func isActive(_ token: Int) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    return token == activeToken
  }
}

