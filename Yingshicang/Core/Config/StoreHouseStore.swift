import Foundation

/// 多仓与线路的本地持久化（R-29）。
/// 结构「仓 { name, url, lines[] }」是 F-02 明确要求的形态；
/// 持久化键名在文档 5.2 标为待确认，本工程用 `tpc_stores` / `tpc_current_line` 两个键，
/// 并在默认取值清单中声明。
final class StoreHouseStore {
    static let shared = StoreHouseStore()
    private let defaults = UserDefaults.standard
    private let storesKey = "tpc_stores"
    private let currentKey = "tpc_current_line"

    func stores() -> [ConfigStore] {
        guard let data = defaults.data(forKey: storesKey),
              let list = try? JSONDecoder().decode([ConfigStore].self, from: data) else { return [] }
        return list
    }

    func save(_ stores: [ConfigStore]) {
        if let data = try? JSONEncoder().encode(stores) {
            defaults.set(data, forKey: storesKey)
        }
    }

    func add(_ store: ConfigStore) {
        var list = stores()
        list.removeAll { $0.id == store.id }
        list.insert(store, at: 0)
        save(list)
    }

    func remove(storeID: String) {
        save(stores().filter { $0.id != storeID })
    }

    func addLine(_ line: ConfigLine, to storeID: String) {
        var list = stores()
        guard let index = list.firstIndex(where: { $0.id == storeID }) else { return }
        list[index].lines.removeAll { $0.url == line.url }
        list[index].lines.append(line)
        save(list)
    }

    func removeLine(url: String, from storeID: String) {
        var list = stores()
        guard let index = list.firstIndex(where: { $0.id == storeID }) else { return }
        list[index].lines.removeAll { $0.url == url }
        save(list)
    }

    /// 当前生效线路。
    var currentLine: ConfigLine? {
        get {
            guard let data = defaults.data(forKey: currentKey),
                  let line = try? JSONDecoder().decode(ConfigLine.self, from: data) else { return nil }
            return line
        }
        set {
            if let value = newValue, let data = try? JSONEncoder().encode(value) {
                defaults.set(data, forKey: currentKey)
            } else {
                defaults.removeObject(forKey: currentKey)
            }
        }
    }

    func reset() {
        defaults.removeObject(forKey: storesKey)
        defaults.removeObject(forKey: currentKey)
    }
}
