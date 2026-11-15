package net.yuandev.onexray.pigeon

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class OnDemandRule(
    val mode: String?,
    val interfaceType: String?,
    val ssid: List<String>?,
)

@Serializable
enum class PerAppVPNMode {
    @SerialName("allow")
    ALLOW,

    @SerialName("disallow")
    DISALLOW
}

@Serializable
data class TunJson(
    val tunIPv4: String? = null,
    val tunIPv6: String? = null,
    val tunDnsIPv4: String?,
    val tunDnsIPv6: String?,
    val enableDot: Boolean?,
    val dnsServerName: String?,
    val enableIPv6: Boolean?,
    val autoOutboundsInterface: String?,
    val includeAllNetworks: Boolean?,
    val excludeLocalNetworks: Boolean?,
    val excludeCellularServices: Boolean?,
    val excludeAPNs: Boolean?,
    val excludeDeviceCommunication: Boolean?,
    val excludedRoutes: List<String>? = null,
    val hideVpnIcon: Boolean? = null,
    val onDemandEnabled: Boolean?,
    val onDemandRules: List<OnDemandRule>?,
    val perAppVPNMode: PerAppVPNMode?,
    val allowAppList: List<String>?,
    val disallowAppList: List<String>?,
)

@Serializable
data class StartVpnRequest(
    val tun: TunJson?,
    val socksPort: String? = null,
    val metricsPort: String?,
    val coreInvokeText: String?,
    val snapshotToken: String? = null,
    val metadataJson: String? = null,
    val captureMode: String? = null,
    val autoSetSystemProxy: Boolean? = null,
)

@Serializable
enum class LibXrayMethod {
    @SerialName("getFreePorts")
    GET_FREE_PORTS,

    @SerialName("convertShareLinksToXrayJson")
    CONVERT_SHARE_LINKS_TO_XRAY_JSON,

    @SerialName("convertXrayJsonToShareLinks")
    CONVERT_XRAY_JSON_TO_SHARE_LINKS,

    @SerialName("countGeoData")
    COUNT_GEO_DATA,

    @SerialName("pingBatch")
    PING_BATCH,

    @SerialName("testXray")
    TEST_XRAY,

    @SerialName("runXray")
    RUN_XRAY,

    @SerialName("stopXray")
    STOP_XRAY,

    @SerialName("xrayVersion")
    XRAY_VERSION,

    @SerialName("getXrayState")
    GET_XRAY_STATE,
}

@Serializable
data class RunXrayRequest(
    val xrayJson: String? = null,
)

@Serializable
data class XrayEnv(
    @SerialName("xray.location.asset")
    val assetLocation: String? = null,
    @SerialName("xray.location.cert")
    val certLocation: String? = null,
    @SerialName("xray.tun.fd")
    val tunFd: String? = null,
)

@Serializable
data class LibXrayInvokeRequest(
    val apiVersion: Int? = 3,
    val method: LibXrayMethod? = null,
    val payload: RunXrayRequest? = null,
)

@Serializable
data class LibXrayInvokeResponse(
    val success: Boolean,
    val error: String,
)
