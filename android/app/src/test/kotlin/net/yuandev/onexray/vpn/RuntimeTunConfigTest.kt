package net.yuandev.onexray.vpn

import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import net.yuandev.onexray.pigeon.JsonTool
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class RuntimeTunConfigTest {
    @Test fun preservesCompleteEnvAndProviderGraphWhileReplacingDescriptor() {
        val source = """{
          "env":{"xray.location.asset":"/assets","xray.location.cert":"/certs",
                 "xray.tun.fd":"4","provider.future-option":"保留","XRAY_CUSTOM":"enabled"},
          "outbounds":[{"tag":"entry","protocol":"socks","streamSettings":{"sockopt":{"dialerProxy":"exit"}}},
                       {"tag":"exit","protocol":"freedom"}],
          "routing":{"domainStrategy":"IPIfNonMatch","rules":[{"inboundTag":["tunIn"],"outboundTag":"entry"}]},
          "dns":{"hosts":{"example.com":"203.0.113.1"}},"futureOption":{"enabled":true}
        }"""
        val original = JsonTool.json.parseToJsonElement(source).jsonObject
        val updated = JsonTool.json.parseToJsonElement(RuntimeTunConfig.withTunFd(source, 37)).jsonObject
        assertEquals(original - "env", updated - "env")
        assertEquals(original.getValue("env").jsonObject - "xray.tun.fd",
            updated.getValue("env").jsonObject - "xray.tun.fd")
        val descriptor = updated.getValue("env").jsonObject.getValue("xray.tun.fd").jsonPrimitive
        assertEquals("37", descriptor.content)
        assertEquals(true, descriptor.isString)
        assertEquals("4", original.getValue("env").jsonObject.getValue("xray.tun.fd").jsonPrimitive.content)
    }

    @Test fun createsDescriptorForMissingOrNullEnvironment() {
        for (source in listOf("""{"outbounds":[{"protocol":"freedom"}]}""",
            """{"env":null,"outbounds":[{"protocol":"freedom"}]}""")) {
            val original = JsonTool.json.parseToJsonElement(source).jsonObject
            val updated = JsonTool.json.parseToJsonElement(RuntimeTunConfig.withTunFd(source, 9)).jsonObject
            assertEquals(original - "env", updated - "env")
            assertEquals(setOf("xray.tun.fd"), updated.getValue("env").jsonObject.keys)
            assertEquals("9", updated.getValue("env").jsonObject.getValue("xray.tun.fd").jsonPrimitive.content)
        }
    }

    @Test fun rejectsMalformedEnvironmentInsteadOfSilentlyReplacingIt() {
        for (source in listOf("""{"env":[]}""", """{"env":"invalid"}""")) {
            assertThrows(IllegalArgumentException::class.java) { RuntimeTunConfig.withTunFd(source, 8) }
        }
    }
}
