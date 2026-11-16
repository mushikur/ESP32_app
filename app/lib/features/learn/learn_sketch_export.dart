import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'learn_catalog.dart';

class LearnSketchActions extends StatefulWidget {
  const LearnSketchActions({
    required this.project,
    required this.language,
    super.key,
  });

  final LearnProject project;
  final LearnLanguage language;

  @override
  State<LearnSketchActions> createState() => _LearnSketchActionsState();
}

class _LearnSketchActionsState extends State<LearnSketchActions> {
  static const _channel = MethodChannel('esp_iot/learn_export');
  bool _saving = false;

  Future<void> _save() async {
    setState(() => _saving = true);
    final language = widget.language;
    final name = widget.project.sketchFileName;
    var message = language.pick(
      'Could not save the sketch. Try another folder or copy the code.',
      'স্কেচ সেভ করা যায়নি। অন্য ফোল্ডারে চেষ্টা করুন বা কোড কপি করুন।',
    );
    try {
      final saved = await _channel.invokeMethod<bool>('saveSketch', {
        'name': name,
        'bytes': Uint8List.fromList(utf8.encode(widget.project.sketch)),
      });
      if (saved == false) return;
      if (saved == true) {
        message = language.pick('Sketch saved', 'স্কেচ সেভ হয়েছে');
      }
    } on Exception {
      // Keep the localized save failure message.
    } finally {
      if (mounted) setState(() => _saving = false);
    }
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final language = widget.language;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        OutlinedButton.icon(
          onPressed: () => copyLearnText(
            context,
            widget.project.sketch,
            language,
            language.pick('Sketch copied', 'স্কেচ কপি হয়েছে'),
          ),
          icon: const Icon(Icons.content_copy_rounded),
          label: Text(language.pick('Copy sketch', 'স্কেচ কপি করুন')),
        ),
        FilledButton.tonalIcon(
          onPressed: _saving ? null : _save,
          icon: const Icon(Icons.download_rounded),
          label: Text(
            _saving
                ? language.pick('Saving sketch…', 'স্কেচ সেভ হচ্ছে…')
                : language.pick('Download .ino', '.ino ডাউনলোড করুন'),
          ),
        ),
      ],
    );
  }
}

Future<void> copyLearnText(
  BuildContext context,
  String text,
  LearnLanguage language,
  String confirmation,
) async {
  var message = confirmation;
  try {
    await Clipboard.setData(ClipboardData(text: text));
  } on Exception {
    message = language.pick(
      'Could not copy. Try selecting the text manually.',
      'কপি করা যায়নি। লেখাটি বেছে নিজে কপি করার চেষ্টা করুন।',
    );
  }
  if (context.mounted) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}
