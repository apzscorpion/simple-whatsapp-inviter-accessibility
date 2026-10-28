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

/// {name} = the person's name as saved.
String fillMessage(String template, String name) => template.replaceAll('{name}', name.trim());
