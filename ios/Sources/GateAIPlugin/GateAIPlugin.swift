import Foundation
import Capacitor

@objc(GateAIPlugin)
public final class GateAIPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "GateAIPlugin"
    public let jsName = "GateAI"
    public let pluginMethods: [CAPPluginMethod] = [CAPPluginMethod(name: "execute", returnType: CAPPluginReturnPromise)]
    @MainActor private lazy var implementation = GateMobileBridge()
    @objc func execute(_ call: CAPPluginCall) {
        guard let payload = call.getString("payload") else { call.reject("Missing payload."); return }
        Task { @MainActor in
            call.resolve(["payload": await implementation.execute(payload)])
        }
    }
}
