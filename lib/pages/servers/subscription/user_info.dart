import 'package:intl/intl.dart' show DateFormat;
import 'package:material_ui/material_ui.dart';
import 'package:onexray/core/tools/traffic_format.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/theme/color.dart';
import 'package:onexray/pages/theme/font.dart';
import 'package:onexray/service/servers/subscription/user_info.dart';

class SubscriptionPackageSummary extends StatelessWidget {
  const SubscriptionPackageSummary({super.key, required this.info});

  final SubscriptionUserInfo info;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final palette = ColorManager.palette(context);
    final now = DateTime.now();
    final remaining = info.remainingBytes;
    final used = info.usedBytes;
    final quota = info.unlimited
        ? l.subscriptionPackageUnlimited
        : info.exhausted
        ? l.subscriptionPackageExhausted
        : remaining != null
        ? l.subscriptionPackageRemainingSummary(_bytes(remaining))
        : used != null
        ? l.subscriptionPackageUsedSummary(_bytes(used))
        : info.totalBytes != null
        ? l.subscriptionPackageTotalSummary(_bytes(info.totalBytes!))
        : info.uploadBytes != null
        ? '${l.prototypeUpload} ${_bytes(info.uploadBytes!)}'
        : info.downloadBytes != null
        ? '${l.prototypeDownload} ${_bytes(info.downloadBytes!)}'
        : null;
    final expiry = info.expiresAt;
    final expiryLabel = info.expireTimestamp == 0
        ? l.subscriptionPackageNoExpiry
        : expiry == null
        ? null
        : info.isExpired(now)
        ? l.subscriptionPackageExpired
        : l.subscriptionPackageExpiresInDays(
            (expiry.difference(now).inMilliseconds /
                    Duration.millisecondsPerDay)
                .ceil(),
          );
    return Text(
      [?quota, ?expiryLabel].join(' · '),
      style: AppTypography.serverGroupSummary.copyWith(
        color: info.exhausted || info.isExpired(now)
            ? palette.restartingText
            : palette.mutedForeground,
      ),
    );
  }
}

class SubscriptionPackageDetails extends StatelessWidget {
  const SubscriptionPackageDetails({super.key, required this.info});

  final SubscriptionUserInfo info;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final palette = ColorManager.palette(context);
    String bytes(int? value) =>
        value == null ? l.subscriptionPackageNotProvided : formatTraffic(value);
    String date(DateTime value) =>
        DateFormat.yMd(l.localeName).add_Hm().format(value.toLocal());
    final expiry = info.expiresAt;
    final values = <(String, String)>[
      (l.prototypeUpload, bytes(info.uploadBytes)),
      (l.prototypeDownload, bytes(info.downloadBytes)),
      (l.subscriptionPackageUsed, bytes(info.usedBytes)),
      (
        l.subscriptionPackageTotal,
        info.unlimited
            ? l.subscriptionPackageUnlimited
            : bytes(info.totalBytes),
      ),
      (
        l.subscriptionPackageRemaining,
        info.unlimited
            ? l.subscriptionPackageUnlimited
            : bytes(info.remainingBytes),
      ),
      (
        l.subscriptionPackageExpiry,
        info.expireTimestamp == 0
            ? l.subscriptionPackageNoExpiry
            : expiry == null
            ? l.subscriptionPackageNotProvided
            : date(expiry),
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l.subscriptionPackageTitle,
          style: AppTypography.sectionTitle.copyWith(color: palette.foreground),
        ),
        const SizedBox(height: 4),
        SubscriptionPackageSummary(info: info),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            final fontSize = AppTypography.rowValue.fontSize!;
            final textScale =
                MediaQuery.textScalerOf(context).scale(fontSize) / fontSize;
            final twoColumns = constraints.maxWidth >= 280 * textScale;
            return Wrap(
              spacing: 18,
              runSpacing: 12,
              children: [
                for (final (label, value) in values)
                  SizedBox(
                    width: twoColumns
                        ? (constraints.maxWidth - 18) / 2
                        : constraints.maxWidth,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          style: AppTypography.serverGroupSummary.copyWith(
                            color: palette.mutedForeground,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          value,
                          style: AppTypography.rowValue.copyWith(
                            color: palette.foreground,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 14),
        Text(
          l.subscriptionPackageUpdatedAt(date(info.updatedAt)),
          style: AppTypography.serverGroupSummary.copyWith(
            color: palette.mutedForeground,
          ),
        ),
      ],
    );
  }
}

String _bytes(int value) => '\u2066${formatTraffic(value)}\u2069';
