import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AnhsTeamMeetingMinutesApp());
}

class AnhsTeamMeetingMinutesApp extends StatefulWidget {
  const AnhsTeamMeetingMinutesApp({super.key});

  @override
  State<AnhsTeamMeetingMinutesApp> createState() => _AnhsTeamMeetingMinutesAppState();
}

class _AnhsTeamMeetingMinutesAppState extends State<AnhsTeamMeetingMinutesApp> {
  bool _isDark = true;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "Anh's TEAM - Biên Bản Họp Tự Động",
      debugShowCheckedModeBanner: false,
      themeMode: _isDark ? ThemeMode.dark : ThemeMode.light,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorSchemeSeed: const Color(0xFF4F46E5),
        scaffoldBackgroundColor: const Color(0xFFF6F8FC),
        dividerTheme: const DividerThemeData(thickness: 0.8, space: 1),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: const Color(0xFF6366F1),
        scaffoldBackgroundColor: const Color(0xFF0B1021),
        dividerTheme: const DividerThemeData(thickness: 0.8, space: 1),
      ),
      home: MeetingMinutesHomeScreen(
        isDark: _isDark,
        onToggleTheme: () => setState(() => _isDark = !_isDark),
      ),
    );
  }
}

class SpeakerTurnItem {
  String speaker;
  String lang; // 'VI', 'EN', 'DE'
  String timestamp;
  String content;
  String translation;

  SpeakerTurnItem({
    required this.speaker,
    required this.lang,
    required this.timestamp,
    required this.content,
    this.translation = '',
  });

  Map<String, dynamic> toJson() => {
        'speaker': speaker,
        'lang': lang,
        'timestamp': timestamp,
        'content': content,
        'translation': translation,
      };
}

class ActionTaskItem {
  String task;
  String assignee;
  String coordinator;
  String deadline;

  ActionTaskItem({
    required this.task,
    required this.assignee,
    required this.coordinator,
    required this.deadline,
  });

  Map<String, dynamic> toJson() => {
        'task': task,
        'assignee': assignee,
        'coordinator': coordinator,
        'deadline': deadline,
      };
}

class MeetingMinutesHomeScreen extends StatefulWidget {
  final bool isDark;
  final VoidCallback onToggleTheme;

  const MeetingMinutesHomeScreen({
    super.key,
    required this.isDark,
    required this.onToggleTheme,
  });

  @override
  State<MeetingMinutesHomeScreen> createState() => _MeetingMinutesHomeScreenState();
}

class _MeetingMinutesHomeScreenState extends State<MeetingMinutesHomeScreen> {
  static const MethodChannel _channel = MethodChannel('com.anhsteam.meetingminutes/native');

  Map<String, dynamic> _status = {};
  List<Map<String, dynamic>> _recordings = [];
  List<Map<String, dynamic>> _exportedDocx = [];
  Timer? _pollTimer;

  // Ngôn ngữ nhận diện giọng nói: 'vi-VN', 'en-US', 'de-DE'
  String _selectedSpeechLocale = 'vi-VN';

  // Chế độ ngôn ngữ xuất Biên bản Word (.docx): 'VI', 'VI_EN', 'VI_DE', 'VI_EN_DE'
  String _docLanguageMode = 'VI';

  // Thông báo trạng thái tệp đã nhập
  String _importedFileBanner = '';
  bool _showManualInputSection = false;
  int _lastSyncedAutoTurnCount = 0;
  bool _wasAutoProcessing = false;

  // Controllers cho thông tin hành chính của Biên bản cuộc họp
  final TextEditingController _govBodyCtrl = TextEditingController(text: '');
  final TextEditingController _orgNameCtrl = TextEditingController(text: "ANH'S TEAM");
  final TextEditingController _docNumCtrl = TextEditingController(text: 'Số: 01/2026/BB-AT');
  final TextEditingController _locDateCtrl =
      TextEditingController(text: 'Hà Nội, ngày 16 tháng 10 năm 2026');
  final TextEditingController _meetingTitleCtrl =
      TextEditingController(text: 'BIÊN BẢN CUỘC HỌP');
  final TextEditingController _meetingSubjectCtrl =
      TextEditingController(text: 'Về việc tổng hợp nội dung và kết luận cuộc họp');
  final TextEditingController _startTimeCtrl =
      TextEditingController(text: '08 giờ 30 phút ngày 16/10/2026');
  final TextEditingController _endTimeCtrl =
      TextEditingController(text: '11 giờ 00 phút cùng ngày');
  final TextEditingController _venueCtrl =
      TextEditingController(text: 'Phòng họp trung tâm & Trực tuyến');
  final TextEditingController _chairNameCtrl = TextEditingController(text: 'Ông Trương Đức Anh');
  final TextEditingController _chairTitleCtrl =
      TextEditingController(text: "Trưởng nhóm Anh's TEAM - Chủ trì");
  final TextEditingController _secNameCtrl =
      TextEditingController(text: "Hệ thống Tự động Anh's TEAM");
  final TextEditingController _secTitleCtrl = TextEditingController(text: 'Thư ký cuộc họp');
  final TextEditingController _attendeesCtrl =
      TextEditingController(text: "Các thành viên tham dự cuộc họp của Anh's TEAM");

  // Controllers cho việc thêm thủ công (tùy chọn)
  final TextEditingController _liveSpeakerCtrl =
      TextEditingController(text: 'Ông Trương Đức Anh (Chủ trì)');
  final TextEditingController _liveContentCtrl = TextEditingController();
  final TextEditingController _liveTranslationCtrl = TextEditingController();

  // Controllers cho việc chỉnh sửa Kết luận và Nhiệm vụ tại Tab 2
  final TextEditingController _newConclusionCtrl = TextEditingController();
  final TextEditingController _newTaskNameCtrl = TextEditingController();
  final TextEditingController _newTaskAssigneeCtrl = TextEditingController();
  final TextEditingController _newTaskCoordCtrl = TextEditingController();
  final TextEditingController _newTaskDeadlineCtrl = TextEditingController();

  String _lastSyncedSpeech = '';
  String _lastExportedDocxPath = '';

  // Khởi tạo danh sách trống (Không để dữ liệu mẫu giả định - Tuân thủ Rule 12)
  final List<SpeakerTurnItem> _speakerTurns = [];
  final List<String> _conclusions = [];
  final List<ActionTaskItem> _actionItems = [];

  @override
  void initState() {
    super.initState();
    _refreshAll();
    _pollTimer = Timer.periodic(const Duration(seconds: 1), (_) => _refreshStatusOnly());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _govBodyCtrl.dispose();
    _orgNameCtrl.dispose();
    _docNumCtrl.dispose();
    _locDateCtrl.dispose();
    _meetingTitleCtrl.dispose();
    _meetingSubjectCtrl.dispose();
    _startTimeCtrl.dispose();
    _endTimeCtrl.dispose();
    _venueCtrl.dispose();
    _chairNameCtrl.dispose();
    _chairTitleCtrl.dispose();
    _secNameCtrl.dispose();
    _secTitleCtrl.dispose();
    _attendeesCtrl.dispose();
    _liveSpeakerCtrl.dispose();
    _liveContentCtrl.dispose();
    _liveTranslationCtrl.dispose();
    _newConclusionCtrl.dispose();
    _newTaskNameCtrl.dispose();
    _newTaskAssigneeCtrl.dispose();
    _newTaskCoordCtrl.dispose();
    _newTaskDeadlineCtrl.dispose();
    super.dispose();
  }

  Future<void> _refreshAll() async {
    await _refreshStatusOnly();
    await _refreshFiles();
  }

  Future<void> _refreshStatusOnly() async {
    try {
      final res = await _channel.invokeMethod('getSystemStatus');
      if (res is Map && mounted) {
        final map = Map<String, dynamic>.from(res);

        // Đồng bộ kết quả đọc giọng nói trực tiếp (nếu có)
        final finalSpeech = (map['latestFinalSpeech'] ?? '').toString().trim();
        if (finalSpeech.isNotEmpty && finalSpeech != _lastSyncedSpeech) {
          _lastSyncedSpeech = finalSpeech;
          _liveContentCtrl.text = finalSpeech;
        }

        // Đồng bộ tự động các lượt phát biểu, kết luận & nhiệm vụ từ AutoAudioMinutesProcessor
        final bool isAuto = map['isAutoProcessing'] == true;
        final List<dynamic> autoTurnsRaw = (map['autoTranscribedTurns'] as List?) ?? [];
        final List<dynamic> autoConcRaw = (map['autoExtractedConclusions'] as List?) ?? [];
        final List<dynamic> autoActRaw = (map['autoExtractedActions'] as List?) ?? [];
        final String autoDocx = (map['autoGeneratedDocxPath'] ?? '').toString();

        if (autoTurnsRaw.length != _lastSyncedAutoTurnCount || (_wasAutoProcessing && !isAuto)) {
          _lastSyncedAutoTurnCount = autoTurnsRaw.length;
          _speakerTurns
            ..clear()
            ..addAll(
              autoTurnsRaw.whereType<Map>().map((m) {
                final tm = Map<String, dynamic>.from(m);
                return SpeakerTurnItem(
                  speaker: (tm['speaker'] ?? 'Đại biểu').toString(),
                  lang: (tm['lang'] ?? 'VI').toString(),
                  timestamp: (tm['timestamp'] ?? '00:00:00').toString(),
                  content: (tm['content'] ?? '').toString(),
                  translation: (tm['translation'] ?? '').toString(),
                );
              }),
            );
        }

        if (autoConcRaw.isNotEmpty && (_wasAutoProcessing || _conclusions.isEmpty)) {
          _conclusions
            ..clear()
            ..addAll(autoConcRaw.map((e) => e.toString()));
        }

        if (autoActRaw.isNotEmpty && (_wasAutoProcessing || _actionItems.isEmpty)) {
          _actionItems
            ..clear()
            ..addAll(
              autoActRaw.whereType<Map>().map((m) {
                final am = Map<String, dynamic>.from(m);
                return ActionTaskItem(
                  task: (am['task'] ?? '').toString(),
                  assignee: (am['assignee'] ?? 'Bộ phận chuyên môn').toString(),
                  coordinator: (am['coordinator'] ?? 'Các đơn vị').toString(),
                  deadline: (am['deadline'] ?? 'Theo kế hoạch').toString(),
                );
              }),
            );
        }

        if (autoDocx.isNotEmpty && autoDocx != _lastExportedDocxPath) {
          _lastExportedDocxPath = autoDocx;
          _refreshFiles();
        }

        _wasAutoProcessing = isAuto;
        setState(() {
          _status = map;
        });
      }
    } catch (_) {}
  }

  Future<void> _refreshFiles() async {
    try {
      final recs = await _channel.invokeMethod('listRecordings');
      final docs = await _channel.invokeMethod('listExportedDocx');
      if (mounted) {
        setState(() {
          if (recs is List) {
            _recordings = recs.map((e) => Map<String, dynamic>.from(e as Map)).toList();
          }
          if (docs is List) {
            _exportedDocx = docs.map((e) => Map<String, dynamic>.from(e as Map)).toList();
          }
        });
      }
    } catch (_) {}
  }

  String _formatDuration(int totalSeconds) {
    final hrs = totalSeconds ~/ 3600;
    final mins = (totalSeconds % 3600) ~/ 60;
    final secs = totalSeconds % 60;
    return '${hrs.toString().padLeft(2, '0')}:${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  String _localeToShortTag(String locale) {
    if (locale.startsWith('en')) return 'EN';
    if (locale.startsWith('de')) return 'DE';
    return 'VI';
  }

  /// NHẬP FILE CÓ SẴN TRONG MÁY -> TỰ ĐỘNG GỠ BĂNG & TỰ SINH BIÊN BẢN (KHÔNG CẦN NHẬP TAY)
  Future<void> _pickAndImportExistingFile() async {
    try {
      final res = await _channel.invokeMethod('pickAndImportFile', {
        'locale': _selectedSpeechLocale,
        'docLanguageMode': _docLanguageMode,
      });
      if (res == null || res is! Map) return;

      final info = Map<String, dynamic>.from(res);
      final category = (info['fileCategory'] ?? '').toString();
      final name = (info['name'] ?? '').toString();
      final suggestedSubject = (info['suggestedSubject'] ?? '').toString();

      if (category == 'AUDIO') {
        final durSec = (info['durationSec'] as num?)?.toInt() ?? 0;
        final sha = (info['sha256Short'] ?? '').toString();

        setState(() {
          _speakerTurns.clear();
          _conclusions.clear();
          _actionItems.clear();
          _lastSyncedAutoTurnCount = 0;
          if (suggestedSubject.isNotEmpty) {
            _meetingSubjectCtrl.text = suggestedSubject;
          }
          _importedFileBanner =
              'Đang xử lý tự động tệp "$name" (${_formatDuration(durSec)} • SHA256: $sha) -> Tự động gỡ băng từng đoạn và sinh Biên bản Word (.docx)...';
        });
        await _refreshAll();
      } else if (category == 'DOCUMENT') {
        final rawTurns = (info['turns'] as List?) ?? [];
        final rawConclusions = (info['conclusions'] as List?) ?? [];
        final rawActions = (info['actionItems'] as List?) ?? [];

        final importedTurns = <SpeakerTurnItem>[];
        for (final item in rawTurns) {
          if (item is Map) {
            final m = Map<String, dynamic>.from(item);
            importedTurns.add(
              SpeakerTurnItem(
                speaker: (m['speaker'] ?? 'Đại biểu').toString(),
                lang: (m['lang'] ?? 'VI').toString(),
                timestamp: (m['timestamp'] ?? '00:00:00').toString(),
                content: (m['content'] ?? '').toString(),
                translation: (m['translation'] ?? '').toString(),
              ),
            );
          }
        }

        final importedConclusions =
            rawConclusions.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();

        final importedActions = <ActionTaskItem>[];
        for (final item in rawActions) {
          if (item is Map) {
            final m = Map<String, dynamic>.from(item);
            importedActions.add(
              ActionTaskItem(
                task: (m['task'] ?? '').toString(),
                assignee: (m['assignee'] ?? 'Bộ phận chuyên môn').toString(),
                coordinator: (m['coordinator'] ?? 'Các đơn vị').toString(),
                deadline: (m['deadline'] ?? 'Theo kế hoạch').toString(),
              ),
            );
          }
        }

        if (mounted) {
          setState(() {
            if (suggestedSubject.isNotEmpty) {
              _meetingSubjectCtrl.text = suggestedSubject;
            }
            _speakerTurns
              ..clear()
              ..addAll(importedTurns);
            _conclusions
              ..clear()
              ..addAll(importedConclusions);
            _actionItems
              ..clear()
              ..addAll(importedActions);
            _importedFileBanner =
                'Đã tự động trích xuất ${importedTurns.length} lượt phát biểu từ "$name" và xuất sang Biên bản Word (.docx).';
          });
          // Tự động xuất luôn file .DOCX cho người dùng
          await _exportDocxAndOptionallyShare(shareImmediately: false);
        }
      }
    } on PlatformException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi nhập tệp: ${e.message}')),
        );
      }
    }
  }

  /// CHẠY TỰ ĐỘNG GỠ BĂNG & TẠO BIÊN BẢN CHO 1 FILE GHI ÂM TRONG MÁY
  Future<void> _autoGenerateMinutesFromAudioItem(Map<String, dynamic> rec) async {
    final path = (rec['path'] ?? '').toString();
    final name = (rec['name'] ?? '').toString();
    final durSec = (rec['durationSec'] as num?)?.toInt() ?? 0;

    if (path.isEmpty) return;
    setState(() {
      _speakerTurns.clear();
      _conclusions.clear();
      _actionItems.clear();
      _lastSyncedAutoTurnCount = 0;
      _meetingSubjectCtrl.text = 'Biên bản cuộc họp (Trích xuất tự động từ tệp: $name)';
      _importedFileBanner =
          'Đang tự động gỡ băng tệp "$name" (${_formatDuration(durSec)}) và tự sinh Biên bản cuộc họp...';
    });

    await _channel.invokeMethod('startAutoProcessAudioPath', {
      'path': path,
      'locale': _selectedSpeechLocale,
      'docLanguageMode': _docLanguageMode,
    });
    await _refreshStatusOnly();
  }

  Future<void> _toggleMeetingRecording() async {
    final isRec = _status['isRecording'] == true;
    if (isRec) {
      setState(() {
        _speakerTurns.clear();
        _conclusions.clear();
        _actionItems.clear();
        _lastSyncedAutoTurnCount = 0;
      });
      await _channel.invokeMethod('stopMeetingRecording');
      await _refreshAll();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Đã dừng thu âm -> Hệ thống đang tự động gỡ băng và sinh Biên bản Word (.docx)!'),
          ),
        );
      }
    } else {
      try {
        final gain = (_status['roomGainBoost'] as num?)?.toDouble() ?? 2.5;
        await _channel.invokeMethod('startMeetingRecording', {
          'meetingTitle': _meetingSubjectCtrl.text,
          'roomGainBoost': gain,
        });
        await _refreshStatusOnly();
      } on PlatformException catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.message ?? 'Vui lòng cấp quyền Microphone')),
          );
        }
      }
    }
  }

  Future<void> _toggleVoiceDictation() async {
    final isListening = _status['isListeningSpeech'] == true;
    if (isListening) {
      await _channel.invokeMethod('stopVoiceDictation');
      await _refreshStatusOnly();
    } else {
      try {
        await _channel.invokeMethod('startVoiceDictation', {
          'locale': _selectedSpeechLocale,
        });
        await _refreshStatusOnly();
      } on PlatformException catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.message ?? 'Không thể khởi chạy nhận diện giọng nói')),
          );
        }
      }
    }
  }

  void _addLiveTurnToMinutes() {
    final text = _liveContentCtrl.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng nhập hoặc đọc nội dung phát biểu trước khi thêm.')),
      );
      return;
    }
    final elapsedSec = (_status['elapsedSeconds'] as num?)?.toInt() ?? 0;
    final playingPath = (_status['currentlyPlayingPath'] ?? '').toString();
    final playPosSec = (_status['playbackPositionSec'] as num?)?.toInt() ?? 0;

    final String ts;
    if (_status['isRecording'] == true) {
      ts = _formatDuration(elapsedSec);
    } else if (playingPath.isNotEmpty) {
      ts = _formatDuration(playPosSec);
    } else {
      ts = TimeOfDay.now().format(context);
    }

    setState(() {
      _speakerTurns.add(
        SpeakerTurnItem(
          speaker: _liveSpeakerCtrl.text.trim().isEmpty
              ? 'Đại biểu phát biểu'
              : _liveSpeakerCtrl.text.trim(),
          lang: _localeToShortTag(_selectedSpeechLocale),
          timestamp: ts,
          content: text,
          translation: _liveTranslationCtrl.text.trim(),
        ),
      );
      _liveContentCtrl.clear();
      _liveTranslationCtrl.clear();
      _lastSyncedSpeech = '';
    });
    _channel.invokeMethod('clearSpeechBuffer');
  }

  void _applyDocLanguageModeTitle(String mode) {
    setState(() {
      _docLanguageMode = mode;
      if (mode == 'VI') {
        _meetingTitleCtrl.text = 'BIÊN BẢN CUỘC HỌP';
      } else if (mode == 'VI_EN') {
        _meetingTitleCtrl.text = 'BIÊN BẢN CUỘC HỌP / MEETING MINUTES';
      } else if (mode == 'VI_DE') {
        _meetingTitleCtrl.text = 'BIÊN BẢN CUỘC HỌP / SITZUNGSPROTOKOLL';
      } else {
        _meetingTitleCtrl.text = 'BIÊN BẢN CUỘC HỌP / MEETING MINUTES / SITZUNGSPROTOKOLL';
      }
    });
  }

  Map<String, dynamic> _buildMinutesJsonMap() {
    return {
      'docLanguageMode': _docLanguageMode,
      'governingBody': _govBodyCtrl.text.trim(),
      'organizationName': _orgNameCtrl.text.trim(),
      'documentNumber': _docNumCtrl.text.trim(),
      'locationDate': _locDateCtrl.text.trim(),
      'meetingTitle': _meetingTitleCtrl.text.trim(),
      'meetingSubject': _meetingSubjectCtrl.text.trim(),
      'startTime': _startTimeCtrl.text.trim(),
      'endTime': _endTimeCtrl.text.trim(),
      'venue': _venueCtrl.text.trim(),
      'chairName': _chairNameCtrl.text.trim(),
      'chairTitle': _chairTitleCtrl.text.trim(),
      'secretaryName': _secNameCtrl.text.trim(),
      'secretaryTitle': _secTitleCtrl.text.trim(),
      'attendeesList': _attendeesCtrl.text.trim(),
      'speakerTurns': _speakerTurns.map((e) => e.toJson()).toList(),
      'conclusions': _conclusions,
      'actionItems': _actionItems.map((e) => e.toJson()).toList(),
    };
  }

  String _buildPlainTextPreview() {
    final sb = StringBuilderPlain();
    if (_govBodyCtrl.text.trim().isNotEmpty) {
      sb.writeln(_govBodyCtrl.text.trim().toUpperCase());
    }
    sb.writeln('${_orgNameCtrl.text.trim().toUpperCase()}  |  CỘNG HÒA XÃ HỘI CHỦ NGHĨA VIỆT NAM');
    sb.writeln('${_docNumCtrl.text.trim()}  |  Độc lập - Tự do - Hạnh phúc');
    sb.writeln(_locDateCtrl.text.trim());
    sb.writeln('');
    sb.writeln(_meetingTitleCtrl.text.trim().toUpperCase());
    sb.writeln(_meetingSubjectCtrl.text.trim());
    sb.writeln('');
    sb.writeln('I. THỜI GIAN, ĐỊA ĐIỂM VÀ THÀNH PHẦN THAM DỰ');
    sb.writeln('1. Thời gian bắt đầu: ${_startTimeCtrl.text.trim()}.');
    sb.writeln('2. Địa điểm / Hình thức: ${_venueCtrl.text.trim()}.');
    sb.writeln('3. Thành phần tham dự:');
    sb.writeln('- Chủ trì: ${_chairNameCtrl.text.trim()} (${_chairTitleCtrl.text.trim()}).');
    sb.writeln('- Thư ký: ${_secNameCtrl.text.trim()} (${_secTitleCtrl.text.trim()}).');
    if (_attendeesCtrl.text.trim().isNotEmpty) {
      sb.writeln('- Thành viên: ${_attendeesCtrl.text.trim()}.');
    }
    sb.writeln('');
    sb.writeln('II. NỘI DUNG DIỄN BIẾN CUỘC HỌP');
    if (_speakerTurns.isEmpty) {
      sb.writeln('- (Chưa có nội dung gỡ băng. Hãy bấm "Nhập File Có Sẵn" để hệ thống tự động gỡ băng và sinh biên bản).');
    } else {
      for (int i = 0; i < _speakerTurns.length; i++) {
        final t = _speakerTurns[i];
        sb.writeln('${i + 1}. [${t.lang}] Phát biểu của ${t.speaker} (Mốc: ${t.timestamp}):');
        for (final line in t.content.split('\n')) {
          if (line.trim().isNotEmpty) {
            sb.writeln('- ${line.trim()}');
          }
        }
        if (t.translation.trim().isNotEmpty) {
          sb.writeln('  -> [Dịch đối sánh]: ${t.translation.trim()}');
        }
      }
    }
    sb.writeln('');
    sb.writeln('III. KẾT LUẬN VÀ PHÂN CÔNG NHIỆM VỤ');
    for (final c in _conclusions) {
      sb.writeln('- $c');
    }
    if (_actionItems.isNotEmpty) {
      sb.writeln('');
      sb.writeln('Bảng phân công nhiệm vụ:');
      for (int i = 0; i < _actionItems.length; i++) {
        final a = _actionItems[i];
        sb.writeln(
            '${i + 1}. ${a.task} | Chủ trì: ${a.assignee} | Phối hợp: ${a.coordinator} | Hạn: ${a.deadline}');
      }
    }
    sb.writeln('');
    sb.writeln(
        'Cuộc họp kết thúc vào lúc ${_endTimeCtrl.text.trim()}. Biên bản đã được thông qua và lưu hồ sơ./.');
    return sb.toString();
  }

  Future<void> _exportDocxAndOptionallyShare({required bool shareImmediately}) async {
    try {
      final payload = jsonEncode(_buildMinutesJsonMap());
      final res = await _channel.invokeMethod('generateMeetingDocx', {
        'jsonPayload': payload,
      });
      await _refreshFiles();
      if (res is Map && mounted) {
        final path = (res['path'] ?? '').toString();
        final pubPath = (res['publicDownloadPath'] ?? path).toString();
        setState(() {
          _lastExportedDocxPath = path;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Đã xuất Biên bản Word (.docx) tại: $pubPath'),
            duration: const Duration(seconds: 4),
          ),
        );
        if (shareImmediately && path.isNotEmpty) {
          await _channel.invokeMethod('shareFile', {
            'path': path,
            'mimeType':
                'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
          });
        }
      }
    } on PlatformException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi xuất .docx: ${e.message}')),
        );
      }
    }
  }

  Future<void> _shareExistingOrExportDocx() async {
    if (_lastExportedDocxPath.isNotEmpty) {
      final ok = await _channel.invokeMethod('shareFile', {
        'path': _lastExportedDocxPath,
        'mimeType':
            'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      });
      if (ok == true) return;
    }
    await _exportDocxAndOptionallyShare(shareImmediately: true);
  }

  Future<void> _sharePlainTextMinutes() async {
    final preview = _buildPlainTextPreview();
    await _channel.invokeMethod('shareText', {
      'text': preview,
      'subject': _meetingSubjectCtrl.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool micGranted = _status['micPermissionGranted'] == true;
    final bool isRecording = _status['isRecording'] == true;
    final int elapsedSec = (_status['elapsedSeconds'] as num?)?.toInt() ?? 0;
    final int peakAmp = (_status['peakAmplitude'] as num?)?.toInt() ?? 0;
    final double roomGain = (_status['roomGainBoost'] as num?)?.toDouble() ?? 2.5;
    final bool isListeningSpeech = _status['isListeningSpeech'] == true;
    final String partialSpeech = (_status['latestPartialSpeech'] ?? '').toString();
    final String playingPath = (_status['currentlyPlayingPath'] ?? '').toString();
    final int playPosSec = (_status['playbackPositionSec'] as num?)?.toInt() ?? 0;
    final int playDurSec = (_status['playbackDurationSec'] as num?)?.toInt() ?? 0;

    final bool isAutoProcessing = _status['isAutoProcessing'] == true;
    final int autoProgressPct = (_status['autoProgressPercent'] as num?)?.toInt() ?? 0;
    final String autoStatusMsg = (_status['autoStatusMessage'] ?? '').toString();
    final String autoPartialTxt = (_status['autoPartialText'] ?? '').toString();

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          elevation: 0,
          scrolledUnderElevation: 0,
          titleSpacing: 12,
          title: Row(
            children: [
              ClipOval(
                child: Image.asset(
                  'assets/logo_anhs_team.png',
                  width: 38,
                  height: 38,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Anh's TEAM • Biên Bản Tự Động",
                      style: TextStyle(fontSize: 15.8, fontWeight: FontWeight.w800),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      'Tự động Gỡ băng File Ghi âm -> Sinh Word NĐ 30',
                      style: TextStyle(
                        fontSize: 11.2,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'Chia sẻ File Biên bản (.DOCX) qua Zalo / Email',
              icon: const Icon(Icons.share),
              onPressed: _shareExistingOrExportDocx,
            ),
            IconButton(
              tooltip: 'Nhập file ghi âm để tự sinh biên bản',
              icon: const Icon(Icons.file_upload_outlined),
              onPressed: _pickAndImportExistingFile,
            ),
            IconButton(
              tooltip: 'Chuyển chế độ Sáng/Tối',
              icon: Icon(widget.isDark ? Icons.light_mode : Icons.dark_mode),
              onPressed: widget.onToggleTheme,
            ),
          ],
          bottom: const TabBar(
            isScrollable: false,
            dividerColor: Colors.transparent,
            labelStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            unselectedLabelStyle: TextStyle(fontSize: 11.5),
            tabs: [
              Tab(icon: Icon(Icons.auto_awesome, size: 19), text: 'Tự Động'),
              Tab(icon: Icon(Icons.edit_note, size: 19), text: 'Soạn Họp'),
              Tab(icon: Icon(Icons.description_outlined, size: 19), text: 'Xuất Word'),
              Tab(icon: Icon(Icons.folder_copy_outlined, size: 19), text: 'File Máy'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildRecordAndTranscribeTab(
              micGranted: micGranted,
              isRecording: isRecording,
              elapsedSec: elapsedSec,
              peakAmp: peakAmp,
              roomGain: roomGain,
              isListeningSpeech: isListeningSpeech,
              partialSpeech: partialSpeech,
              playingPath: playingPath,
              playPosSec: playPosSec,
              playDurSec: playDurSec,
              isAutoProcessing: isAutoProcessing,
              autoProgressPct: autoProgressPct,
              autoStatusMsg: autoStatusMsg,
              autoPartialTxt: autoPartialTxt,
            ),
            _buildMinutesEditorTab(),
            _buildPreviewAndExportTab(),
            _buildStorageArchiveTab(),
          ],
        ),
      ),
    );
  }

  /// TAB 1: TỰ ĐỘNG XỬ LÝ FILE GHI ÂM CÓ SẴN THÀNH BIÊN BẢN CUỘC HỌP (RULE 14)
  Widget _buildRecordAndTranscribeTab({
    required bool micGranted,
    required bool isRecording,
    required int elapsedSec,
    required int peakAmp,
    required double roomGain,
    required bool isListeningSpeech,
    required String partialSpeech,
    required String playingPath,
    required int playPosSec,
    required int playDurSec,
    required bool isAutoProcessing,
    required int autoProgressPct,
    required String autoStatusMsg,
    required String autoPartialTxt,
  }) {
    final cs = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      children: [
        if (!micGranted)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
            decoration: BoxDecoration(
              color: Colors.amber.withOpacity(0.15),
              border: Border(
                left: BorderSide(color: Colors.amber.shade700, width: 3.5),
              ),
            ),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'BẮT BUỘC: Bấm "Cấp quyền" để hệ thống Nhận diện giọng nói (Speech Engine) của Android được phép gỡ băng tự động tệp âm thanh.',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: () async {
                    await _channel.invokeMethod('requestPermissions');
                    await _refreshAll();
                  },
                  icon: const Icon(Icons.verified_user, size: 16),
                  label: const Text('Cấp quyền'),
                ),
              ],
            ),
          ),

        // HIỂN THỊ TIẾN TRÌNH TỰ ĐỘNG GỠ BĂNG & TỰ SINH BIÊN BẢN
        if (isAutoProcessing || autoStatusMsg.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            decoration: BoxDecoration(
              color: isAutoProcessing
                  ? cs.primaryContainer.withOpacity(0.28)
                  : Colors.green.withOpacity(0.14),
              border: Border(
                left: BorderSide(
                  color: isAutoProcessing ? cs.primary : Colors.green,
                  width: 4,
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        isAutoProcessing
                            ? 'ĐANG TỰ ĐỘNG GỠ BĂNG & SINH BIÊN BẢN ($autoProgressPct%)'
                            : 'HOÀN TẤT TỰ ĐỘNG SINH BIÊN BẢN CUỘC HỌP',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13.2,
                          color: isAutoProcessing ? cs.primary : Colors.green,
                        ),
                      ),
                    ),
                    if (isAutoProcessing)
                      TextButton.icon(
                        style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                        onPressed: () => _channel.invokeMethod('stopAutoProcessEarly'),
                        icon: const Icon(Icons.done_all, size: 17),
                        label: const Text('Xuất Ngay'),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                LinearProgressIndicator(
                  value: (autoProgressPct / 100.0).clamp(0.02, 1.0),
                  minHeight: 6,
                  color: isAutoProcessing ? cs.primary : Colors.green,
                ),
                const SizedBox(height: 6),
                Text(
                  autoStatusMsg,
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
                if (autoPartialTxt.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Đang nghe câu: "$autoPartialTxt..."',
                    style: const TextStyle(
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                      color: Colors.amber,
                    ),
                  ),
                ],
                if (!isAutoProcessing) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: _shareExistingOrExportDocx,
                        icon: const Icon(Icons.share, size: 17),
                        label: const Text('Chia Sẻ File Biên Bản (.DOCX)'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _sharePlainTextMinutes,
                        icon: const Icon(Icons.send_outlined, size: 17),
                        label: const Text('Chia Sẻ Văn Bản (Zalo/Text)'),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),

        // DUY NHẤT 1 THẺ ĐƠN CẤP (SINGLE-LEVEL CARD) CHO BỘ TỰ ĐỘNG HÓA 1-CHẠM
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isRecording ? Colors.redAccent : cs.outlineVariant.withOpacity(0.6),
              width: 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '1. Chọn Ngôn ngữ chính của File Ghi âm (VI / EN / DE):',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
              ),
              const SizedBox(height: 6),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final langOpt in [
                      {'locale': 'vi-VN', 'label': '🇻🇳 Tiếng Việt (vi-VN)'},
                      {'locale': 'en-US', 'label': '🇬🇧 English (en-US)'},
                      {'locale': 'de-DE', 'label': '🇩🇪 Tiếng Đức (de-DE)'},
                    ])
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text(langOpt['label']!, style: const TextStyle(fontSize: 12.2)),
                          selected: _selectedSpeechLocale == langOpt['locale'],
                          side: BorderSide.none,
                          showCheckmark: false,
                          visualDensity: VisualDensity.compact,
                          onSelected: (_) {
                            setState(() {
                              _selectedSpeechLocale = langOpt['locale']!;
                            });
                          },
                        ),
                      ),
                  ],
                ),
              ),

              const SizedBox(height: 12),
              const Text(
                '2. Bấm Chọn File Ghi Âm Có Sẵn -> Tự Động Sinh Biên Bản (.DOCX):',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
              ),
              const SizedBox(height: 8),

              // NÚT CHÍNH: NHẬP FILE GHI ÂM -> TỰ ĐỘNG GỠ BĂNG & SINH BIÊN BẢN 100%
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                  ),
                  onPressed: isAutoProcessing ? null : _pickAndImportExistingFile,
                  icon: const Icon(Icons.auto_fix_high, size: 20),
                  label: const Text(
                    'Nhập File Ghi Âm (.M4A/.WAV/.MP3) -> Tự Sinh Biên Bản',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
                  ),
                ),
              ),

              const SizedBox(height: 8),

              // NÚT PHỤ: THU ÂM MỚI PHÒP HỌP (KHI DỪNG CŨNG TỰ ĐỘNG GỠ BĂNG)
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: isRecording ? Colors.redAccent : null,
                      ),
                      onPressed: _toggleMeetingRecording,
                      icon: Icon(
                        isRecording ? Icons.stop_circle : Icons.fiber_manual_record,
                        size: 18,
                        color: isRecording ? Colors.redAccent : cs.primary,
                      ),
                      label: Text(
                        isRecording
                            ? 'Dừng Thu (${_formatDuration(elapsedSec)}) & Tự Sinh Biên Bản'
                            : 'Hoặc Thu Âm Cuộc Họp Mới (Tự gỡ băng khi dừng)',
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
                      ),
                    ),
                  ),
                ],
              ),

              if (isRecording) ...[
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: (peakAmp / 32767.0).clamp(0.03, 1.0),
                  minHeight: 5,
                  color: Colors.redAccent,
                ),
              ],

              const SizedBox(height: 8),

              // NÚT CHIA SẺ FILE BIÊN BẢN (.DOCX) TRỰC TIẾP TRÊN MÀN HÌNH CHÍNH
              Row(
                children: [
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: _shareExistingOrExportDocx,
                      icon: const Icon(Icons.share, size: 18),
                      label: const Text(
                        'Chia Sẻ File Biên Bản (.DOCX)',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.8),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: _sharePlainTextMinutes,
                    icon: const Icon(Icons.send_outlined, size: 17),
                    label: const Text(
                      'Gửi Text',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
                    ),
                  ),
                ],
              ),

              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Divider(height: 1),
              ),

              // MỤC BỔ SUNG THỦ CÔNG (MẶC ĐỊNH THU GỌN ĐỂ KHÔNG PHẢI GÕ TAY)
              InkWell(
                onTap: () => setState(() => _showManualInputSection = !_showManualInputSection),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Bổ sung / Ghi chú thêm lượt phát biểu thủ công (Tùy chọn)',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    Icon(
                      _showManualInputSection ? Icons.expand_less : Icons.expand_more,
                      size: 20,
                      color: cs.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
              if (_showManualInputSection) ...[
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Nhập bổ sung:',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
                    ),
                    TextButton.icon(
                      style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                      onPressed: _toggleVoiceDictation,
                      icon: Icon(
                        isListeningSpeech ? Icons.mic_off : Icons.record_voice_over,
                        size: 17,
                      ),
                      label: Text(
                        isListeningSpeech ? 'Dừng nghe' : 'Đọc Mic trực tiếp',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
                TextField(
                  controller: _liveSpeakerCtrl,
                  style: const TextStyle(fontSize: 13),
                  decoration: const InputDecoration(
                    labelText: 'Người phát biểu',
                    isDense: true,
                    border: UnderlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _liveContentCtrl,
                  maxLines: 2,
                  style: const TextStyle(fontSize: 13),
                  decoration: const InputDecoration(
                    labelText: 'Nội dung phát biểu bổ sung',
                    isDense: true,
                    border: UnderlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.tonalIcon(
                    onPressed: _addLiveTurnToMinutes,
                    icon: const Icon(Icons.add, size: 17),
                    label: const Text('Thêm vào Biên bản'),
                  ),
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: 16),

        // DANH SÁCH NỘI DUNG ĐÃ TỰ ĐỘNG GỠ BĂNG TỪ FILE GHI ÂM (PHẲNG HÓA 100%)
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                'Nội dung tự động gỡ băng (${_speakerTurns.length} đoạn phát biểu)',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
              ),
            ),
            if (_speakerTurns.isNotEmpty)
              TextButton.icon(
                style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                onPressed: () => _exportDocxAndOptionallyShare(shareImmediately: true),
                icon: const Icon(Icons.description_outlined, size: 17),
                label: const Text('Xuất .DOCX Ngay'),
              ),
          ],
        ),
        const SizedBox(height: 6),

        if (_speakerTurns.isEmpty && !isAutoProcessing)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(color: cs.outlineVariant, width: 3),
              ),
            ),
            child: Text(
              'Chưa có dữ liệu gỡ băng.\nHãy bấm nút "Nhập File Ghi Âm (.M4A/.WAV/.MP3) -> Tự Sinh Biên Bản" ở trên (hoặc chọn file từ tab "File Máy") để hệ thống tự động tách câu, gỡ băng và lập Biên bản cuộc họp mà không cần nhập tay.',
              style: TextStyle(fontSize: 12.8, color: cs.onSurfaceVariant, height: 1.4),
            ),
          )
        else
          ..._speakerTurns.asMap().entries.map((entry) {
            final idx = entry.key;
            final turn = entry.value;
            final Color langColor = turn.lang == 'DE'
                ? Colors.amber.shade700
                : (turn.lang == 'EN' ? Colors.cyan : cs.primary);

            return Container(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(color: langColor, width: 3.5),
                  bottom: BorderSide(color: cs.outlineVariant.withOpacity(0.45), width: 0.8),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          '${idx + 1}. [${turn.lang}] ${turn.speaker}',
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.2),
                        ),
                      ),
                      Text(
                        '[${turn.timestamp}]',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontFamily: 'monospace',
                          color: cs.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.delete_outline, size: 18),
                        onPressed: () {
                          setState(() {
                            _speakerTurns.removeAt(idx);
                          });
                        },
                      ),
                    ],
                  ),
                  Text(
                    turn.content,
                    style: const TextStyle(fontSize: 13),
                  ),
                  if (turn.translation.trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      '↳ Dịch đối sánh: ${turn.translation}',
                      style: TextStyle(
                        fontSize: 12.2,
                        fontStyle: FontStyle.italic,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            );
          }),
      ],
    );
  }

  /// TAB 2: SOẠN THẢO CẤU TRÚC BIÊN BẢN CUỘC HỌP ĐA NGÔN NGỮ (PHẲNG HÓA 100% - RULE 14)
  Widget _buildMinutesEditorTab() {
    final cs = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: cs.outlineVariant.withOpacity(0.6), width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Chế độ Ngôn ngữ Xuất Biên bản (.DOCX):',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
              ),
              const SizedBox(height: 6),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final m in [
                      {'id': 'VI', 'label': '🇻🇳 Tiếng Việt (NĐ 30/2020)'},
                      {'id': 'VI_EN', 'label': '🇻🇳🇬🇧 Song ngữ Việt - Anh'},
                      {'id': 'VI_DE', 'label': '🇻🇳🇩🇪 Song ngữ Việt - Đức'},
                      {'id': 'VI_EN_DE', 'label': '🇻🇳🇬🇧🇩🇪 Đa ngữ Việt - Anh - Đức'},
                    ])
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text(m['label']!, style: const TextStyle(fontSize: 12)),
                          selected: _docLanguageMode == m['id'],
                          side: BorderSide.none,
                          showCheckmark: false,
                          visualDensity: VisualDensity.compact,
                          onSelected: (_) => _applyDocLanguageModeTitle(m['id']!),
                        ),
                      ),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Divider(height: 1),
              ),
              const Text(
                'I. Thông tin Hành chính & Thành phần tham dự',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _orgNameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Tên Cơ quan / Đơn vị lập biên bản',
                  isDense: true,
                  border: UnderlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _docNumCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Số & Ký hiệu biên bản',
                        isDense: true,
                        border: UnderlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _locDateCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Địa danh, ngày tháng năm',
                        isDense: true,
                        border: UnderlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _meetingTitleCtrl,
                decoration: const InputDecoration(
                  labelText: 'Tiêu đề Biên bản',
                  isDense: true,
                  border: UnderlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _meetingSubjectCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Trích yếu nội dung cuộc họp',
                  isDense: true,
                  border: UnderlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _startTimeCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Thời gian bắt đầu',
                        isDense: true,
                        border: UnderlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _endTimeCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Thời gian kết thúc',
                        isDense: true,
                        border: UnderlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _venueCtrl,
                decoration: const InputDecoration(
                  labelText: 'Địa điểm / Hình thức họp',
                  isDense: true,
                  border: UnderlineInputBorder(),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Divider(height: 1),
              ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _chairNameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Họ tên Chủ trì',
                        isDense: true,
                        border: UnderlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _chairTitleCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Chức vụ Chủ trì',
                        isDense: true,
                        border: UnderlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _secNameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Họ tên Thư ký',
                        isDense: true,
                        border: UnderlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _secTitleCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Chức vụ Thư ký',
                        isDense: true,
                        border: UnderlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _attendeesCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Thành viên tham dự',
                  isDense: true,
                  border: UnderlineInputBorder(),
                ),
              ),

              const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Divider(height: 1),
              ),

              // 2. KẾT LUẬN TỰ ĐỘNG TRÍCH XUẤT
              const Text(
                'III. Kết luận cuộc họp (Tự động trích xuất / Chỉnh sửa)',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5),
              ),
              const SizedBox(height: 6),
              ..._conclusions.asMap().entries.map((entry) {
                final idx = entry.key;
                final text = entry.value;
                return Container(
                  padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                  decoration: BoxDecoration(
                    border: Border(
                      left: BorderSide(color: Colors.teal, width: 3),
                      bottom: BorderSide(color: cs.outlineVariant.withOpacity(0.4), width: 0.7),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text('- $text', style: const TextStyle(fontSize: 13)),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.close, size: 17),
                        onPressed: () {
                          setState(() {
                            _conclusions.removeAt(idx);
                          });
                        },
                      ),
                    ],
                  ),
                );
              }),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _newConclusionCtrl,
                      decoration: const InputDecoration(
                        hintText: 'Nhập thêm ý kết luận (nếu cần)...',
                        isDense: true,
                        border: UnderlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonal(
                    onPressed: () {
                      final val = _newConclusionCtrl.text.trim();
                      if (val.isNotEmpty) {
                        setState(() {
                          _conclusions.add(val);
                          _newConclusionCtrl.clear();
                        });
                      }
                    },
                    child: const Text('+ Kết luận'),
                  ),
                ],
              ),

              const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Divider(height: 1),
              ),

              // 3. BẢNG PHÂN CÔNG NHIỆM VỤ
              const Text(
                'Bảng phân công nhiệm vụ (Tự động trích xuất / Chỉnh sửa)',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5),
              ),
              const SizedBox(height: 6),
              ..._actionItems.asMap().entries.map((entry) {
                final idx = entry.key;
                final item = entry.value;
                return Container(
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                  decoration: BoxDecoration(
                    border: Border(
                      left: BorderSide(color: cs.primary, width: 3),
                      bottom: BorderSide(color: cs.outlineVariant.withOpacity(0.4), width: 0.7),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${idx + 1}. ${item.task}',
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Chủ trì: ${item.assignee}  •  Phối hợp: ${item.coordinator}  •  Hạn: ${item.deadline}',
                              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.delete_outline, size: 18),
                        onPressed: () {
                          setState(() {
                            _actionItems.removeAt(idx);
                          });
                        },
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
      ],
    );
  }

  /// TAB 3: XEM TRƯỚC & XUẤT BẢN WORD (.DOCX) ĐA NGÔN NGỮ CHUẨN NGHỊ ĐỊNH 30/2020/NĐ-CP
  Widget _buildPreviewAndExportTab() {
    final cs = Theme.of(context).colorScheme;
    final previewText = _buildPlainTextPreview();

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final m in [
                {'id': 'VI', 'label': '🇻🇳 Tiếng Việt (NĐ 30/2020)'},
                {'id': 'VI_EN', 'label': '🇻🇳🇬🇧 Việt-Anh'},
                {'id': 'VI_DE', 'label': '🇻🇳🇩🇪 Việt-Đức'},
                {'id': 'VI_EN_DE', 'label': '🇻🇳🇬🇧🇩🇪 Việt-Anh-Đức'},
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 6, bottom: 8),
                  child: ChoiceChip(
                    label: Text(m['label']!, style: const TextStyle(fontSize: 12)),
                    selected: _docLanguageMode == m['id'],
                    side: BorderSide.none,
                    showCheckmark: false,
                    visualDensity: VisualDensity.compact,
                    onSelected: (_) => _applyDocLanguageModeTitle(m['id']!),
                  ),
                ),
            ],
          ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: () => _exportDocxAndOptionallyShare(shareImmediately: true),
              icon: const Icon(Icons.share, size: 18),
              label: Text('Chia Sẻ File .DOCX ($_docLanguageMode)'),
            ),
            FilledButton.tonalIcon(
              onPressed: () => _exportDocxAndOptionallyShare(shareImmediately: false),
              icon: const Icon(Icons.file_download_outlined, size: 18),
              label: const Text('Lưu File .DOCX Vào Máy'),
            ),
            OutlinedButton.icon(
              onPressed: _sharePlainTextMinutes,
              icon: const Icon(Icons.send_outlined, size: 18),
              label: const Text('Chia Sẻ Văn Bản (Text)'),
            ),
            OutlinedButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: previewText));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Đã sao chép toàn văn Biên bản cuộc họp vào bộ nhớ tạm.')),
                );
              },
              icon: const Icon(Icons.copy_all_outlined, size: 18),
              label: const Text('Sao chép Toàn văn'),
            ),
          ],
        ),

        if (_lastExportedDocxPath.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              'File Word vừa tự sinh: $_lastExportedDocxPath\n(Đã lưu trong thư mục /Download/AnhsTeam_BienBanHop/ của điện thoại)',
              style: TextStyle(fontSize: 12, color: cs.primary, fontWeight: FontWeight.w600),
            ),
          ),

        const SizedBox(height: 12),

        // DUY NHẤT 1 THẺ XEM TRƯỚC BIÊN BẢN HÀNH CHÍNH (SINGLE-LEVEL CARD)
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: cs.outlineVariant.withOpacity(0.6), width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ClipOval(
                    child: Image.asset(
                      'assets/logo_anhs_team.png',
                      width: 30,
                      height: 30,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Bản xem trước Biên bản ($_docLanguageMode) • Chuẩn NĐ 30/2020/NĐ-CP',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
                    ),
                  ),
                ],
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Divider(height: 1),
              ),
              SelectableText(
                previewText,
                style: const TextStyle(
                  fontSize: 13.2,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// TAB 4: QUẢN LÝ FILE TRONG MÁY & CHẠY TỰ ĐỘNG 1-CHẠM
  Widget _buildStorageArchiveTab() {
    final cs = Theme.of(context).colorScheme;
    final playingPath = (_status['currentlyPlayingPath'] ?? '').toString();

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      children: [
        FilledButton.icon(
          onPressed: _pickAndImportExistingFile,
          icon: const Icon(Icons.auto_fix_high),
          label: const Text(
            'Chọn Tệp Từ Bộ Nhớ Máy -> Tự Động Gỡ Băng & Sinh Biên Bản (.DOCX)',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 16),

        Text(
          '1. Biên bản Cuộc họp đã xuất (.DOCX) (${_exportedDocx.length})',
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5),
        ),
        const SizedBox(height: 6),
        if (_exportedDocx.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'Chưa có tệp .docx nào.',
              style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
            ),
          )
        else
          ..._exportedDocx.map((doc) {
            final path = (doc['path'] ?? '').toString();
            final name = (doc['name'] ?? '').toString();
            final dateStr = (doc['dateFormatted'] ?? '').toString();
            final sizeKB = doc['sizeKB'] ?? 1;

            return Container(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(color: cs.primary, width: 3),
                  bottom: BorderSide(color: cs.outlineVariant.withOpacity(0.45), width: 0.8),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.2),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$dateStr  •  $sizeKB KB  •  Chuẩn NĐ 30/2020/NĐ-CP',
                          style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
                    onPressed: () {
                      _channel.invokeMethod('shareFile', {
                        'path': path,
                        'mimeType':
                            'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
                      });
                    },
                    icon: const Icon(Icons.share, size: 16),
                    label: const Text('Chia sẻ'),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 19),
                    onPressed: () async {
                      await _channel.invokeMethod('deleteFile', {'path': path});
                      await _refreshFiles();
                    },
                  ),
                ],
              ),
            );
          }),

        const SizedBox(height: 20),

        Text(
          '2. Tệp Ghi âm Đã Nhập & Có Sẵn Trong Máy (${_recordings.length})',
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5),
        ),
        const SizedBox(height: 6),
        if (_recordings.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'Chưa có tệp âm thanh nào.',
              style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
            ),
          )
        else
          ..._recordings.map((rec) {
            final path = (rec['path'] ?? '').toString();
            final name = (rec['name'] ?? '').toString();
            final sourceTag = (rec['sourceTag'] ?? 'THU ÂM').toString();
            final dateStr = (rec['dateFormatted'] ?? '').toString();
            final sizeKB = rec['sizeKB'] ?? 0;
            final durSec = (rec['durationSec'] as num?)?.toInt() ?? 0;
            final sha = (rec['sha256Short'] ?? '').toString();
            final isPlaying = playingPath == path && path.isNotEmpty;

            return Container(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(
                    color: isPlaying ? Colors.green : Colors.teal,
                    width: 3,
                  ),
                  bottom: BorderSide(color: cs.outlineVariant.withOpacity(0.45), width: 0.8),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        sourceTag,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: cs.primary,
                        ),
                      ),
                      Text(
                        '$dateStr  •  ${_formatDuration(durSec)}  •  $sizeKB KB',
                        style: TextStyle(fontSize: 11.2, color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    name,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.2),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'SHA-256: $sha...',
                    style: TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  Wrap(
                    spacing: 6,
                    alignment: WrapAlignment.end,
                    children: [
                      FilledButton.tonalIcon(
                        style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
                        onPressed: () => _autoGenerateMinutesFromAudioItem(rec),
                        icon: const Icon(Icons.auto_fix_high, size: 16),
                        label: const Text('Tự Động Sinh Biên Bản'),
                      ),
                      TextButton.icon(
                        style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                        onPressed: () async {
                          if (isPlaying) {
                            await _channel.invokeMethod('stopPlayback');
                          } else {
                            await _channel.invokeMethod('playRecording', {'path': path});
                          }
                          await _refreshStatusOnly();
                        },
                        icon: Icon(
                          isPlaying ? Icons.stop_circle : Icons.play_circle_fill,
                          size: 18,
                        ),
                        label: Text(isPlaying ? 'Dừng' : 'Nghe'),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }
}

class StringBuilderPlain {
  final StringBuffer _buf = StringBuffer();
  void writeln(String s) => _buf.writeln(s);
  @override
  String toString() => _buf.toString();
}
