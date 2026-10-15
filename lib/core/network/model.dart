final class DownloadRequestHeaders {
  const DownloadRequestHeaders({this.agePublicKey, this.hwid, this.userAgent});

  final String? agePublicKey;
  final String? hwid;
  final String? userAgent;

  static bool isValidUserAgent(String? value) =>
      value == null ||
      value.codeUnits.every((code) => code >= 0x20 && code <= 0x7e);

  Map<String, String>? toHttpHeaders() {
    final publicKey = agePublicKey?.trim();
    final agent = userAgent?.trim();
    final headers = <String, String>{
      if (agent != null && agent.isNotEmpty) 'User-Agent': agent,
      if (publicKey != null && publicKey.isNotEmpty)
        'X-Age-Public-Key': publicKey,
      'x-hwid': ?hwid,
    };
    return headers.isEmpty ? null : headers;
  }
}
