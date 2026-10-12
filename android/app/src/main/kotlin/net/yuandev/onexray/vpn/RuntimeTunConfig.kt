package net.yuandev.onexray.vpn

import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.put
import net.yuandev.onexray.pigeon.JsonTool

/** Injects only the native descriptor; Raw/provider env entries remain Core-owned. */
internal object RuntimeTunConfig {
    fun withTunFd(xrayJson: String, fd: Int): String {
        val root = JsonTool.json.parseToJsonElement(xrayJson).jsonObject
        val currentEnv = root["env"]
        require(currentEnv == null || currentEnv == JsonNull || currentEnv is JsonObject) {
            "Xray env must be an object"
        }
        val env = buildJsonObject {
            (currentEnv as? JsonObject)?.forEach { (key, value) -> put(key, value) }
            put("xray.tun.fd", fd.toString())
        }
        val updated = buildJsonObject {
            root.forEach { (key, value) -> put(key, value) }
            put("env", env)
        }
        return JsonTool.json.encodeToString(updated)
    }
}
