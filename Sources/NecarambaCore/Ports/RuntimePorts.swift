import Foundation

public protocol LayoutAccess: AnyObject {
    func current() -> LayoutID?
    func supported() -> [LayoutID]
    func select(_ id: LayoutID) -> Bool
}
public protocol ContextAccess: AnyObject {
    func current() -> ContextToken?
    func isSafe(_ token: ContextToken) -> Bool
}
public protocol InputRuntimeControl: AnyObject {
    func updatePreferences(_ snapshot: PreferencesSnapshot)
    func invalidateContext(reason: InvalidationReason)
}
