import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'phone.dart';

void main() => runApp(const InviterApp());

const _channel = MethodChannel('inviter');
const _green = Color(0xFF1B7F3B);
const _repo = 'apzscorpion/simple-whatsapp-inviter-accessibility';
// The API, not raw.githubusercontent.com, so an edit reaches phones at once instead of after a 5-minute CDN cache.
const _defaultPresetUrl = 'https://api.github.com/repos/$_repo/contents/preset.json';

/// The invitation picture, kept in app files (not cache) so Android never clears a picture chosen on the phone.
Future<File> imageFile() async => File('${(await getApplicationSupportDirectory()).path}/invite_image');

/// Creates or replaces [path] in the repo; returns the commit sha.
Future<String> githubPut(String token, String path, List<int> bytes) async {
  final uri = Uri.parse('https://api.github.com/repos/$_repo/contents/$path');
  final headers = {'Authorization': 'Bearer $token', 'Accept': 'application/vnd.github+json'};
  final old = await http.get(uri, headers: headers);
  final sha = old.statusCode == 200 ? (jsonDecode(old.body) as Map)['sha'] : null;
  final r = await http.put(uri, headers: headers, body: jsonEncode({
    'message': 'Update $path from the app',
    'content': base64Encode(bytes),
    'sha': ?sha,
  }));
  if (r.statusCode >= 300) throw 'GitHub said ${r.statusCode}. Check the key.';
  return ((jsonDecode(r.body) as Map)['commit'] as Map)['sha'] as String;
}

class InviterApp extends StatelessWidget {
  const InviterApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'WhatsApp Inviter',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorSchemeSeed: _green,
          textTheme: const TextTheme(
            bodyLarge: TextStyle(fontSize: 22),
            bodyMedium: TextStyle(fontSize: 20),
            titleMedium: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
          ),
        ),
        home: const HomePage(),
      );
}

class Person {
  Person(this.name, this.phone, this.photo, this.onWhatsApp);
  final String name;
  final String phone; // normalized, digits only
  final Uint8List? photo;
  final bool onWhatsApp;
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  late SharedPreferences _prefs;
  List<Person> _people = [];
  Set<String> _sent = {};
  String _query = '';
  bool _whatsAppOnly = true;
  bool _hasWhatsAppAccount = false;
  String? _status = 'Loading…';
  bool _autoSend = true; // hides the setup banner until checked

  String get _cc => _prefs.getString('cc') ?? '91';
  String get _message => (jsonDecode(_prefs.getString('preset') ?? '{}') as Map)['message'] as String? ?? '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkAutoSend(); // back from Accessibility settings
  }

  Future<void> _checkAutoSend() async {
    final on = await _channel.invokeMethod<bool>('autoSendOn') ?? false;
    if (mounted && on != _autoSend) setState(() => _autoSend = on);
  }

  Future<void> _start() async {
    _prefs = await SharedPreferences.getInstance();
    _sent = (_prefs.getStringList('sent') ?? []).toSet();
    _checkAutoSend();
    _refreshPreset(); // background; the cached copy works offline
    await _loadContacts();
  }

  /// Fetches {"message": "...", "image": "https://..."} from the preset link (preset.json in the repo by default).
  Future<String> _refreshPreset() async {
    final saved = _prefs.getString('presetUrl') ?? '';
    final url = saved.isEmpty ? _defaultPresetUrl : saved;
    try {
      final r = await http.get(Uri.parse(url), headers: {'Accept': 'application/vnd.github.raw'}).timeout(const Duration(seconds: 20));
      if (r.statusCode != 200) return 'Preset link gave ${r.statusCode}';
      // Unchanged since last time: keep any edit made on this phone.
      if (r.body == _prefs.getString('lastRemote')) return 'Up to date';
      final preset = jsonDecode(r.body) as Map;
      if (preset['message'] is! String) return 'Preset has no "message"';
      final img = await imageFile();
      final imageUrl = preset['image'] as String? ?? '';
      if (imageUrl.isEmpty) {
        if (await img.exists()) await img.delete();
      } else {
        final ir = await http.get(Uri.parse(imageUrl)).timeout(const Duration(seconds: 60));
        if (ir.statusCode != 200) return 'Image link gave ${ir.statusCode}';
        await img.writeAsBytes(ir.bodyBytes);
      }
      await _prefs.setString('preset', r.body);
      await _prefs.setString('lastRemote', r.body);
      if (mounted) setState(() {});
      return 'Updated';
    } catch (e) {
      return 'Could not update: $e';
    }
  }

  Future<void> _loadContacts() async {
    if (await FlutterContacts.permissions.request(PermissionType.read) != PermissionStatus.granted) {
      setState(() => _status = 'Allow Contacts to see your people.\nYou can still type a number below.');
      return;
    }
    // WhatsApp adds a "com.whatsapp" contacts account holding the people who use it.
    final waAccounts = (await FlutterContacts.accounts.getAll()).where((a) => a.type == 'com.whatsapp');
    final waNumbers = <String>{};
    for (final a in waAccounts) {
      for (final c in await FlutterContacts.getAll(account: a, properties: {ContactProperty.phone})) {
        waNumbers.addAll(c.phones.map((p) => normalizePhone(p.normalizedNumber ?? p.number, _cc)).whereType<String>());
      }
    }
    final contacts = await FlutterContacts.getAll(properties: {ContactProperty.phone, ContactProperty.photoThumbnail});
    final people = <Person>[];
    for (final c in contacts) {
      final numbers = c.phones.map((p) => normalizePhone(p.normalizedNumber ?? p.number, _cc)).whereType<String>().toSet();
      for (final n in numbers) {
        people.add(Person(c.displayName ?? n, n, c.photo?.thumbnail, waNumbers.contains(n)));
      }
    }
    people.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    setState(() {
      _people = people;
      _hasWhatsAppAccount = waNumbers.isNotEmpty;
      _whatsAppOnly = waNumbers.isNotEmpty;
      _status = null;
    });
  }

  Future<void> _invite(String name, String phone) async {
    final message = _message;
    if (message.isEmpty) return _openSettings();
    final text = fillMessage(message, name);
    final img = await imageFile();
    final outcome = await _channel.invokeMethod<String>('send', {
      'phone': phone,
      'text': text,
      'image': await img.exists() ? img.path : null,
    });
    if (outcome == 'missing') {
      // shortcut: no WhatsApp app found, so the wa.me link sends text only (no image).
      await launchUrl(Uri.parse('https://wa.me/$phone?text=${Uri.encodeComponent(text)}'),
          mode: LaunchMode.externalApplication);
    }
    _sent.add(phone);
    await _prefs.setStringList('sent', _sent.toList());
    if (!mounted) return;
    setState(() {});
    if (outcome == 'sent') _say('Sent to ${name.isEmpty ? '+$phone' : name} ✓');
    if (outcome == 'opened' && _autoSend) _say('Please tap Send in WhatsApp.');
  }

  void _say(String s) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s, style: const TextStyle(fontSize: 20))));

  Future<void> _typeNumber() async {
    final number = TextEditingController(), name = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Type a number'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: number, keyboardType: TextInputType.phone, autofocus: true, style: const TextStyle(fontSize: 26),
              decoration: const InputDecoration(labelText: 'Phone number')),
          TextField(controller: name, style: const TextStyle(fontSize: 22), decoration: const InputDecoration(labelText: 'Name (optional)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel', style: TextStyle(fontSize: 20))),
          _InviteButton(onPressed: () => Navigator.pop(c, true)),
        ],
      ),
    );
    if (ok != true) return;
    final phone = normalizePhone(number.text, _cc);
    if (phone == null) {
      _say('That number looks wrong. Please check it.');
      return;
    }
    await _invite(name.text.trim(), phone);
  }

  Future<void> _openSettings() async {
    final pin = _prefs.getString('pin') ?? '';
    if (pin.isNotEmpty) {
      final entered = TextEditingController();
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('PIN'),
          content: TextField(controller: entered, obscureText: true, keyboardType: TextInputType.number, autofocus: true,
              onSubmitted: (_) => Navigator.pop(c, true)),
          actions: [TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('OK'))],
        ),
      );
      if (ok != true || entered.text != pin) return;
    }
    if (!mounted) return;
    await Navigator.push(context, MaterialPageRoute(builder: (_) => SettingsPage(prefs: _prefs)));
    _sent = (_prefs.getStringList('sent') ?? []).toSet();
    await _loadContacts(); // country code may have changed
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.toLowerCase();
    final shown = _people
        .where((p) => !_whatsAppOnly || p.onWhatsApp)
        .where((p) => q.isEmpty || p.name.toLowerCase().contains(q) || p.phone.contains(q))
        .toList();
    return Scaffold(
      appBar: AppBar(
        // Settings hide behind a long press so a stray tap can't change the invitation.
        title: GestureDetector(onLongPress: _openSettings, child: const Text('Send Invitation', style: TextStyle(fontSize: 24))),
      ),
      body: Column(children: [
        if (!_autoSend)
          Card(
            color: Colors.amber.shade100,
            margin: const EdgeInsets.all(12),
            child: ListTile(
              title: const Text('Send without tapping Send', style: TextStyle(fontSize: 18)),
              subtitle: const Text('One time: tap Turn on, choose "WhatsApp Inviter auto-send", switch it on.', style: TextStyle(fontSize: 15)),
              trailing: FilledButton(onPressed: () => _channel.invokeMethod('openAutoSendSettings'), child: const Text('Turn on')),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
          child: TextField(
            style: const TextStyle(fontSize: 22),
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search, size: 30), hintText: 'Search name', border: OutlineInputBorder()),
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        if (_hasWhatsAppAccount)
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: true, label: Text('On WhatsApp', style: TextStyle(fontSize: 18))),
              ButtonSegment(value: false, label: Text('All contacts', style: TextStyle(fontSize: 18))),
            ],
            selected: {_whatsAppOnly},
            onSelectionChanged: (s) => setState(() => _whatsAppOnly = s.first),
          ),
        Expanded(
          child: _status != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_status!, textAlign: TextAlign.center)))
              : ListView.separated(
                  padding: const EdgeInsets.only(bottom: 110),
                  itemCount: shown.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final p = shown[i];
                    final sent = _sent.contains(p.phone);
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      leading: CircleAvatar(
                        radius: 28,
                        backgroundImage: p.photo != null ? MemoryImage(p.photo!) : null,
                        child: p.photo == null ? Text(p.name.isEmpty ? '?' : p.name[0].toUpperCase(), style: const TextStyle(fontSize: 24)) : null,
                      ),
                      title: Text(p.name, maxLines: 2, overflow: TextOverflow.ellipsis),
                      subtitle: Text(sent ? '✓ Sent  +${p.phone}' : '+${p.phone}', style: TextStyle(fontSize: 16, color: sent ? _green : null)),
                      trailing: _InviteButton(sent: sent, onPressed: () => _invite(p.name, p.phone)),
                    );
                  },
                ),
        ),
      ]),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _typeNumber,
        icon: const Icon(Icons.dialpad, size: 30),
        label: const Text('Type a number', style: TextStyle(fontSize: 22)),
      ),
    );
  }
}

class _InviteButton extends StatelessWidget {
  const _InviteButton({required this.onPressed, this.sent = false});
  final VoidCallback onPressed;
  final bool sent;

  @override
  Widget build(BuildContext context) => FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: sent ? Colors.grey.shade600 : _green,
          minimumSize: const Size(110, 56),
          textStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        onPressed: onPressed,
        child: Text(sent ? 'Again' : 'Invite'),
      );
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.prefs});
  final SharedPreferences prefs;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final Map _preset = jsonDecode(widget.prefs.getString('preset') ?? '{}') as Map;
  late final _message = TextEditingController(text: _preset['message'] as String? ?? '');
  late final _token = TextEditingController(text: widget.prefs.getString('githubToken'));
  late final _url = TextEditingController(text: widget.prefs.getString('presetUrl'));
  late final _cc = TextEditingController(text: widget.prefs.getString('cc') ?? '91');
  late final _pin = TextEditingController(text: widget.prefs.getString('pin'));
  Uint8List? _image; // what the picture box shows
  bool _imageChanged = false;
  bool _busy = false;
  String _result = '';

  @override
  void initState() {
    super.initState();
    imageFile().then((f) async {
      if (!await f.exists()) return;
      final bytes = await f.readAsBytes();
      if (mounted) setState(() => _image = bytes);
    });
  }

  Future<void> _pick() async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1600, imageQuality: 85);
    if (x == null) return;
    final bytes = await x.readAsBytes();
    setState(() {
      _image = bytes;
      _imageChanged = true;
    });
  }

  Future<void> _save() async {
    final prefs = widget.prefs;
    final token = _token.text.trim();
    setState(() {
      _busy = true;
      _result = 'Saving…';
    });
    await prefs.setString('githubToken', token);
    await prefs.setString('presetUrl', _url.text.trim());
    await prefs.setString('cc', _cc.text.replaceAll(RegExp(r'\D'), ''));
    await prefs.setString('pin', _pin.text.trim());
    final img = await imageFile();
    var imageUrl = _preset['image'] as String? ?? '';
    if (_imageChanged) {
      if (_image != null) {
        await img.writeAsBytes(_image!);
      } else if (await img.exists()) {
        await img.delete();
      }
      imageUrl = '';
    }
    var result = 'Saved on this phone.';
    if (token.isNotEmpty) {
      try {
        if (_imageChanged && _image != null) {
          // Pinned to the commit, so phones never get an old cached copy.
          imageUrl = 'https://raw.githubusercontent.com/$_repo/${await githubPut(token, 'card.jpg', _image!)}/card.jpg';
        }
        final body = const JsonEncoder.withIndent('  ').convert({'message': _message.text, 'image': imageUrl});
        await githubPut(token, 'preset.json', utf8.encode(body));
        await prefs.setString('lastRemote', body);
        result = 'Saved. All phones get it next time they open the app.';
      } catch (e) {
        result = 'Saved on this phone only. Sending to other phones failed: $e';
      }
    }
    _preset['image'] = imageUrl;
    await prefs.setString('preset', jsonEncode({'message': _message.text, 'image': imageUrl}));
    setState(() {
      _busy = false;
      _imageChanged = false;
      _result = result;
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Invitation')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          TextField(
            controller: _message,
            minLines: 4,
            maxLines: 12,
            style: const TextStyle(fontSize: 18),
            decoration: const InputDecoration(
              labelText: 'Message',
              helperText: '{name} becomes the person\'s name. Paste your link in the message.',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          if (_image != null) ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.memory(_image!, height: 220, fit: BoxFit.contain)),
          Row(children: [
            Expanded(child: OutlinedButton.icon(onPressed: _pick, icon: const Icon(Icons.photo), label: const Text('Choose picture'))),
            if (_image != null) ...[
              const SizedBox(width: 8),
              OutlinedButton(onPressed: () => setState(() {
                _image = null;
                _imageChanged = true;
              }), child: const Text('Remove')),
            ],
          ]),
          const SizedBox(height: 16),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _green, minimumSize: const Size.fromHeight(56)),
            onPressed: _busy ? null : _save,
            child: const Text('Save', style: TextStyle(fontSize: 20)),
          ),
          const SizedBox(height: 8),
          Text(_result, style: const TextStyle(fontSize: 16)),
          const SizedBox(height: 8),
          ExpansionTile(
            title: const Text('Advanced', style: TextStyle(fontSize: 18)),
            childrenPadding: const EdgeInsets.symmetric(horizontal: 8),
            children: [
              TextField(
                controller: _token,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'GitHub key (only on your phone)',
                  helperText: 'With a key, Save sends the invitation to every phone.',
                ),
              ),
              TextField(controller: _pin, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'PIN to open this screen (blank = none)')),
              TextField(controller: _cc, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Country code for 10-digit numbers')),
              TextField(controller: _url, decoration: const InputDecoration(labelText: 'Preset link (blank = this app\'s GitHub)')),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () async {
                  await widget.prefs.remove('sent');
                  setState(() => _result = '"Sent" marks cleared.');
                },
                child: const Text('Clear all "Sent" marks'),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ]),
      );
}
