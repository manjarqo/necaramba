public protocol AppRuleStore {
  func apps() throws -> [AppRule]
  func setApp(_ rule: AppRule) throws
  func deleteApp(bundleID: String) throws
}
