enum ServerDomainStrategy { system, useIp, ipv4, ipv6, ipv4First, ipv6First }

/// Device preference for App-managed server connections, not routing DNS.
final class ServerDialingSettings {
  final ServerDomainStrategy domainStrategy;
  final bool happyEyeballs;

  const ServerDialingSettings({
    this.domainStrategy = ServerDomainStrategy.system,
    this.happyEyeballs = false,
  });

  factory ServerDialingSettings.fromJson(Map<String, dynamic> json) =>
      ServerDialingSettings(
        domainStrategy:
            ServerDomainStrategy.values
                .where((value) => value.name == json['domainStrategy'])
                .firstOrNull ??
            ServerDomainStrategy.system,
        happyEyeballs: json['happyEyeballs'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
    'domainStrategy': domainStrategy.name,
    'happyEyeballs': happyEyeballs,
  };

  EffectiveServerDialing effective({required bool ipv6}) {
    if (domainStrategy == ServerDomainStrategy.system) {
      return ipv6 && happyEyeballs
          ? const EffectiveServerDialing(
              domainStrategy: 'UseIP',
              happyEyeballs: true,
            )
          : const EffectiveServerDialing(domainStrategy: 'AsIs');
    }
    if (!ipv6) {
      return const EffectiveServerDialing(domainStrategy: 'UseIPv4');
    }
    return EffectiveServerDialing(
      domainStrategy: switch (domainStrategy) {
        ServerDomainStrategy.system => 'AsIs',
        ServerDomainStrategy.useIp => 'UseIP',
        ServerDomainStrategy.ipv4 => 'UseIPv4',
        ServerDomainStrategy.ipv6 => 'UseIPv6',
        ServerDomainStrategy.ipv4First => 'UseIPv4v6',
        ServerDomainStrategy.ipv6First => 'UseIPv6v4',
      },
      happyEyeballs:
          domainStrategy == ServerDomainStrategy.useIp && happyEyeballs,
    );
  }
}

/// The effective value shared by compilation and reconnect comparisons.
final class EffectiveServerDialing {
  final String domainStrategy;
  final bool happyEyeballs;

  const EffectiveServerDialing({
    required this.domainStrategy,
    this.happyEyeballs = false,
  });

  bool get enabled => domainStrategy != 'AsIs';

  Map<String, dynamic> toJson() => {
    'domainStrategy': domainStrategy,
    'happyEyeballs': happyEyeballs,
  };

  @override
  bool operator ==(Object other) =>
      other is EffectiveServerDialing &&
      domainStrategy == other.domainStrategy &&
      happyEyeballs == other.happyEyeballs;

  @override
  int get hashCode => Object.hash(domainStrategy, happyEyeballs);
}
