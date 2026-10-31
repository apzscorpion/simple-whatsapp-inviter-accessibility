/// Turns any typed or saved number into WhatsApp's form: country code + number, digits only.
/// Returns null when it can't be a phone number.
String? normalizePhone(String raw, String countryCode) {
  var d = raw.replaceAll(RegExp(r'\D'), '');
  if (raw.trim().startsWith('+')) return d.length >= 8 ? d : null;
  if (d.startsWith('00')) return d.length >= 10 ? d.substring(2) : null;
  if (d.startsWith('0')) d = d.substring(1); // local trunk prefix, e.g. 09876543210
  if (d.length == 10) return '$countryCode$d';
  return d.length > 10 && d.length <= 15 ? d : null;
}

/// A piece of [text] that auto-send must find on WhatsApp's screen before pressing Send: the first stretch of
/// 6+ characters with no formatting marks, since WhatsApp may style or hide those marks. Empty = nothing to check.
String sendCheck(String text) {
  final parts = text.split(RegExp(r'[*_~\n]')).map((s) => s.trim()).where((s) => s.length >= 6);
  final p = parts.isEmpty ? text.trim() : parts.first;
  return p.length > 20 ? p.substring(0, 20) : p;
}

/// {name} = the person's name as saved. WhatsApp's own marks (*bold*, _italic_, ~strike~) pass through;
/// Markdown pasted from elsewhere (**bold**, __italic__, [text](link)) is turned into them, since WhatsApp
/// would show its marks as plain characters.
String fillMessage(String template, String name) => template
    .replaceAll('{name}', name.trim())
    .replaceAllMapped(RegExp(r'\[([^\]]+)\]\(([^)\s]+)\)'), (m) => m[1] == m[2] ? m[2]! : '${m[1]} ${m[2]}')
    .replaceAllMapped(RegExp(r'\*\*(.+?)\*\*'), (m) => '*${m[1]!.trim()}*')
    .replaceAllMapped(RegExp(r'__(.+?)__'), (m) => '_${m[1]!.trim()}_');
