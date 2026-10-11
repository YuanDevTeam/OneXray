import 'package:onexray/core/model/xray_json.dart';
import 'package:onexray/service/connect/routing/options.dart';
import 'package:onexray/core/network/constants.dart';
import 'package:onexray/core/pigeon/constants.dart';

const lanProxyInboundTag = 'app-lan-proxy';
const defaultLanProxyPort = 11024;

XrayInbound createTunInbound({
  List<String>? gateway,
  List<String>? dns,
  List<String>? autoSystemRoutingTable,
  String? autoOutboundsInterface,
  List<String>? autoSystemWfpBlockLeak,
  bool fakeDns = false,
  RoutingSniffingSettings sniffing = const RoutingSniffingSettings(),
}) => XrayInbound(
  listen: NetConstants.proxyHost,
  protocol: 'tun',
  settings: XrayInboundTunSettings(
    name: 'OneXrayTun',
    mtu: VpnConstants.tunMtu,
    gateway: gateway,
    dns: dns,
    autoSystemRoutingTable: autoSystemRoutingTable,
    autoOutboundsInterface: autoOutboundsInterface,
    autoSystemWfpBlockLeak: autoSystemWfpBlockLeak,
  ).toJson(),
  tag: 'tunIn',
  sniffing: sniffing.toXraySniffing(fakeDns: fakeDns),
);

XrayInbound createSocksInbound(
  String port, {
  bool fakeDns = false,
  RoutingSniffingSettings sniffing = const RoutingSniffingSettings(),
}) => XrayInbound(
  listen: NetConstants.proxyHost,
  port: port,
  protocol: 'socks',
  settings: XrayInboundSocksSettings(auth: 'noauth', udp: true).toJson(),
  tag: 'tunIn',
  sniffing: sniffing.toXraySniffing(fakeDns: fakeDns),
);

XrayInbound createLanProxyInbound(
  int port, {
  bool fakeDns = false,
  RoutingSniffingSettings sniffing = const RoutingSniffingSettings(),
}) => XrayInbound(
  listen: '0.0.0.0',
  port: '$port',
  protocol: 'socks',
  settings: XrayInboundSocksSettings(auth: 'noauth', udp: true).toJson(),
  tag: lanProxyInboundTag,
  sniffing: sniffing.toXraySniffing(fakeDns: fakeDns),
);
