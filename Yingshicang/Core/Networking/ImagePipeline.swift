import UIKit

/// 极简图片管线：内存 NSCache + URLSession 自带磁盘缓存。
/// 海报墙同时会显示几十张图，必须做请求去重，否则同一 URL 被重复拉取。
final class ImagePipeline {
    static let shared = ImagePipeline()

    private let cache = NSCache<NSString, UIImage>()
    private let session = HTTPClient.makeImageSession()
    private let lock = NSLock()
    private var inflight: [String: [(Result<UIImage, Error>) -> Void]] = [:]

    private init() {
        cache.countLimit = 260
        cache.totalCostLimit = 64 * 1024 * 1024
    }

    func cachedImage(for urlString: String) -> UIImage? {
        cache.object(forKey: urlString as NSString)
    }

    func load(_ request: URLRequest, completion: @escaping (Result<UIImage, Error>) -> Void) {
        guard let urlString = request.url?.absoluteString, !urlString.isEmpty else {
            completion(.failure(PipelineError.invalidURL))
            return
        }
        if let cached = cache.object(forKey: urlString as NSString) {
            completion(.success(cached))
            return
        }
        lock.lock()
        if var waiters = inflight[urlString] {
            waiters.append(completion)
            inflight[urlString] = waiters
            lock.unlock()
            return
        }
        inflight[urlString] = [completion]
        lock.unlock()

        session.dataTask(with: request) { [weak self] data, _, _ in
            guard let self = self else { return }
            var result: Result<UIImage, Error> = .failure(PipelineError.decodeFailed)
            if let data = data, let image = UIImage(data: data) {
                self.cache.setObject(image, forKey: urlString as NSString, cost: data.count)
                result = .success(image)
            }
            self.lock.lock()
            let waiters = self.inflight[urlString] ?? []
            self.inflight[urlString] = nil
            self.lock.unlock()
            DispatchQueue.main.async {
                waiters.forEach { $0(result) }
            }
        }.resume()
    }

    enum PipelineError: Error {
        case invalidURL
        case decodeFailed
    }
}
