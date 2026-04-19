import Foundation

public struct HermesHookInstallerManifest: Equatable, Codable, Sendable {
    public static let fileName = "open-island-hermes-install.json"

    public var hookBinaryPath: String
    public var pluginVersion: String
    public var installedAt: Date

    public init(
        hookBinaryPath: String,
        pluginVersion: String = HermesHookInstaller.pluginVersion,
        installedAt: Date = .now
    ) {
        self.hookBinaryPath = hookBinaryPath
        self.pluginVersion = pluginVersion
        self.installedAt = installedAt
    }
}

public struct HermesPluginAssets: Equatable, Sendable {
    public var pluginYAML: Data
    public var pluginInit: Data

    public init(pluginYAML: Data, pluginInit: Data) {
        self.pluginYAML = pluginYAML
        self.pluginInit = pluginInit
    }
}

public enum HermesHookInstaller {
    public static let pluginVersion = "1.0.0"
    public static let pluginDirectoryName = "open-island"
    public static let managedMarker = "open_island_managed: true"

    public static func renderPluginAssets(hookBinaryPath: String) -> HermesPluginAssets {
        HermesPluginAssets(
            pluginYAML: Data(pluginYAML().utf8),
            pluginInit: Data(pluginInitPython(hookBinaryPath: hookBinaryPath).utf8)
        )
    }

    public static func isManagedPlugin(pluginYAMLData: Data?) -> Bool {
        guard let data = pluginYAMLData,
              let text = String(data: data, encoding: .utf8) else {
            return false
        }

        return text.contains(managedMarker)
    }

    public static func pluginYAML() -> String {
        """
        # Managed by Open Island. Do not edit by hand.
        # Removing the marker below will cause `OpenIslandSetup uninstallHermes` to
        # leave this plugin directory in place.
        open_island_managed: true
        name: open-island
        version: \(pluginVersion)
        description: >
          Forwards Hermes Agent hook events to the local Open Island bridge.
          Observer-only: never blocks tool calls.
        """
    }

    public static func pluginInitPython(hookBinaryPath: String) -> String {
        """
        # Managed by Open Island. Do not edit by hand.
        \"\"\"Open Island bridge plugin for Hermes Agent.

        Forwards Hermes hook events (``on_session_start``, ``pre_tool_call``,
        ``post_tool_call``, ``on_session_end``) to the local Open Island bridge
        via the OpenIslandHooks binary over stdin. Failures are swallowed so the
        Hermes CLI keeps running when the island app is not available.
        \"\"\"

        from __future__ import annotations

        import json
        import os
        import subprocess
        from typing import Any, Mapping

        HOOK_BINARY = \(pythonQuote(hookBinaryPath))


        def _send(payload: Mapping[str, Any]) -> None:
            try:
                data = json.dumps(payload, default=str).encode(\"utf-8\")
            except Exception:
                return

            try:
                process = subprocess.Popen(
                    [HOOK_BINARY, \"--source\", \"hermes\"],
                    stdin=subprocess.PIPE,
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                    close_fds=True,
                )
            except Exception:
                return

            try:
                process.stdin.write(data)
            except Exception:
                pass
            finally:
                try:
                    process.stdin.close()
                except Exception:
                    pass


        def _coerce(value: Any) -> Any:
            if isinstance(value, (str, int, float, bool)) or value is None:
                return value
            if isinstance(value, Mapping):
                return {str(k): _coerce(v) for k, v in value.items()}
            if isinstance(value, (list, tuple, set)):
                return [_coerce(v) for v in value]
            return str(value)


        def _base_payload(event_name: str, ctx: Any) -> dict[str, Any]:
            session_id = getattr(ctx, \"session_id\", None) or getattr(ctx, \"sessionID\", None)
            payload: dict[str, Any] = {
                \"hook_event_name\": event_name,
                \"session_id\": str(session_id) if session_id is not None else \"\",
                \"cwd\": os.getcwd(),
                \"pid\": os.getpid(),
                \"platform\": \"cli\",
            }

            model = getattr(ctx, \"model\", None)
            if model:
                payload[\"model\"] = str(model)

            return payload


        def _on_session_start(ctx: Any = None, **kwargs: Any) -> None:
            payload = _base_payload(\"session_start\", ctx)
            _send(payload)


        def _pre_tool_call(ctx: Any = None, tool_name: Any = None, tool_args: Any = None, tool_call_id: Any = None, **kwargs: Any) -> None:
            payload = _base_payload(\"pre_tool_call\", ctx)
            if tool_name is not None:
                payload[\"tool_name\"] = str(tool_name)
            if tool_args is not None:
                payload[\"tool_args\"] = _coerce(tool_args)
            if tool_call_id is not None:
                payload[\"tool_call_id\"] = str(tool_call_id)
            _send(payload)
            return None


        def _post_tool_call(ctx: Any = None, tool_name: Any = None, tool_args: Any = None, tool_call_id: Any = None, result: Any = None, **kwargs: Any) -> None:
            payload = _base_payload(\"post_tool_call\", ctx)
            if tool_name is not None:
                payload[\"tool_name\"] = str(tool_name)
            if tool_call_id is not None:
                payload[\"tool_call_id\"] = str(tool_call_id)
            _send(payload)


        def _on_session_end(ctx: Any = None, completed: Any = None, interrupted: Any = None, **kwargs: Any) -> None:
            payload = _base_payload(\"session_end\", ctx)
            if completed is not None:
                payload[\"completed\"] = bool(completed)
            if interrupted is not None:
                payload[\"interrupted\"] = bool(interrupted)
            _send(payload)


        def register(ctx: Any) -> None:
            \"\"\"Hermes plugin entry point.

            Hermes looks up a ``register`` callable on the plugin module and passes
            its own plugin context. The context exposes ``register_hook(name, fn)``.
            \"\"\"

            for event_name, callback in (
                (\"on_session_start\", _on_session_start),
                (\"pre_tool_call\", _pre_tool_call),
                (\"post_tool_call\", _post_tool_call),
                (\"on_session_end\", _on_session_end),
            ):
                register_hook = getattr(ctx, \"register_hook\", None)
                if register_hook is None:
                    return
                try:
                    register_hook(event_name, callback)
                except Exception:
                    # Never propagate: the Hermes CLI must keep running even if
                    # the bridge plugin fails to register a single callback.
                    continue
        """
    }

    private static func pythonQuote(_ string: String) -> String {
        let escaped = string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
