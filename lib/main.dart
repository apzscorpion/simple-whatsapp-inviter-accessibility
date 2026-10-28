import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'phone.dart';

void main() => runApp(const InviterApp());

const _channel = MethodChannel('inviter');
const _green = Color(0xFF1B7F3B);
// Edit preset.json on github.com and every phone picks it up the next time the app opens.
const _defaultPresetUrl = 'https://raw.githubusercontent.com/apzscorpion/simple-whatsapp-inviter-accessibility/main/preset.json';

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

class _HomePageState extends State<HomePage> {
  late SharedPreferences _prefs;
  List<Person> _people = [];
  Set<String> _sent = {};
  String _query = '';
  bool _whatsAppOnly = true;
  bool _hasWhatsAppAccount = false;
  String? _status = 'Loading…';

  String get _cc => _prefs.getString('cc') ?? '91';
  String get _message => (jsonDecode(_prefs.getString('preset') ?? '{}') as Map)['message'] as String? ?? '';

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    _prefs = await SharedPreferences.getInstance();
    _sent = (_prefs.getStringList('sent') ?? []).toSet();
    _refreshPreset(); // background; the cached copy works offline
    await _loadContacts();
  }

  Future<File> _imageFile() async => File('${(await getApplicationCacheDirectory()).path}/invite_image');

  /// Fetches {"message": "...", "image": "https://..."} from the preset link set in Settings.
  Future<String> _refreshPreset() async {
    final saved = _prefs.getString('presetUrl') ?? '';
    final url = saved.isEmpty ? _defaultPresetUrl : saved;
    try {
      final r = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 20));
      if (r.statusCode != 200) return 'Preset link gave ${r.statusCode}';
      final preset = jsonDecode(r.body) as Map;
      if (preset['message'] is! String) return 'Preset has no "message"';
      final img = await _imageFile();
      final imageUrl = preset['image'] as String? ?? '';
      if (imageUrl.isEmpty) {
        if (await img.exists()) await img.delete();
      } else if (imageUrl != _prefs.getString('imageUrl') || !await img.exists()) {
        final ir = await http.get(Uri.parse(imageUrl)).timeout(const Duration(seconds: 60));
        if (ir.statusCode != 200) return 'Image link gave ${ir.statusCode}';
        await img.writeAsBytes(ir.bodyBytes);
      }
      await _prefs.setString('imageUrl', imageUrl);
      await _prefs.setString('preset', r.body);
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
    if (message.isEmpty) {
      _say('The invitation is not set up yet.');
      return;
    }
    final text = fillMessage(message, name);
    final img = await _imageFile();
    final opened = await _channel.invokeMethod<bool>('send', {
      'phone': phone,
      'text': text,
      'image': await img.exists() ? img.path : null,
    });
    if (opened != true) {
      // shortcut: no WhatsApp app found, so the wa.me link sends text only (no image).
      await launchUrl(Uri.parse('https://wa.me/$phone?text=${Uri.encodeComponent(text)}'),
          mode: LaunchMode.externalApplication);
    }
    _sent.add(phone);
    await _prefs.setStringList('sent', _sent.toList());
    setState(() {});
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
    await Navigator.push(context, MaterialPageRoute(builder: (_) => SettingsPage(prefs: _prefs, refresh: _refreshPreset)));
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
  const SettingsPage({super.key, required this.prefs, required this.refresh});
  final SharedPreferences prefs;
  final Future<String> Function() refresh;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final _url = TextEditingController(text: widget.prefs.getString('presetUrl'));
  late final _cc = TextEditingController(text: widget.prefs.getString('cc') ?? '91');
  late final _pin = TextEditingController(text: widget.prefs.getString('pin'));
  String _result = '';

  Future<void> _save() async {
    await widget.prefs.setString('presetUrl', _url.text.trim());
    await widget.prefs.setString('cc', _cc.text.replaceAll(RegExp(r'\D'), ''));
    await widget.prefs.setString('pin', _pin.text.trim());
    setState(() => _result = 'Saved. Updating…');
    final r = await widget.refresh();
    setState(() => _result = r);
  }

  @override
  Widget build(BuildContext context) {
    final message = (jsonDecode(widget.prefs.getString('preset') ?? '{}') as Map)['message'] ?? '(none yet)';
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(controller: _url, decoration: const InputDecoration(labelText: 'Preset link (blank = preset.json in GitHub)')),
        TextField(controller: _cc, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Country code for 10-digit numbers')),
        TextField(controller: _pin, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Settings PIN (blank = none)')),
        const SizedBox(height: 16),
        FilledButton(onPressed: _save, child: const Text('Save and update now')),
        const SizedBox(height: 8),
        Text(_result),
        const Divider(height: 32),
        const Text('Current message:', style: TextStyle(fontWeight: FontWeight.bold)),
        Text('$message', style: const TextStyle(fontSize: 16)),
        const SizedBox(height: 16),
        OutlinedButton(
          onPressed: () async {
            await widget.prefs.remove('sent');
            setState(() => _result = 'Sent ticks cleared');
          },
          child: const Text('Clear all "Sent" ticks'),
        ),
      ]),
    );
  }
}
