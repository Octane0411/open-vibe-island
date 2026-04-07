import Foundation
import Network
import os

/// Discovered Mac running Open Island.
struct DiscoveredMac: Identifiable, Hashable {
    let id: String          // NWBrowser.Result identifier
    let name: String        // Human-readable Mac name from Bonjour TXT or service name
    let endpoint: NWEndpoint

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: DiscoveredMac, rhs: DiscoveredMac) -> Bool {
        lhs.id == rhs.id
    }
}

/// Uses NWBrowser to discover macOS instances advertising `_openisland._tcp`.
@MainActor
final class BonjourDiscovery: ObservableObject {
    private static let logger = Logger(subsystem: "app.openisland.mobile", category: "BonjourDiscovery")
    private static let serviceType = "_openisland._tcp"

    @Published private(set) var discoveredMacs: [DiscoveredMac] = []
    @Published private(set) var isSearching = false

    private var browser: NWBrowser?

    func startBrowsing() {
        stopBrowsing()

        let params = NWParameters()
        params.includePeerToPeer = true

        let browser = NWBrowser(for: .bonjour(type: Self.serviceType, domain: nil), using: params)

        browser.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                switch state {
                case .ready:
                    self?.isSearching = true
                    Self.logger.info("Bonjour browser ready")
                case let .failed(error):
                    Self.logger.error("Bonjour browser failed: \(error.localizedDescription)")
                    self?.isSearching = false
                case .cancelled:
                    self?.isSearching = false
                default:
                    break
                }
            }
        }

        browser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor [weak self] in
                self?.updateDiscoveredMacs(from: results)
            }
        }

        browser.start(queue: .main)
        self.browser = browser
    }

    func stopBrowsing() {
        browser?.cancel()
        browser = nil
        isSearching = false
        discoveredMacs = []
    }

    // MARK: - Private

    private func updateDiscoveredMacs(from results: Set<NWBrowser.Result>) {
        discoveredMacs = results.compactMap { result in
            let name: String
            let id: String

            switch result.endpoint {
            case let .service(serviceName, serviceType, domain, _):
                name = serviceName
                // Use full service identity to avoid collisions when multiple Macs share a name
                id = "\(serviceName).\(serviceType).\(domain ?? "local")"
            default:
                name = "Unknown Mac"
                id = "\(result.endpoint)"
            }

            return DiscoveredMac(id: id, name: name, endpoint: result.endpoint)
        }

        Self.logger.info("Discovered \(self.discoveredMacs.count) Mac(s)")
    }
}
