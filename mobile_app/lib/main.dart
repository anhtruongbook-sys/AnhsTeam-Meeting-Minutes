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
      title: "Anh's TEAM - Biên Bản Cuộc Họp",
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
  String timestamp;
  String content;

  SpeakerTurnItem({
    required this.speaker,
    required this.timestamp,
    required this.content,
  });

  Map<String, dynamic> toJson() => {
        'speaker': speaker,
        'timestamp': timestamp,
        'content': content,
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

  // Controllers cho thông tin hành chính của Biên bản cuộc họp
  final TextEditingController _govBodyCtrl = TextEditingController(text: '');
  final TextEditingController _orgNameCtrl = TextEditingController(text: "ANH'S TEAM");
  final TextEditingController _docNumCtrl = TextEditingController(text: 'Số: 01/2026/BB-AT');
  final TextEditingController _locDateCtrl =
      TextEditingController(text: 'Hà Nội, ngày 16 tháng 10 năm 2026');
  final TextEditingController _meetingTitleCtrl =
      TextEditingController(text: 'BIÊN BẢN CUỘC HỌP');
  final TextEditingController _meetingSubjectCtrl = TextEditingController(
      text: 'Về việc rà soát tiến độ công việc và phân công nhiệm vụ triển khai dự án');
  final TextEditingController _startTimeCtrl =
      TextEditingController(text: '08 giờ 30 phút ngày 16/10/2026');
  final TextEditingController _endTimeCtrl =
      TextEditingController(text: '11 giờ 00 phút cùng ngày');
  final TextEditingController _venueCtrl =
      TextEditingController(text: 'Phòng họp trung tâm (Kết hợp trực tuyến)');
  final TextEditingController _chairNameCtrl = TextEditingController(text: 'Ông Trương Đức Anh');
  final TextEditingController _chairTitleCtrl =
      TextEditingController(text: "Trưởng nhóm Anh's TEAM - Chủ trì");
  final TextEditingController _secNameCtrl = TextEditingController(text: 'Thư ký chuyên trách');
  final TextEditingController _secTitleCtrl = TextEditingController(text: 'Thư ký cuộc họp');
  final TextEditingController _attendeesCtrl = TextEditingController(
      text: 'Các thành viên nhóm dự án và đại diện các bộ phận chuyên môn');

  // Controllers cho việc thêm nhanh lượt phát biểu tại Tab 1
  final TextEditingController _liveSpeakerCtrl =
      TextEditingController(text: 'Ông Trương Đức Anh (Chủ trì)');
  final TextEditingController _liveContentCtrl = TextEditingController();

  // Controllers cho việc thêm Kết luận và Nhiệm vụ tại Tab 2
  final TextEditingController _newConclusionCtrl = TextEditingController();
  final TextEditingController _newTaskNameCtrl = TextEditingController();
  final TextEditingController _newTaskAssigneeCtrl = TextEditingController();
  final TextEditingController _newTaskCoordCtrl = TextEditingController();
  final TextEditingController _newTaskDeadlineCtrl = TextEditingController();

  String _lastSyncedSpeech = '';
  String _lastExportedDocxPath = '';

  final List<SpeakerTurnItem> _speakerTurns = [
    SpeakerTurnItem(
      speaker: 'Ông Trương Đức Anh (Chủ trì)',
      timestamp: '00:00:15',
      content:
          'Tuyên bố lý do cuộc họp, quán triệt mục tiêu rà soát tiến độ thực hiện các hạng mục công việc trọng tâm và yêu cầu các bộ phận báo cáo số liệu thực tế.',
    ),
    SpeakerTurnItem(
      speaker: 'Đại diện Bộ phận Kỹ thuật',
      timestamp: '00:05:40',
      content:
          'Báo cáo kết quả hoàn thành giai đoạn 1, đề xuất phương án tối ưu hóa quy trình phối hợp dữ liệu và thống nhất lịch kiểm tra nghiệm thu nội bộ.',
    ),
  ];

  final List<String> _conclusions = [
    'Thống nhất thông qua báo cáo tiến độ của Bộ phận Kỹ thuật và phương án điều phối kế hoạch giai đoạn tiếp theo.',
    'Yêu cầu các thành viên phụ trách hoàn thành đúng thời hạn trong bảng phân công nhiệm vụ và báo cáo kết quả trước kỳ họp giao ban tuần tới.',
  ];

  final List<ActionTaskItem> _actionItems = [
    ActionTaskItem(
      task: 'Hoàn thiện hồ sơ kỹ thuật và danh mục kiểm tra chất lượng',
      assignee: 'Bộ phận Kỹ thuật',
      coordinator: 'Bộ phận Quản lý dự án',
      deadline: '22/10/2026',
    ),
    ActionTaskItem(
      task: 'Tổng hợp báo cáo tiến độ và gửi biên bản cuộc họp cho các bên liên quan',
      assignee: 'Thư ký cuộc họp',
      coordinator: 'Văn phòng nhóm',
      deadline: '17/10/2026',
    ),
  ];

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
        final finalSpeech = (map['latestFinalSpeech'] ?? '').toString().trim();
        if (finalSpeech.isNotEmpty && finalSpeech != _lastSyncedSpeech) {
          _lastSyncedSpeech = finalSpeech;
          _liveContentCtrl.text = finalSpeech;
        }
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

  Future<void> _toggleMeetingRecording() async {
    final isRec = _status['isRecording'] == true;
    if (isRec) {
      await _channel.invokeMethod('stopMeetingRecording');
      await _refreshAll();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã dừng thu âm và lưu tệp WAV 16kHz kèm mã SHA-256.')),
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
        await _channel.invokeMethod('startVoiceDictation');
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
    final ts = _status['isRecording'] == true
        ? _formatDuration(elapsedSec)
        : TimeOfDay.now().format(context);

    setState(() {
      _speakerTurns.add(
        SpeakerTurnItem(
          speaker: _liveSpeakerCtrl.text.trim().isEmpty
              ? 'Đại biểu phát biểu'
              : _liveSpeakerCtrl.text.trim(),
          timestamp: ts,
          content: text,
        ),
      );
      _liveContentCtrl.clear();
      _lastSyncedSpeech = '';
    });
    _channel.invokeMethod('clearSpeechBuffer');
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Đã thêm lượt phát biểu vào Biên bản cuộc họp.')),
    );
  }

  Map<String, dynamic> _buildMinutesJsonMap() {
    return {
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
    sb.writeln('2. Địa điểm / Hình thức họp: ${_venueCtrl.text.trim()}.');
    sb.writeln('3. Thành phần tham dự:');
    sb.writeln('- Chủ trì cuộc họp: ${_chairNameCtrl.text.trim()} (${_chairTitleCtrl.text.trim()}).');
    sb.writeln('- Thư ký cuộc họp: ${_secNameCtrl.text.trim()} (${_secTitleCtrl.text.trim()}).');
    if (_attendeesCtrl.text.trim().isNotEmpty) {
      sb.writeln('- Thành viên tham dự: ${_attendeesCtrl.text.trim()}.');
    }
    sb.writeln('');
    sb.writeln('II. NỘI DUNG DIỄN BIẾN CUỘC HỌP');
    for (int i = 0; i < _speakerTurns.length; i++) {
      final t = _speakerTurns[i];
      sb.writeln('${i + 1}. Ý kiến phát biểu của ${t.speaker} (Mốc: ${t.timestamp}):');
      for (final line in t.content.split('\n')) {
        if (line.trim().isNotEmpty) {
          sb.writeln('- ${line.trim()}');
        }
      }
    }
    sb.writeln('');
    sb.writeln('III. KẾT LUẬN CUỘC HỌP VÀ PHÂN CÔNG NHIỆM VỤ');
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

  @override
  Widget build(BuildContext context) {
    final bool micGranted = _status['micPermissionGranted'] == true;
    final bool isRecording = _status['isRecording'] == true;
    final int elapsedSec = (_status['elapsedSeconds'] as num?)?.toInt() ?? 0;
    final int peakAmp = (_status['peakAmplitude'] as num?)?.toInt() ?? 0;
    final double roomGain = (_status['roomGainBoost'] as num?)?.toDouble() ?? 2.5;
    final bool isListeningSpeech = _status['isListeningSpeech'] == true;
    final String partialSpeech = (_status['latestPartialSpeech'] ?? '').toString();

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
                      "Anh's TEAM • Biên Bản Họp",
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      'Thu âm DSP • Gỡ băng • Xuất Word NĐ 30/2020',
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
              tooltip: 'Làm mới dữ liệu',
              icon: const Icon(Icons.refresh),
              onPressed: _refreshAll,
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
              Tab(icon: Icon(Icons.mic_external_on, size: 19), text: 'Thu Âm'),
              Tab(icon: Icon(Icons.edit_note, size: 19), text: 'Soạn Họp'),
              Tab(icon: Icon(Icons.description_outlined, size: 19), text: 'Xuất Word'),
              Tab(icon: Icon(Icons.folder_copy_outlined, size: 19), text: 'Lưu Trữ'),
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
            ),
            _buildMinutesEditorTab(),
            _buildPreviewAndExportTab(),
            _buildStorageArchiveTab(),
          ],
        ),
      ),
    );
  }

  /// TAB 1: THU ÂM PHÒNG HỌP & GỠ BĂNG TRỰC TIẾP (TUÂN THỦ RULE 14 - SINGLE-LEVEL CARD)
  Widget _buildRecordAndTranscribeTab({
    required bool micGranted,
    required bool isRecording,
    required int elapsedSec,
    required int peakAmp,
    required double roomGain,
    required bool isListeningSpeech,
    required String partialSpeech,
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
              color: Colors.amber.withOpacity(0.12),
              border: Border(
                left: BorderSide(color: Colors.amber.shade700, width: 3.5),
              ),
            ),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Cần cấp quyền Microphone để thu âm phòng họp và nhận diện giọng nói tiếng Việt.',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.tonalIcon(
                  onPressed: () async {
                    await _channel.invokeMethod('requestPermissions');
                    await _refreshStatusOnly();
                  },
                  icon: const Icon(Icons.mic, size: 16),
                  label: const Text('Cấp quyền'),
                ),
              ],
            ),
          ),

        // DUY NHẤT 1 THẺ ĐƠN CẤP (SINGLE-LEVEL CARD) CHO BỘ ĐIỀU KHIỂN THU ÂM & GỠ BĂNG
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
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(
                        isRecording ? Icons.fiber_manual_record : Icons.podcasts,
                        color: isRecording ? Colors.redAccent : cs.primary,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        isRecording
                            ? 'ĐANG THU ÂM: ${_formatDuration(elapsedSec)}'
                            : 'Bàn điều khiển Thu âm Phòng họp',
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                      ),
                    ],
                  ),
                  Text(
                    '16kHz PCM • DSP x${roomGain.toStringAsFixed(1)}',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: cs.primary,
                    ),
                  ),
                ],
              ),
              if (isRecording) ...[
                const SizedBox(height: 10),
                LinearProgressIndicator(
                  value: (peakAmp / 32767.0).clamp(0.03, 1.0),
                  minHeight: 6,
                  color: Colors.redAccent,
                ),
                const SizedBox(height: 4),
                Text(
                  'Cường độ âm thanh phòng họp: $peakAmp / 32767',
                  style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant),
                ),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Độ nhạy thu xa (Far-Field Gain): x${roomGain.toStringAsFixed(1)}',
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                    ),
                  ),
                  SizedBox(
                    width: 150,
                    child: Slider(
                      value: roomGain.clamp(1.0, 6.0),
                      min: 1.0,
                      max: 6.0,
                      divisions: 10,
                      label: 'x${roomGain.toStringAsFixed(1)}',
                      onChanged: (val) async {
                        await _channel.invokeMethod('updateRoomGain', {'roomGainBoost': val});
                        await _refreshStatusOnly();
                      },
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: isRecording ? Colors.red : null,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                      onPressed: _toggleMeetingRecording,
                      icon: Icon(isRecording ? Icons.stop_circle : Icons.fiber_manual_record),
                      label: Text(
                        isRecording ? 'Dừng & Lưu File WAV' : 'Bắt Đầu Thu Âm Cuộc Họp',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),

              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Divider(height: 1),
              ),

              // KHU VỰC GỠ BĂNG TIẾNG VIỆT & GHI NHẬN LƯỢT PHÁT BIỂU (PHẲNG HOÀN TOÀN)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Ghi nhận Lượt phát biểu vào Biên bản',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                  ),
                  TextButton.icon(
                    style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                    onPressed: _toggleVoiceDictation,
                    icon: Icon(
                      isListeningSpeech ? Icons.mic_off : Icons.record_voice_over,
                      size: 17,
                      color: isListeningSpeech ? Colors.redAccent : cs.primary,
                    ),
                    label: Text(
                      isListeningSpeech ? 'Đang nghe (Dừng)' : 'Đọc Giọng Nói (vi-VN)',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: isListeningSpeech ? Colors.redAccent : cs.primary,
                      ),
                    ),
                  ),
                ],
              ),
              if (partialSpeech.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    'Đang nhận diện: "$partialSpeech..."',
                    style: const TextStyle(
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                      color: Colors.amber,
                    ),
                  ),
                ),

              // Chọn nhanh vai trò người phát biểu bằng Chip phẳng (side: BorderSide.none)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final preset in [
                      '${_chairNameCtrl.text} (Chủ trì)',
                      '${_secNameCtrl.text} (Thư ký)',
                      'Đại diện Bộ phận Kỹ thuật',
                      'Đại diện Đơn vị Tư vấn',
                      'Đại biểu dự họp',
                    ])
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ActionChip(
                          label: Text(preset, style: const TextStyle(fontSize: 11.5)),
                          side: BorderSide.none,
                          visualDensity: VisualDensity.compact,
                          onPressed: () {
                            setState(() {
                              _liveSpeakerCtrl.text = preset;
                            });
                          },
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              TextField(
                controller: _liveSpeakerCtrl,
                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                decoration: const InputDecoration(
                  labelText: 'Người đang phát biểu (Họ tên & Chức vụ)',
                  isDense: true,
                  border: UnderlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _liveContentCtrl,
                maxLines: 3,
                style: const TextStyle(fontSize: 13.5),
                decoration: const InputDecoration(
                  labelText: 'Nội dung phát biểu (Nhập tay hoặc bấm Đọc Giọng Nói ở trên)',
                  hintText: 'Nhập các ý chính đại biểu vừa trình bày...',
                  isDense: true,
                  border: UnderlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.tonalIcon(
                  onPressed: _addLiveTurnToMinutes,
                  icon: const Icon(Icons.playlist_add_check, size: 18),
                  label: const Text('Đưa Lượt Phát Biểu Này Vào Biên Bản'),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // DANH SÁCH LƯỢT PHÁT BIỂU ĐÃ GHI NHẬN TRONG CUỘC HỌP HIỆN TẠI (PHẲNG HÓA 100%)
        Text(
          'Diễn biến cuộc họp đã ghi nhận (${_speakerTurns.length} lượt phát biểu)',
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
        ),
        const SizedBox(height: 8),
        ..._speakerTurns.asMap().entries.map((entry) {
          final idx = entry.key;
          final turn = entry.value;
          return Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(color: cs.primary, width: 3),
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
                        '${idx + 1}. ${turn.speaker}',
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
              ],
            ),
          );
        }),
      ],
    );
  }

  /// TAB 2: SOẠN THẢO CẤU TRÚC BIÊN BẢN CUỘC HỌP (PHẲNG HÓA 100% - RULE 14)
  Widget _buildMinutesEditorTab() {
    final cs = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      children: [
        // 1. THÔNG TIN HÀNH CHÍNH & THÀNH PHẦN THAM DỰ
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
                        labelText: 'Họ tên Chủ trì cuộc họp',
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
                        labelText: 'Họ tên Thư ký cuộc họp',
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
                  labelText: 'Thành viên tham dự (cách nhau bởi dấu chấm phẩy hoặc xuống dòng)',
                  isDense: true,
                  border: UnderlineInputBorder(),
                ),
              ),

              const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Divider(height: 1),
              ),

              // 2. KẾT LUẬN CỦA CHỦ TRÌ CUỘC HỌP
              const Text(
                'III. Kết luận của Chủ trì cuộc họp',
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
                        hintText: 'Nhập thêm ý kết luận mới của Chủ trì...',
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

              // 3. BẢNG PHÂN CÔNG NHIỆM VỤ (ACTION ITEMS)
              const Text(
                'Bảng phân công nhiệm vụ (Action Items)',
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
              const SizedBox(height: 8),
              TextField(
                controller: _newTaskNameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Nội dung công việc cần giao',
                  isDense: true,
                  border: UnderlineInputBorder(),
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _newTaskAssigneeCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Đơn vị/Cá nhân chủ trì',
                        isDense: true,
                        border: UnderlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _newTaskCoordCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Đơn vị phối hợp',
                        isDense: true,
                        border: UnderlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 95,
                    child: TextField(
                      controller: _newTaskDeadlineCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Thời hạn',
                        isDense: true,
                        border: UnderlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.tonalIcon(
                  onPressed: () {
                    final t = _newTaskNameCtrl.text.trim();
                    if (t.isNotEmpty) {
                      setState(() {
                        _actionItems.add(
                          ActionTaskItem(
                            task: t,
                            assignee: _newTaskAssigneeCtrl.text.trim().isEmpty
                                ? 'Chuyên viên phụ trách'
                                : _newTaskAssigneeCtrl.text.trim(),
                            coordinator: _newTaskCoordCtrl.text.trim().isEmpty
                                ? 'Các bộ phận'
                                : _newTaskCoordCtrl.text.trim(),
                            deadline: _newTaskDeadlineCtrl.text.trim().isEmpty
                                ? 'Trong tuần'
                                : _newTaskDeadlineCtrl.text.trim(),
                          ),
                        );
                        _newTaskNameCtrl.clear();
                        _newTaskAssigneeCtrl.clear();
                        _newTaskCoordCtrl.clear();
                        _newTaskDeadlineCtrl.clear();
                      });
                    }
                  },
                  icon: const Icon(Icons.add_task, size: 18),
                  label: const Text('Thêm Nhiệm Vụ Vào Bảng'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// TAB 3: XEM TRƯỚC & XUẤT BẢN WORD (.DOCX) CHUẨN NGHỊ ĐỊNH 30/2020/NĐ-CP
  Widget _buildPreviewAndExportTab() {
    final cs = Theme.of(context).colorScheme;
    final previewText = _buildPlainTextPreview();

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      children: [
        // Thanh công cụ xuất file Word & Chia sẻ
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: () => _exportDocxAndOptionallyShare(shareImmediately: false),
              icon: const Icon(Icons.file_download_outlined, size: 18),
              label: const Text('Xuất File .DOCX (Chuẩn NĐ 30)'),
            ),
            FilledButton.tonalIcon(
              onPressed: () => _exportDocxAndOptionallyShare(shareImmediately: true),
              icon: const Icon(Icons.share_outlined, size: 18),
              label: const Text('Xuất & Gửi Zalo / Email'),
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
              'File vừa xuất: $_lastExportedDocxPath\n(Đồng thời đã lưu bản sao trong thư mục /Download/AnhsTeam_BienBanHop/ của điện thoại)',
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
                  const Expanded(
                    child: Text(
                      'Bản xem trước Thể thức Nghị định 30/2020/NĐ-CP (Times New Roman • Khổ A4)',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
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

  /// TAB 4: KHO LƯU TRỮ BIÊN BẢN (.DOCX) VÀ FILE GHI ÂM (.WAV)
  Widget _buildStorageArchiveTab() {
    final cs = Theme.of(context).colorScheme;
    final playingPath = (_status['currentlyPlayingPath'] ?? '').toString();

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      children: [
        Text(
          '1. Biên bản Cuộc họp đã xuất (.DOCX) (${_exportedDocx.length})',
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5),
        ),
        const SizedBox(height: 6),
        if (_exportedDocx.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Text(
              'Chưa có tệp .docx nào. Hãy sang tab "Xuất Word" và bấm "Xuất File .DOCX (Chuẩn NĐ 30)".',
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
                  TextButton.icon(
                    onPressed: () {
                      _channel.invokeMethod('shareFile', {
                        'path': path,
                        'mimeType':
                            'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
                      });
                    },
                    icon: const Icon(Icons.share, size: 17),
                    label: const Text('Gửi'),
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
          '2. Tệp Ghi âm Phòng họp (.WAV 16kHz PCM) (${_recordings.length})',
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5),
        ),
        const SizedBox(height: 6),
        if (_recordings.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Text(
              'Chưa có tệp ghi âm .wav nào.',
              style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
            ),
          )
        else
          ..._recordings.map((rec) {
            final path = (rec['path'] ?? '').toString();
            final name = (rec['name'] ?? '').toString();
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
                  Text(
                    name,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.2),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$dateStr  •  Thời lượng: ${_formatDuration(durSec)}  •  $sizeKB KB  •  SHA256: $sha...',
                    style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton.icon(
                        onPressed: () async {
                          if (isPlaying) {
                            await _channel.invokeMethod('stopPlayback');
                          } else {
                            await _channel.invokeMethod('playRecording', {'path': path});
                          }
                          await _refreshStatusOnly();
                        },
                        icon: Icon(isPlaying ? Icons.stop_circle : Icons.play_circle_fill, size: 18),
                        label: Text(isPlaying ? 'Dừng' : 'Nghe lại'),
                      ),
                      TextButton.icon(
                        onPressed: () {
                          _channel.invokeMethod('shareFile', {
                            'path': path,
                            'mimeType': 'audio/wav',
                          });
                        },
                        icon: const Icon(Icons.share_outlined, size: 17),
                        label: const Text('Chia sẻ WAV'),
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
