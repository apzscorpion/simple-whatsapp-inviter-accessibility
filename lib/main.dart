import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'phone.dart';

void main() => runApp(const InviterApp());

const _channel = MethodChannel('inviter');
const _green = Color(0xFF1B7F3B);

/// The invitation picture, copied out of the app so WhatsApp can be handed it.
Future<File> imageFile() async => File('${(await getApplicationSupportDirectory()).path}/invite_image');

/// The invitation is built into the app (assets/invitation/): message.txt, and card.jpg if there is one.
/// Nothing is typed or downloaded on the phone, so nothing can be lost there.
Future<String> loadInvitation() async {
  final img = await imageFile();
  try {
    final data = await rootBundle.load('assets/invitation/card.jpg');
    await img.writeAsBytes(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes), flush: true);
  } catch (_) {
    if (await img.exists()) await img.delete(); // no card in this version
  }
  return rootBundle.loadString('assets/invitation/message.txt');
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
  bool _sending = false;

  String get _cc => _prefs.getString('cc') ?? '91';
  String _message = '';

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
    _message = await loadInvitation();
    await _loadContacts();
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
    // One at a time: a second tap mid-send would replace the first and mark the wrong person as sent.
    if (_sending) return;
    _sending = true;
    try {
      await _inviteNow(name, phone);
    } finally {
      _sending = false;
    }
  }

  Future<void> _inviteNow(String name, String phone) async {
    final message = _message;
    final text = fillMessage(message, name);
    final img = await imageFile();
    final outcome = await _channel.invokeMethod<String>('send', {
      'phone': phone,
      'text': text,
      'image': await img.exists() ? img.path : null,
      'expect': sendCheck(text),
    });
    if (outcome == 'missing') {
      // shortcut: no WhatsApp app found, so the wa.me link sends text only (no image).
      await launchUrl(Uri.parse('https://wa.me/$phone?text=${Uri.encodeComponent(text)}'),
          mode: LaunchMode.externalApplication);
    }
    // "opened" = auto-send gave up (Send not found, or the screen wasn't our invitation), so nothing is known
    // to have gone out: don't mark it. "manual" = auto-send is off and they tap Send themselves, as before.
    if (outcome != null && outcome.startsWith('opened')) {
      final why = switch (outcome.split(':').last) {
        'service' => 'Auto-send is not running. Turn it off and on again in Accessibility.',
        'whatsapp' => 'WhatsApp did not open the chat in time.',
        'text' => 'The invitation was not seen in WhatsApp.',
        'button' => "WhatsApp's Send button was not found.",
        _ => 'Send was tapped but WhatsApp did not send.',
      };
      if (mounted) _say('Not sent automatically: $why\nTap Send in WhatsApp.');
      _checkAutoSend();
      return;
    }
    if (outcome == 'manual') _checkAutoSend(); // it may have been switched off: show the banner
    _sent.add(phone);
    await _prefs.setStringList('sent', _sent.toList());
    if (!mounted) return;
    setState(() {});
    if (outcome == 'sent') _say('Sent to ${name.isEmpty ? '+$phone' : name} ✓');
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
        title: const Text('Send Invitation', style: TextStyle(fontSize: 24)),
        actions: [IconButton(onPressed: _openSettings, icon: const Icon(Icons.settings), tooltip: 'Settings')],
      ),
      body: Column(children: [
        if (!_autoSend)
          Card(
            color: Colors.amber.shade100,
            margin: const EdgeInsets.all(12),
            child: ListTile(
              title: const Text('Automatic sending is OFF', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              subtitle: const Text(
                'Tap Turn on → "WhatsApp Inviter auto-send" → On.\nAndroid turns it off after an app update or when the app is cleared from recent apps.',
                style: TextStyle(fontSize: 15),
              ),
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
  late final _cc = TextEditingController(text: widget.prefs.getString('cc') ?? '91');
  String _result = '';

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Settings')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          TextField(
            controller: _cc,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Country code for 10-digit numbers'),
            onChanged: (v) => widget.prefs.setString('cc', v.replaceAll(RegExp(r'\D'), '')),
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: () async {
              await widget.prefs.remove('sent');
              setState(() => _result = '"Sent" marks cleared.');
            },
            child: const Text('Clear all "Sent" marks'),
          ),
          const SizedBox(height: 8),
          Text(_result, style: const TextStyle(fontSize: 16)),
          const SizedBox(height: 24),
          const Text('The invitation message and picture are built into this app version.', style: TextStyle(fontSize: 15)),
        ]),
      );
}
