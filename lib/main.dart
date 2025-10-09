import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_session/audio_session.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:audiotags/audiotags.dart';
import 'dart:io';
import 'dart:math';
import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  await Hive.openBox('songCache');
  await PlaylistManager.initialize();
  await SettingsManager.initialize();
  runApp(MusicPlayerApp());
}

// Song model for caching
class CachedSong {
  final String path;
  final String title;
  final String artist;
  final int duration;
  final int dateModified;

  CachedSong({
    required this.path,
    required this.title,
    required this.artist,
    required this.duration,
    required this.dateModified,
  });

  Map<String, dynamic> toJson() => {
    'path': path,
    'title': title,
    'artist': artist,
    'duration': duration,
    'dateModified': dateModified,
  };

  factory CachedSong.fromJson(Map<String, dynamic> json) => CachedSong(
    path: json['path'] ?? '',
    title: json['title'] ?? '',
    artist: json['artist'] ?? 'Unknown Artist',
    duration: json['duration'] ?? 0,
    dateModified: json['dateModified'] ?? 0,
  );
}

// Playlist model
class Playlist {
  final String id;
  final String name;
  final List<String> songPaths;
  final DateTime createdAt;
  final DateTime updatedAt;

  Playlist({
    required this.id,
    required this.name,
    required this.songPaths,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'songPaths': songPaths,
    'createdAt': createdAt.millisecondsSinceEpoch,
    'updatedAt': updatedAt.millisecondsSinceEpoch,
  };

  factory Playlist.fromJson(Map<String, dynamic> json) => Playlist(
    id: json['id'] ?? '',
    name: json['name'] ?? '',
    songPaths: List<String>.from(json['songPaths'] ?? []),
    createdAt: DateTime.fromMillisecondsSinceEpoch(json['createdAt'] ?? 0),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(json['updatedAt'] ?? 0),
  );

  Playlist copyWith({
    String? id,
    String? name,
    List<String>? songPaths,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Playlist(
      id: id ?? this.id,
      name: name ?? this.name,
      songPaths: songPaths ?? this.songPaths,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

// Playlist manager for storage and operations
class PlaylistManager {
  static const String _playlistsKey = 'user_playlists';
  static late SharedPreferences _prefs;

  static Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();
  }

  static Future<List<Playlist>> getPlaylists() async {
    try {
      final playlistsJson = _prefs.getString(_playlistsKey);
      if (playlistsJson == null) return [];

      final List<dynamic> playlistsList = jsonDecode(playlistsJson);
      return playlistsList.map((json) => Playlist.fromJson(json)).toList();
    } catch (e) {
      debugPrint('Error loading playlists: $e');
      return [];
    }
  }

  static Future<void> savePlaylists(List<Playlist> playlists) async {
    try {
      final playlistsJson = playlists.map((playlist) => playlist.toJson()).toList();
      await _prefs.setString(_playlistsKey, jsonEncode(playlistsJson));
    } catch (e) {
      debugPrint('Error saving playlists: $e');
    }
  }

  static Future<Playlist> createPlaylist(String name) async {
    final playlists = await getPlaylists();
    final newPlaylist = Playlist(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      songPaths: [],
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    playlists.add(newPlaylist);
    await savePlaylists(playlists);
    return newPlaylist;
  }

  static Future<void> deletePlaylist(String playlistId) async {
    final playlists = await getPlaylists();
    playlists.removeWhere((playlist) => playlist.id == playlistId);
    await savePlaylists(playlists);
  }

  static Future<void> addSongToPlaylist(String playlistId, String songPath) async {
    final playlists = await getPlaylists();
    final playlistIndex = playlists.indexWhere((p) => p.id == playlistId);

    if (playlistIndex != -1) {
      final playlist = playlists[playlistIndex];
      if (!playlist.songPaths.contains(songPath)) {
        final updatedPlaylist = playlist.copyWith(
          songPaths: [...playlist.songPaths, songPath],
          updatedAt: DateTime.now(),
        );
        playlists[playlistIndex] = updatedPlaylist;
        await savePlaylists(playlists);
      }
    }
  }

  static Future<void> removeSongFromPlaylist(String playlistId, String songPath) async {
    final playlists = await getPlaylists();
    final playlistIndex = playlists.indexWhere((p) => p.id == playlistId);

    if (playlistIndex != -1) {
      final playlist = playlists[playlistIndex];
      final updatedSongPaths = List<String>.from(playlist.songPaths);
      updatedSongPaths.remove(songPath);

      final updatedPlaylist = playlist.copyWith(
        songPaths: updatedSongPaths,
        updatedAt: DateTime.now(),
      );
      playlists[playlistIndex] = updatedPlaylist;
      await savePlaylists(playlists);
    }
  }

  static Future<void> renamePlaylist(String playlistId, String newName) async {
    final playlists = await getPlaylists();
    final playlistIndex = playlists.indexWhere((p) => p.id == playlistId);

    if (playlistIndex != -1) {
      final playlist = playlists[playlistIndex];
      final updatedPlaylist = playlist.copyWith(
        name: newName,
        updatedAt: DateTime.now(),
      );
      playlists[playlistIndex] = updatedPlaylist;
      await savePlaylists(playlists);
    }
  }
}

// Fast song cache manager
class SongCacheManager {
  static final Box _cacheBox = Hive.box('songCache');
  static const String _songListKey = 'cached_songs';
  static const String _lastScanKey = 'last_scan_time';

  static Future<List<CachedSong>> getCachedSongs() async {
    try {
      final songsData = _cacheBox.get(_songListKey);
      if (songsData == null) return [];

      final List<dynamic> songsList = jsonDecode(songsData);
      return songsList.map((json) => CachedSong.fromJson(json)).toList();
    } catch (e) {
      debugPrint('Error loading cached songs: $e');
      return [];
    }
  }

  static Future<void> cacheSongs(List<CachedSong> songs) async {
    try {
      final songsJson = songs.map((song) => song.toJson()).toList();
      await _cacheBox.put(_songListKey, jsonEncode(songsJson));
      await _cacheBox.put(_lastScanKey, DateTime.now().millisecondsSinceEpoch);
    } catch (e) {
      debugPrint('Error caching songs: $e');
    }
  }

  static bool shouldRefreshCache() {
    final lastScan = _cacheBox.get(_lastScanKey, defaultValue: 0);
    final now = DateTime.now().millisecondsSinceEpoch;
    final dayInMs = 24 * 60 * 60 * 1000;
    return (now - lastScan) > dayInMs; // Refresh if older than 1 day
  }

  static Future<void> clearCache() async {
    await _cacheBox.clear();
  }
}

// Isolate function for background song scanning
Future<List<CachedSong>> _scanSongsInBackground(List<String> directories) async {
  final List<CachedSong> songs = [];
  final audioExtensions = ['.mp3', '.m4a', '.wav', '.flac', '.aac'];

  for (String dirPath in directories) {
    final dir = Directory(dirPath);
    if (!await dir.exists()) continue;

    await for (FileSystemEntity entity in dir.list(recursive: true)) {
      if (entity is File) {
        final path = entity.path;
        if (audioExtensions.any((ext) => path.toLowerCase().endsWith(ext))) {
          try {
            final stat = await entity.stat();
            final fileName = path.split('/').last;
            final title = fileName.replaceAll(RegExp(r'\.[^.]*$'), '');

            songs.add(CachedSong(
              path: path,
              title: title,
              artist: 'Unknown Artist',
              duration: 0, // Will be loaded lazily
              dateModified: stat.modified.millisecondsSinceEpoch,
            ));
          } catch (e) {
            debugPrint('Error processing file $path: $e');
          }
        }
      }
    }
  }

  return songs;
}

// Settings Manager - Handles app settings
class SettingsManager {
  static final SettingsManager _instance = SettingsManager._internal();
  factory SettingsManager() => _instance;
  SettingsManager._internal();

  bool isDarkMode = false;
  Color themeColor = Color(0xFF10B981);
  List<String> musicFolders = [];
  double equalizerBass = 0.0;
  double equalizerTreble = 0.0;
  double volumeBoost = 0.0;

  static late SharedPreferences _prefs;

  static Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();
    final instance = SettingsManager();
    await instance._loadSettings();
  }

  Future<void> _loadSettings() async {
    isDarkMode = _prefs.getBool('isDarkMode') ?? false;
    final colorValue = _prefs.getInt('themeColor') ?? 0xFF10B981;
    themeColor = Color(colorValue);
    musicFolders = _prefs.getStringList('musicFolders') ?? [];
    equalizerBass = _prefs.getDouble('equalizerBass') ?? 0.0;
    equalizerTreble = _prefs.getDouble('equalizerTreble') ?? 0.0;
    volumeBoost = _prefs.getDouble('volumeBoost') ?? 0.0;
  }

  Future<void> _saveSettings() async {
    await _prefs.setBool('isDarkMode', isDarkMode);
    await _prefs.setInt('themeColor', themeColor.value);
    await _prefs.setStringList('musicFolders', musicFolders);
    await _prefs.setDouble('equalizerBass', equalizerBass);
    await _prefs.setDouble('equalizerTreble', equalizerTreble);
    await _prefs.setDouble('volumeBoost', volumeBoost);
  }

  // Theme colors available
  final List<Color> availableColors = [
    Color(0xFF10B981), // Green (default)
    Color(0xFF3B82F6), // Blue
    Color(0xFFEF4444), // Red
    Color(0xFF8B5CF6), // Purple
    Color(0xFFF59E0B), // Orange
    Color(0xFFEC4899), // Pink
  ];

  Future<void> toggleDarkMode() async {
    isDarkMode = !isDarkMode;
    await _saveSettings();
  }

  Future<void> setThemeColor(Color color) async {
    themeColor = color;
    await _saveSettings();
  }

  Future<void> addMusicFolder(String path) async {
    if (!musicFolders.contains(path)) {
      musicFolders.add(path);
      await _saveSettings();
    }
  }

  Future<void> removeMusicFolder(String path) async {
    musicFolders.remove(path);
    await _saveSettings();
  }

  Future<void> setEqualizerBass(double value) async {
    equalizerBass = value;
    await _saveSettings();
  }

  Future<void> setEqualizerTreble(double value) async {
    equalizerTreble = value;
    await _saveSettings();
  }

  Future<void> setVolumeBoost(double value) async {
    volumeBoost = value;
    await _saveSettings();
  }

  ThemeData getThemeData() {
    return ThemeData(
      primaryColor: themeColor,
      scaffoldBackgroundColor: isDarkMode ? Colors.grey[900] : Colors.white,
      fontFamily: 'SF Pro',
      brightness: isDarkMode ? Brightness.dark : Brightness.light,
      appBarTheme: AppBarTheme(
        backgroundColor: isDarkMode ? Colors.grey[850] : Colors.white,
        foregroundColor: isDarkMode ? Colors.white : Colors.black,
      ),
      textTheme: TextTheme(
        bodyLarge: TextStyle(color: isDarkMode ? Colors.white : Colors.black),
        bodyMedium: TextStyle(color: isDarkMode ? Colors.white : Colors.black),
      ),
    );
  }
}

// Audio Manager - Handles all audio playback functionality
class AudioManager {
  static final AudioManager _instance = AudioManager._internal();
  factory AudioManager() => _instance;
  AudioManager._internal();

  final AudioPlayer _audioPlayer = AudioPlayer();

  String? currentSong;
  String? currentArtist;
  String? currentFilePath;
  bool isPlaying = false;
  bool isShuffleOn = false;
  bool isRepeatOn = false;
  LoopMode loopMode = LoopMode.off;
  Duration duration = Duration.zero;
  Duration position = Duration.zero;
  List<String> recentlyPlayedPaths = [];
  List<String> favoritePaths = [];

  // Playlist management for auto-play
  List<String> currentPlaylist = [];
  int currentIndex = 0;
  Function(int)? onPlayNext;
  Function(int)? onPlayPrevious;

  // Audio effects
  double bassLevel = 0.0;
  double trebleLevel = 0.0;
  double volumeBoostLevel = 1.0;

  AudioPlayer get player => _audioPlayer;

  Future<void> init() async {
    // Initialize audio session for background playback
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());

    _audioPlayer.durationStream.listen((d) => duration = d ?? Duration.zero);
    _audioPlayer.positionStream.listen((p) => position = p);
    _audioPlayer.playerStateStream.listen((state) {
      isPlaying = state.playing;

      // Auto-play next song when current song ends
      if (state.processingState == ProcessingState.completed) {
        _playNextSong();
      }
    });
    await loadSavedData();
  }

  void setPlaylist(List<String> playlist, int index) {
    currentPlaylist = playlist;
    currentIndex = index;
  }

  Future<void> _playNextSong() async {
    if (currentPlaylist.isEmpty) return;

    if (loopMode == LoopMode.one) {
      // Repeat current song
      await _audioPlayer.seek(Duration.zero);
      await _audioPlayer.play();
      return;
    }

    // Move to next song
    if (isShuffleOn) {
      // Random next song
      if (currentPlaylist.length > 1) {
        int nextIndex;
        do {
          nextIndex = Random().nextInt(currentPlaylist.length);
        } while (nextIndex == currentIndex);
        currentIndex = nextIndex;
      }
    } else {
      // Sequential next song
      currentIndex++;
      if (currentIndex >= currentPlaylist.length) {
        if (isRepeatOn) {
          currentIndex = 0; // Loop back to start
        } else {
          return; // End of playlist
        }
      }
    }

    // Play the next song
    final nextSongPath = currentPlaylist[currentIndex];

    // Try to get metadata for the next song (simplified approach)
    final fileName = nextSongPath.split('/').last.replaceAll(RegExp(r'\.[^.]*$'), '');
    await playFromFile(nextSongPath, title: fileName, artist: 'Unknown Artist');
    onPlayNext?.call(currentIndex);
  }

  Future<void> playFromFile(String filePath, {String? title, String? artist}) async {
    try {
      currentFilePath = filePath;

      // Extract filename if title not provided
      final fileName = title ?? filePath.split('/').last.replaceAll(RegExp(r'\.[^.]*$'), '');
      final artistName = artist ?? 'Unknown Artist';

      // Set the audio source directly
      await _audioPlayer.setFilePath(filePath);
      await _audioPlayer.play();
      await _addToRecentlyPlayed(filePath);

      // Update current song info
      currentSong = fileName;
      currentArtist = artistName;
    } catch (e) {
      print('Error playing file: $e');
    }
  }

  // Legacy method for backward compatibility
  Future<void> playFromFileSimple(String filePath) async {
    await playFromFile(filePath);
  }

  Future<void> _addToRecentlyPlayed(String filePath) async {
    recentlyPlayedPaths.remove(filePath);
    recentlyPlayedPaths.insert(0, filePath);
    if (recentlyPlayedPaths.length > 10) {
      recentlyPlayedPaths = recentlyPlayedPaths.take(10).toList();
    }
    await _saveRecentlyPlayed();
  }

  Future<void> toggleFavorite(String filePath) async {
    if (favoritePaths.contains(filePath)) {
      favoritePaths.remove(filePath);
    } else {
      favoritePaths.add(filePath);
    }
    await _saveFavorites();
  }

  bool isFavorite(String filePath) {
    return favoritePaths.contains(filePath);
  }

  Future<void> _saveRecentlyPlayed() async {
    // For now, just keep in memory
  }

  Future<void> _saveFavorites() async {
    // For now, just keep in memory
  }

  Future<void> loadSavedData() async {
    // For now, data is kept in memory only
  }

  Future<void> play() async => await _audioPlayer.play();
  Future<void> pause() async => await _audioPlayer.pause();
  Future<void> stop() async => await _audioPlayer.stop();
  
  Future<void> seek(Duration position) async {
    await _audioPlayer.seek(position);
  }

  void toggleShuffle() {
    isShuffleOn = !isShuffleOn;
  }

  void toggleRepeat() {
    isRepeatOn = !isRepeatOn;
    if (isRepeatOn) {
      loopMode = LoopMode.one;
      _audioPlayer.setLoopMode(loopMode);
    } else {
      loopMode = LoopMode.off;
      _audioPlayer.setLoopMode(loopMode);
    }
  }

  void setLoopMode(LoopMode mode) {
    loopMode = mode;
    _audioPlayer.setLoopMode(mode);
    if (mode == LoopMode.one) {
      isRepeatOn = true;
    } else {
      isRepeatOn = false;
    }
  }

  void setBassLevel(double level) {
    bassLevel = level;
    // Apply bass boost (simplified implementation)
    _audioPlayer.setVolume((volumeBoostLevel * (1.0 + level / 10.0)).clamp(0.0, 2.0));
  }

  void setTrebleLevel(double level) {
    trebleLevel = level;
    // Apply treble boost (simplified implementation)
    // In a real app, you'd use platform-specific audio processing
  }

  void setVolumeBoost(double level) {
    volumeBoostLevel = level;
    _audioPlayer.setVolume(level.clamp(0.0, 2.0));
  }

  bool isCurrentlyPlaying(String filePath) {
    return isPlaying && currentFilePath == filePath;
  }

  void dispose() {
    _audioPlayer.dispose();
  }
}

class MusicPlayerApp extends StatefulWidget {
  @override
  _MusicPlayerAppState createState() => _MusicPlayerAppState();
}

class _MusicPlayerAppState extends State<MusicPlayerApp> {
  final AudioManager _audioManager = AudioManager();
  final SettingsManager _settingsManager = SettingsManager();

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    await _audioManager.init();
    await _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    if (Platform.isAndroid) {
      await [
        Permission.storage,
        Permission.manageExternalStorage,
      ].request();
    }
  }

  @override
  void dispose() {
    _audioManager.dispose();
    super.dispose();
  }

  void _refreshTheme() {
    setState(() {
      // This will rebuild the MaterialApp with new theme
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Music Player',
      theme: _settingsManager.getThemeData(),
      home: MainScreen(onThemeChanged: _refreshTheme),
      debugShowCheckedModeBanner: false,
    );
  }
}

class MainScreen extends StatefulWidget {
  final VoidCallback? onThemeChanged;

  MainScreen({this.onThemeChanged});

  @override
  _MainScreenState createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  final SettingsManager _settingsManager = SettingsManager();

  late final List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    _screens = [
      LibraryScreen(),
      SearchScreen(),
      PlaylistScreen(),
      SettingsScreen(onThemeChanged: _onThemeChanged),
    ];
  }

  void _onThemeChanged() {
    setState(() {
      // This will rebuild the MainScreen with new theme colors
    });
    widget.onThemeChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        type: BottomNavigationBarType.fixed,
        selectedItemColor: _settingsManager.themeColor,
        unselectedItemColor: Colors.grey,
        items: [
          BottomNavigationBarItem(icon: Icon(Icons.library_music), label: 'Library'),
          BottomNavigationBarItem(icon: Icon(Icons.search), label: 'Search'),
          BottomNavigationBarItem(icon: Icon(Icons.playlist_play), label: 'Playlists'),
          BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }
}

class LibraryScreen extends StatefulWidget {
  @override
  _LibraryScreenState createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final AudioManager _audioManager = AudioManager();
  final SettingsManager _settingsManager = SettingsManager();
  List<CachedSong> musicFiles = [];
  List<CachedSong> recentSongs = [];
  bool isLoading = false;
  bool isRefreshing = false;

  final List<Color> randomColors = [
    Color(0xFFFF69B4), Color(0xFFFFB347), Color(0xFFDDA0DD),
    Color(0xFF10B981), Color(0xFFFF6347), Color(0xFF98FB98),
    Color(0xFF87CEEB), Color(0xFFDDA0DD), Color(0xFFF0E68C),
    Color(0xFFFF7F50), Color(0xFF20B2AA), Color(0xFFBA55D3),
  ];

  @override
  void initState() {
    super.initState();
    _loadSongsOptimized();
  }

  Future<void> _loadSongsOptimized() async {
    setState(() => isLoading = true);

    try {
      // 1. First, try to load cached songs for instant startup
      final cachedSongs = await SongCacheManager.getCachedSongs();

      if (cachedSongs.isNotEmpty) {
        // Show cached songs immediately
        setState(() {
          musicFiles = cachedSongs;
          recentSongs = cachedSongs.take(6).toList();
          isLoading = false;
        });

        // Then check if we need to refresh in background
        if (SongCacheManager.shouldRefreshCache()) {
          _refreshSongsInBackground();
        }
      } else {
        // No cache available, perform fresh scan
        await _performFreshScan();
      }
    } catch (e) {
      debugPrint('Error loading songs: $e');
      setState(() => isLoading = false);
    }
  }

  Future<void> _performFreshScan() async {
    try {
      final directories = <String>[];

      if (Platform.isAndroid) {
        Directory? extDir = await getExternalStorageDirectory();
        if (extDir != null) {
          directories.addAll([
            '/storage/emulated/0/Music',
            '/storage/emulated/0/Download',
            '${extDir.path}/Music',
          ]);
        }
      }

      // Use isolate for background scanning
      final songs = await compute(_scanSongsInBackground, directories);

      // Cache the results
      await SongCacheManager.cacheSongs(songs);

      // Update UI
      setState(() {
        musicFiles = songs;
        recentSongs = songs.take(6).toList();
        isLoading = false;
      });
    } catch (e) {
      debugPrint('Error in fresh scan: $e');
      setState(() => isLoading = false);
    }
  }

  Future<void> _refreshSongsInBackground() async {
    setState(() => isRefreshing = true);

    try {
      final directories = <String>[];

      if (Platform.isAndroid) {
        Directory? extDir = await getExternalStorageDirectory();
        if (extDir != null) {
          directories.addAll([
            '/storage/emulated/0/Music',
            '/storage/emulated/0/Download',
            '${extDir.path}/Music',
          ]);
        }
      }

      // Background refresh without blocking UI
      final songs = await compute(_scanSongsInBackground, directories);

      // Update cache
      await SongCacheManager.cacheSongs(songs);

      // Update UI if there are changes
      if (songs.length != musicFiles.length) {
        setState(() {
          musicFiles = songs;
          recentSongs = songs.take(6).toList();
        });
      }
    } catch (e) {
      debugPrint('Error refreshing songs: $e');
    } finally {
      setState(() => isRefreshing = false);
    }
  }

  Future<void> _scanForMusicFiles() async {
    // Manual refresh - clear cache and rescan
    await SongCacheManager.clearCache();
    await _performFreshScan();
  }

  // Convert CachedSong to FileSystemEntity for compatibility
  File _cachedSongToFile(CachedSong song) {
    return File(song.path);
  }

  bool _isAudioFile(String path) {
    final extensions = ['.mp3', '.m4a', '.wav', '.flac', '.aac'];
    return extensions.any((ext) => path.toLowerCase().endsWith(ext));
  }

  String _getFileName(String path) {
    return path.split('/').last.replaceAll(RegExp(r'\.[^.]*$'), '');
  }

  Future<void> _showAddToPlaylistDialog(CachedSong song) async {
    final playlists = await PlaylistManager.getPlaylists();

    if (playlists.isEmpty) {
      // Show dialog to create first playlist
      final shouldCreate = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: _settingsManager.isDarkMode ? Colors.grey[900] : Colors.white,
          title: Text(
            'No Playlists Found',
            style: TextStyle(
              color: _settingsManager.isDarkMode ? Colors.white : Colors.black,
            ),
          ),
          content: Text(
            'You need to create a playlist first. Would you like to create one now?',
            style: TextStyle(
              color: _settingsManager.isDarkMode ? Colors.white : Colors.black,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(
                'Cancel',
                style: TextStyle(color: _settingsManager.isDarkMode ? Colors.white70 : Colors.black54),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(
                'Create Playlist',
                style: TextStyle(color: _settingsManager.themeColor),
              ),
            ),
          ],
        ),
      );

      if (shouldCreate == true) {
        // Show create playlist dialog directly
        String playlistName = '';
        final newPlaylistName = await showDialog<String>(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: _settingsManager.isDarkMode ? Colors.grey[900] : Colors.white,
            title: Text(
              'Create Playlist',
              style: TextStyle(
                color: _settingsManager.isDarkMode ? Colors.white : Colors.black,
              ),
            ),
            content: TextField(
              onChanged: (value) => playlistName = value,
              autofocus: true,
              style: TextStyle(
                color: _settingsManager.isDarkMode ? Colors.white : Colors.black,
              ),
              decoration: InputDecoration(
                hintText: 'Enter playlist name',
                hintStyle: TextStyle(
                  color: (_settingsManager.isDarkMode ? Colors.white : Colors.black).withOpacity(0.6),
                ),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(
                    color: _settingsManager.themeColor,
                  ),
                ),
                focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(
                    color: _settingsManager.themeColor,
                    width: 2,
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  'Cancel',
                  style: TextStyle(color: _settingsManager.isDarkMode ? Colors.white70 : Colors.black54),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, playlistName),
                child: Text(
                  'Create',
                  style: TextStyle(color: _settingsManager.themeColor),
                ),
              ),
            ],
          ),
        );

        if (newPlaylistName != null && newPlaylistName.trim().isNotEmpty) {
          final newPlaylist = await PlaylistManager.createPlaylist(newPlaylistName.trim());
          await PlaylistManager.addSongToPlaylist(newPlaylist.id, song.path);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Created playlist "${newPlaylistName}" and added "${song.title}"'),
              backgroundColor: _settingsManager.themeColor,
            ),
          );
          return;
        }
      }
      return;
    }

    final selectedPlaylist = await showDialog<Playlist>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _settingsManager.isDarkMode ? Colors.grey[900] : Colors.white,
        title: Text(
          'Add to Playlist',
          style: TextStyle(
            color: _settingsManager.isDarkMode ? Colors.white : Colors.black,
          ),
        ),
        content: Container(
          width: double.maxFinite,
          height: 300,
          child: ListView.builder(
            itemCount: playlists.length,
            itemBuilder: (context, index) {
              final playlist = playlists[index];
              final alreadyInPlaylist = playlist.songPaths.contains(song.path);
              return ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _settingsManager.themeColor.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _settingsManager.themeColor.withOpacity(0.5),
                      width: 1,
                    ),
                  ),
                  child: Icon(
                    Icons.queue_music,
                    color: _settingsManager.themeColor,
                    size: 20,
                  ),
                ),
                title: Text(
                  playlist.name,
                  style: TextStyle(
                    color: _settingsManager.isDarkMode ? Colors.white : Colors.black,
                    fontWeight: alreadyInPlaylist ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                subtitle: Text(
                  alreadyInPlaylist
                      ? 'Already in playlist • ${playlist.songPaths.length} songs'
                      : '${playlist.songPaths.length} songs',
                  style: TextStyle(
                    color: alreadyInPlaylist
                        ? _settingsManager.themeColor
                        : (_settingsManager.isDarkMode ? Colors.white : Colors.black).withOpacity(0.7),
                  ),
                ),
                trailing: alreadyInPlaylist
                    ? Icon(Icons.check, color: _settingsManager.themeColor)
                    : null,
                onTap: alreadyInPlaylist
                    ? null
                    : () => Navigator.pop(context, playlist),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: TextStyle(color: _settingsManager.isDarkMode ? Colors.white70 : Colors.black54),
            ),
          ),
        ],
      ),
    );

    if (selectedPlaylist != null) {
      await PlaylistManager.addSongToPlaylist(selectedPlaylist.id, song.path);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Added "${song.title}" to "${selectedPlaylist.name}"'),
          backgroundColor: _settingsManager.themeColor,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _settingsManager.isDarkMode ? Colors.grey[900] : Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Library',
          style: TextStyle(
            color: _settingsManager.isDarkMode ? Colors.white : Colors.black,
            fontSize: 28,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          if (isRefreshing)
            Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: _settingsManager.themeColor,
                ),
              ),
            ),
          IconButton(
            icon: Icon(Icons.refresh, color: _settingsManager.isDarkMode ? Colors.white : Colors.black),
            onPressed: _scanForMusicFiles,
          ),
        ],
      ),
      body: isLoading 
        ? Center(child: CircularProgressIndicator(color: _settingsManager.themeColor))
        : SingleChildScrollView(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
SizedBox(height: 0),
                
                if (musicFiles.isNotEmpty) ...[
                  SizedBox(height: 32),
                  Text(
                    'Your Music (${musicFiles.length} songs)',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: _settingsManager.isDarkMode ? Colors.white : Colors.black,
                    ),
                  ),
                  SizedBox(height: 16),
                  ListView.builder(
                    shrinkWrap: true,
                    physics: NeverScrollableScrollPhysics(),
                    itemCount: musicFiles.length,
                    itemBuilder: (context, index) {
                      final song = musicFiles[index];
                      final file = _cachedSongToFile(song);
                      final fileName = song.title;
                      
                      return ListTile(
                        leading: Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            color: _settingsManager.themeColor,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            Icons.music_note,
                            color: Colors.white,
                          ),
                        ),
                        title: Text(
                          fileName,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: _settingsManager.isDarkMode ? Colors.white : Colors.black,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          song.path.split('/').last,
                          style: TextStyle(
                            color: _settingsManager.isDarkMode ? Colors.grey[400] : Colors.grey[600],
                            fontSize: 12
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: Icon(
                                _audioManager.isFavorite(song.path) ? Icons.favorite : Icons.favorite_border,
                                color: _audioManager.isFavorite(song.path) ? Colors.red : Colors.grey,
                              ),
                              onPressed: () async {
                                await _audioManager.toggleFavorite(song.path);
                                setState(() {});
                              },
                            ),
                            PopupMenuButton<String>(
                              icon: Icon(
                                Icons.more_vert,
                                color: _settingsManager.isDarkMode ? Colors.white : Colors.black,
                              ),
                              onSelected: (value) async {
                                if (value == 'add_to_playlist') {
                                  await _showAddToPlaylistDialog(song);
                                }
                              },
                              itemBuilder: (context) => [
                                PopupMenuItem(
                                  value: 'add_to_playlist',
                                  child: Row(
                                    children: [
                                      Icon(Icons.playlist_add, color: _settingsManager.themeColor),
                                      SizedBox(width: 8),
                                      Text('Add to Playlist'),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            StreamBuilder<bool>(
                              stream: _audioManager.player.playerStateStream.map((state) => _audioManager.isCurrentlyPlaying(song.path)),
                              builder: (context, snapshot) {
                                bool isCurrentlyPlaying = snapshot.data ?? false;
                                return IconButton(
                                  icon: Icon(
                                    isCurrentlyPlaying ? Icons.pause : Icons.play_arrow,
                                    color: _settingsManager.themeColor
                                  ),
                                  onPressed: () async {
                                    if (isCurrentlyPlaying) {
                                      await _audioManager.pause();
                                    } else {
                                      // Set up the current playlist for auto-play
                                      final playlist = musicFiles.map((s) => s.path).toList();
                                      _audioManager.setPlaylist(playlist, index);
                                      await _audioManager.playFromFile(song.path);
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => NowPlayingScreenWithData(
                                            songTitle: fileName,
                                            artist: song.artist,
                                            filePath: song.path,
                                            allSongs: musicFiles.map(_cachedSongToFile).toList(),
                                            currentIndex: index,
                                          ),
                                        ),
                                      );
                                    }
                                  },
                                );
                              },
                            ),
                          ],
                        ),
                        onTap: () async {
                          // Set up the current playlist for auto-play
                          final playlist = musicFiles.map((s) => s.path).toList();
                          _audioManager.setPlaylist(playlist, index);
                          await _audioManager.playFromFile(song.path);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => NowPlayingScreenWithData(
                                songTitle: fileName,
                                artist: song.artist,
                                filePath: song.path,
                                allSongs: musicFiles.map(_cachedSongToFile).toList(),
                                currentIndex: index,
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ],
                
                if (musicFiles.isEmpty && !isLoading) ...[
                  SizedBox(height: 32),
                  Center(
                    child: Column(
                      children: [
                        Icon(
                          Icons.music_off,
                          size: 80,
                          color: Colors.grey[300],
                        ),
                        SizedBox(height: 16),
                        Text(
                          'No music files found',
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.grey[600],
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Place music files in your Music or Download folder',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[500],
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
    );
  }
}

class SearchScreen extends StatefulWidget {
  @override
  _SearchScreenState createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final AudioManager _audioManager = AudioManager();
  final SettingsManager _settingsManager = SettingsManager();
  final TextEditingController _searchController = TextEditingController();
  List<FileSystemEntity> allMusicFiles = [];
  List<FileSystemEntity> filteredFiles = [];
  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    // Don't load music files immediately - only when user starts searching
  }

  Future<void> _loadMusicFiles() async {
    setState(() => isLoading = true);
    
    try {
      List<Directory> musicDirs = [];
      
      if (Platform.isAndroid) {
        Directory? extDir = await getExternalStorageDirectory();
        if (extDir != null) {
          musicDirs.addAll([
            Directory('/storage/emulated/0/Music'),
            Directory('/storage/emulated/0/Download'),
            Directory('${extDir.path}/Music'),
          ]);
        }
      }
      
      List<FileSystemEntity> foundFiles = [];
      for (Directory dir in musicDirs) {
        if (await dir.exists()) {
          await for (FileSystemEntity entity in dir.list(recursive: true)) {
            if (entity is File && _isAudioFile(entity.path)) {
              foundFiles.add(entity);
            }
          }
        }
      }
      
      setState(() {
        allMusicFiles = foundFiles;
        filteredFiles = foundFiles;
        isLoading = false;
      });
    } catch (e) {
      print('Error loading music files: $e');
      setState(() => isLoading = false);
    }
  }

  bool _isAudioFile(String path) {
    final extensions = ['.mp3', '.m4a', '.wav', '.flac', '.aac'];
    return extensions.any((ext) => path.toLowerCase().endsWith(ext));
  }

  String _getFileName(String path) {
    return path.split('/').last.replaceAll(RegExp(r'\.[^.]*$'), '');
  }

  void _filterSongs(String query) async {
    // Load music files if not loaded yet
    if (allMusicFiles.isEmpty && !isLoading) {
      await _loadMusicFiles();
    }

    setState(() {
      if (query.isEmpty) {
        filteredFiles = [];
      } else {
        filteredFiles = allMusicFiles.where((file) {
          final fileName = _getFileName(file.path).toLowerCase();
          return fileName.contains(query.toLowerCase());
        }).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Search',
          style: TextStyle(
            color: _settingsManager.isDarkMode ? Colors.white : Colors.black,
            fontSize: 28,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      backgroundColor: _settingsManager.isDarkMode ? Colors.grey[900] : Colors.white,
      body: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _searchController,
              onChanged: _filterSongs,
              style: TextStyle(
                color: _settingsManager.isDarkMode ? Colors.black : Colors.black,
              ),
              decoration: InputDecoration(
                hintText: 'Search songs, artists, albums...',
                hintStyle: TextStyle(
                  color: _settingsManager.isDarkMode ? Colors.grey[600] : Colors.grey[600],
                ),
                prefixIcon: Icon(Icons.search, color: Colors.grey),
                filled: true,
                fillColor: _settingsManager.isDarkMode ? Colors.white : Colors.grey[100],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            SizedBox(height: 20),
            Expanded(
              child: isLoading
                ? Center(child: CircularProgressIndicator(color: _settingsManager.themeColor))
                : filteredFiles.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _searchController.text.isEmpty ? Icons.search : Icons.music_off,
                            size: 80,
                            color: Colors.grey[300],
                          ),
                          SizedBox(height: 16),
                          Text(
                            _searchController.text.isEmpty 
                              ? 'Search for music'
                              : 'No songs found',
                            style: TextStyle(
                              fontSize: 18,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: filteredFiles.length,
                      itemBuilder: (context, index) {
                        final file = filteredFiles[index];
                        final fileName = _getFileName(file.path);
                        
                        return ListTile(
                          leading: Container(
                            width: 50,
                            height: 50,
                            decoration: BoxDecoration(
                              color: _settingsManager.themeColor,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              Icons.music_note,
                              color: Colors.white,
                            ),
                          ),
                          title: Text(
                            fileName,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: _settingsManager.isDarkMode ? Colors.white : Colors.black,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            file.path.split('/').last,
                            style: TextStyle(
                              color: _settingsManager.isDarkMode ? Colors.grey[400] : Colors.grey[600],
                              fontSize: 12
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: Icon(
                                  _audioManager.isFavorite(file.path) ? Icons.favorite : Icons.favorite_border,
                                  color: _audioManager.isFavorite(file.path) ? Colors.red : Colors.grey,
                                ),
                                onPressed: () async {
                                  await _audioManager.toggleFavorite(file.path);
                                  setState(() {});
                                },
                              ),
                              StreamBuilder<bool>(
                                stream: _audioManager.player.playerStateStream.map((state) => _audioManager.isCurrentlyPlaying(file.path)),
                                builder: (context, snapshot) {
                                  bool isCurrentlyPlaying = snapshot.data ?? false;
                                  return IconButton(
                                    icon: Icon(
                                      isCurrentlyPlaying ? Icons.pause : Icons.play_arrow,
                                      color: _settingsManager.themeColor
                                    ),
                                    onPressed: () async {
                                      if (isCurrentlyPlaying) {
                                        await _audioManager.pause();
                                      } else {
                                        // Set up the current playlist for auto-play
                                        final playlist = allMusicFiles.map((f) => f.path).toList();
                                        final currentIndex = allMusicFiles.indexOf(file);
                                        _audioManager.setPlaylist(playlist, currentIndex);
                                        await _audioManager.playFromFile(file.path);
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) => NowPlayingScreenWithData(
                                              songTitle: fileName,
                                              artist: 'Unknown Artist',
                                              filePath: file.path,
                                              allSongs: allMusicFiles,
                                              currentIndex: currentIndex,
                                            ),
                                          ),
                                        );
                                      }
                                    },
                                  );
                                },
                              ),
                            ],
                          ),
                          onTap: () async {
                            // Set up the current playlist for auto-play
                            final playlist = allMusicFiles.map((f) => f.path).toList();
                            final currentIndex = allMusicFiles.indexOf(file);
                            _audioManager.setPlaylist(playlist, currentIndex);
                            await _audioManager.playFromFile(file.path);
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => NowPlayingScreenWithData(
                                  songTitle: fileName,
                                  artist: 'Unknown Artist',
                                  filePath: file.path,
                                  allSongs: allMusicFiles,
                                  currentIndex: currentIndex,
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class NowPlayingScreen extends StatefulWidget {
  @override
  _NowPlayingScreenState createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends State<NowPlayingScreen> {
  bool isPlaying = false;
  double progress = 0.3;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFF10B981),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.keyboard_arrow_down, color: Colors.white, size: 30),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.more_horiz, color: Colors.white),
            onPressed: () {},
          ),
        ],
      ),
      body: Column(
        children: [
          SizedBox(height: 40),
          Container(
            width: 280,
            height: 180,
            decoration: BoxDecoration(
              color: Color(0xFF0D9968),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 20,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Stack(
              children: [
                Positioned(
                  top: 20,
                  left: 20,
                  right: 20,
                  child: Container(
                    height: 60,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.9),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Text(
                        'blond',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          fontStyle: FontStyle.italic,
                          color: Colors.black,
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 30,
                  left: 40,
                  child: Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: Colors.black,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          color: Color(0xFF0D9968),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 30,
                  right: 40,
                  child: Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: Colors.black,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          color: Color(0xFF0D9968),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 50),
          Text(
            'Nikes',
            style: TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Frank Ocean',
            style: TextStyle(
              color: Colors.white.withOpacity(0.8),
              fontSize: 18,
            ),
          ),
          SizedBox(height: 40),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 40),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '0:14',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.8),
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      '5:09',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.8),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 8),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 4,
                    thumbShape: RoundSliderThumbShape(enabledThumbRadius: 8),
                    overlayShape: RoundSliderOverlayShape(overlayRadius: 16),
                    activeTrackColor: Colors.white,
                    inactiveTrackColor: Colors.white.withOpacity(0.3),
                    thumbColor: Colors.white,
                  ),
                  child: Slider(
                    value: progress,
                    onChanged: (value) => setState(() => progress = value),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 40),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: Icon(Icons.skip_previous, color: Colors.white, size: 40),
                onPressed: () {},
              ),
              SizedBox(width: 20),
              Container(
                width: 70,
                height: 70,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: Icon(
                    isPlaying ? Icons.pause : Icons.play_arrow,
                    color: Colors.white,
                    size: 35,
                  ),
                  onPressed: () => setState(() => isPlaying = !isPlaying),
                ),
              ),
              SizedBox(width: 20),
              IconButton(
                icon: Icon(Icons.skip_next, color: Colors.white, size: 40),
                onPressed: () {},
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class NowPlayingScreenWithData extends StatefulWidget {
  final String? songTitle;
  final String? artist;
  final String? filePath;
  final List<FileSystemEntity>? allSongs;
  final int? currentIndex;

  NowPlayingScreenWithData({
    this.songTitle,
    this.artist,
    this.filePath,
    this.allSongs,
    this.currentIndex,
  });

  @override
  _NowPlayingScreenWithDataState createState() => _NowPlayingScreenWithDataState();
}

class _NowPlayingScreenWithDataState extends State<NowPlayingScreenWithData> {
  final AudioManager _audioManager = AudioManager();
  bool isPlaying = false;
  Duration duration = Duration.zero;
  Duration position = Duration.zero;
  late int currentIndex;
  late List<FileSystemEntity> playlist;
  List<int> shuffledIndices = [];
  int shuffleIndex = 0;
  String currentSongTitle = '';
  String currentArtist = '';
  Uint8List? albumArt;

  @override
  void initState() {
    super.initState();
    currentIndex = widget.currentIndex ?? 0;
    playlist = widget.allSongs ?? [];
    currentSongTitle = widget.songTitle ?? 'Unknown Song';
    currentArtist = widget.artist ?? 'Unknown Artist';
    _initializeShuffleList();
    _setupAudioListeners();
    if (widget.filePath != null) {
      _playFile();
    }
  }

  void _initializeShuffleList() {
    shuffledIndices = List.generate(playlist.length, (index) => index);
    shuffledIndices.shuffle(Random());
    shuffleIndex = shuffledIndices.indexOf(currentIndex);
  }

  void _setupAudioListeners() {
    _audioManager.player.durationStream.listen((d) {
      if (mounted) setState(() => duration = d ?? Duration.zero);
    });
    
    _audioManager.player.positionStream.listen((p) {
      if (mounted) setState(() => position = p);
    });
    
    _audioManager.player.playerStateStream.listen((state) {
      if (mounted) setState(() => isPlaying = state.playing);
    });
  }

  Future<void> _playFile() async {
    if (widget.filePath != null) {
      await _audioManager.playFromFile(widget.filePath!);
      await _extractAlbumArt(widget.filePath!);
    }
  }

  Future<void> _playCurrentSong() async {
    if (playlist.isNotEmpty && currentIndex >= 0 && currentIndex < playlist.length) {
      final file = playlist[currentIndex];
      await _audioManager.playFromFile(file.path);
      setState(() {
        currentSongTitle = _getFileName(file.path);
      });
      await _extractAlbumArt(file.path);
    }
  }

  void _playNext() async {
    if (playlist.isEmpty) return;

    if (_audioManager.isShuffleOn) {
      if (shuffleIndex < shuffledIndices.length - 1) {
        setState(() {
          shuffleIndex++;
          currentIndex = shuffledIndices[shuffleIndex];
        });
        await _playCurrentSong();
      } else {
        // Loop back to beginning when shuffle is on
        setState(() {
          shuffleIndex = 0;
          currentIndex = shuffledIndices[shuffleIndex];
        });
        await _playCurrentSong();
      }
    } else {
      if (currentIndex < playlist.length - 1) {
        setState(() {
          currentIndex++;
        });
        await _playCurrentSong();
      } else {
        // Loop back to beginning when at end of playlist
        setState(() {
          currentIndex = 0;
        });
        await _playCurrentSong();
      }
    }
  }

  void _playPrevious() async {
    if (playlist.isEmpty) return;

    if (_audioManager.isShuffleOn) {
      if (shuffleIndex > 0) {
        setState(() {
          shuffleIndex--;
          currentIndex = shuffledIndices[shuffleIndex];
        });
        await _playCurrentSong();
      }
    } else {
      if (currentIndex > 0) {
        setState(() {
          currentIndex--;
        });
        await _playCurrentSong();
      }
    }
  }

  String _getFileName(String path) {
    return path.split('/').last.replaceAll(RegExp(r'\.[^.]*$'), '');
  }

  Future<void> _togglePlayPause() async {
    if (isPlaying) {
      await _audioManager.pause();
    } else {
      await _audioManager.play();
    }
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return "$twoDigitMinutes:$twoDigitSeconds";
  }

  Future<void> _extractAlbumArt(String filePath) async {
    try {
      final Tag? tag = await AudioTags.read(filePath);
      setState(() {
        albumArt = tag?.pictures.isNotEmpty == true ? tag!.pictures.first.bytes : null;
        currentArtist = tag?.artist ?? 'Unknown Artist';
      });
    } catch (e) {
      setState(() {
        albumArt = null;
        currentArtist = 'Unknown Artist';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final progress = duration.inMilliseconds > 0
        ? position.inMilliseconds / duration.inMilliseconds
        : 0.0;
    final SettingsManager _settingsManager = SettingsManager();
    final Color themeColor = Colors.blue; // Default theme color

    return Scaffold(
      backgroundColor: _settingsManager.isDarkMode ? Colors.black : Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.keyboard_arrow_down, color: Colors.white, size: 30),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.more_horiz, color: Colors.white),
            onPressed: () {},
          ),
        ],
      ),
      body: Column(
        children: [
          SizedBox(height: 40),
          Container(
            width: 280,
            height: 280,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Outer glow effect
                Container(
                  width: 260,
                  height: 260,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: themeColor.withOpacity(0.3),
                        blurRadius: 30,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                ),
                // Main album art circle
                AnimatedRotation(
                  turns: isPlaying ? position.inSeconds / 30.0 : 0,
                  duration: Duration(milliseconds: 100),
                  child: Container(
                    width: 240,
                    height: 240,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.3),
                          blurRadius: 20,
                          offset: Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Album art or gradient background
                        Container(
                          width: 240,
                          height: 240,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            image: albumArt != null
                              ? DecorationImage(
                                  image: MemoryImage(albumArt!),
                                  fit: BoxFit.cover,
                                )
                              : null,
                            gradient: albumArt == null ? LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                themeColor.withOpacity(0.8),
                                themeColor,
                                themeColor.withOpacity(0.6),
                              ],
                            ) : null,
                          ),
                          child: albumArt == null ? Stack(
                            alignment: Alignment.center,
                            children: [
                              // Vinyl texture rings when no album art
                              Container(
                                width: 200,
                                height: 200,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.black.withOpacity(0.1),
                                    width: 1,
                                  ),
                                ),
                              ),
                              Container(
                                width: 160,
                                height: 160,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.black.withOpacity(0.1),
                                    width: 1,
                                  ),
                                ),
                              ),
                              Container(
                                width: 120,
                                height: 120,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.black.withOpacity(0.1),
                                    width: 1,
                                  ),
                                ),
                              ),
                            ],
                          ) : null,
                        ),
                        // Center label/hole (always visible)
                        Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: albumArt != null
                              ? Colors.black.withOpacity(0.7)
                              : (_settingsManager.isDarkMode ? Colors.grey[900] : Colors.white),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.2),
                                blurRadius: 8,
                                offset: Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Icon(
                            Icons.music_note,
                            size: 40,
                            color: albumArt != null ? Colors.white : themeColor,
                          ),
                        ),
                        // Center hole
                        Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.black,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 50),
          Text(
            currentSongTitle,
            style: TextStyle(
              color: _settingsManager.isDarkMode ? Colors.white : Colors.black,
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 8),
          Text(
            currentArtist,
            style: TextStyle(
              color: (_settingsManager.isDarkMode ? Colors.white : Colors.black).withOpacity(0.7),
              fontSize: 18,
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 40),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 40),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _formatDuration(position),
                      style: TextStyle(
                        color: (_settingsManager.isDarkMode ? Colors.white : Colors.black).withOpacity(0.7),
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      _formatDuration(duration),
                      style: TextStyle(
                        color: (_settingsManager.isDarkMode ? Colors.white : Colors.black).withOpacity(0.7),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 8),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 4,
                    thumbShape: RoundSliderThumbShape(enabledThumbRadius: 8),
                    overlayShape: RoundSliderOverlayShape(overlayRadius: 16),
                    activeTrackColor: themeColor,
                    inactiveTrackColor: (_settingsManager.isDarkMode ? Colors.white : Colors.black).withOpacity(0.3),
                    thumbColor: themeColor,
                  ),
                  child: Slider(
                    value: progress.clamp(0.0, 1.0),
                    onChanged: (value) async {
                      final newPosition = Duration(
                        milliseconds: (value * duration.inMilliseconds).round(),
                      );
                      await _audioManager.seek(newPosition);
                    },
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                icon: Icon(
                  Icons.shuffle,
                  color: _audioManager.isShuffleOn ? themeColor : (_settingsManager.isDarkMode ? Colors.white : Colors.black).withOpacity(0.7),
                  size: 28,
                ),
                onPressed: () {
                  setState(() {
                    _audioManager.toggleShuffle();
                    if (_audioManager.isShuffleOn) {
                      _initializeShuffleList();
                    }
                  });
                },
              ),
              IconButton(
                icon: Icon(
                  _audioManager.loopMode == LoopMode.one ? Icons.repeat_one : Icons.repeat,
                  color: _audioManager.isRepeatOn ? themeColor : (_settingsManager.isDarkMode ? Colors.white : Colors.black).withOpacity(0.7),
                  size: 28,
                ),
                onPressed: () {
                  setState(() {
                    _audioManager.toggleRepeat();
                  });
                },
              ),
            ],
          ),
          SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: Icon(Icons.skip_previous, color: _settingsManager.isDarkMode ? Colors.white : Colors.black, size: 40),
                onPressed: _playPrevious,
              ),
              SizedBox(width: 20),
              Container(
                width: 70,
                height: 70,
                decoration: BoxDecoration(
                  color: themeColor.withOpacity(0.2),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: themeColor.withOpacity(0.5),
                    width: 2,
                  ),
                ),
                child: IconButton(
                  icon: Icon(
                    isPlaying ? Icons.pause : Icons.play_arrow,
                    color: themeColor,
                    size: 35,
                  ),
                  onPressed: _togglePlayPause,
                ),
              ),
              SizedBox(width: 20),
              IconButton(
                icon: Icon(Icons.skip_next, color: _settingsManager.isDarkMode ? Colors.white : Colors.black, size: 40),
                onPressed: _playNext,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class AlbumDetailScreen extends StatelessWidget {
  final Album album;
  
  AlbumDetailScreen(this.album);

  final List<Song> songs = [
    Song('Nikes', '5:14'),
    Song('Ivy', '4:09'),
    Song('Pink + White', '3:04'),
    Song('Be Yourself', '1:17'),
    Song('Solo', '4:17'),
    Song('Skyline To', '3:05'),
    Song('Self Control', '4:09'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.more_horiz, color: Colors.black),
            onPressed: () {},
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            height: 200,
            width: 200,
            margin: EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: album.color,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 20,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Center(
              child: Text(
                album.title,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          Text(
            album.title,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.person, size: 16, color: Colors.grey),
              SizedBox(width: 4),
              Text(
                '${album.artist} • Psychedelic Pop • Aug 20, 2016',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 14,
                ),
              ),
              SizedBox(width: 8),
              Icon(Icons.star, size: 16, color: Colors.grey),
              Text(
                '8.8',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 14,
                ),
              ),
            ],
          ),
          SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: EdgeInsets.symmetric(horizontal: 40, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(25),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.play_arrow, color: Colors.white),
                    SizedBox(width: 8),
                    Text(
                      'Play',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: 20),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey[300]!),
                  borderRadius: BorderRadius.circular(25),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.shuffle, color: Colors.black),
                    SizedBox(width: 8),
                    Text(
                      'Shuffle',
                      style: TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 30),
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.symmetric(horizontal: 20),
              itemCount: songs.length,
              itemBuilder: (context, index) {
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    songs[index].title,
                    style: TextStyle(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        songs[index].duration,
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 14,
                        ),
                      ),
                      SizedBox(width: 8),
                      Icon(Icons.more_horiz, color: Colors.grey),
                    ],
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => NowPlayingScreenWithData(
                          songTitle: songs[index].title,
                          artist: album.artist,
                          allSongs: [],
                          currentIndex: 0,
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class PlaylistScreen extends StatefulWidget {
  @override
  _PlaylistScreenState createState() => _PlaylistScreenState();
}

class _PlaylistScreenState extends State<PlaylistScreen> {
  final SettingsManager _settingsManager = SettingsManager();
  List<Playlist> _userPlaylists = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPlaylists();
  }

  Future<void> _loadPlaylists() async {
    setState(() => _isLoading = true);
    final playlists = await PlaylistManager.getPlaylists();
    setState(() {
      _userPlaylists = playlists;
      _isLoading = false;
    });
  }

  Future<void> _showCreatePlaylistDialog() async {
    String playlistName = '';
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _settingsManager.isDarkMode ? Colors.grey[900] : Colors.white,
        title: Text(
          'Create Playlist',
          style: TextStyle(
            color: _settingsManager.isDarkMode ? Colors.white : Colors.black,
          ),
        ),
        content: TextField(
          onChanged: (value) => playlistName = value,
          style: TextStyle(
            color: _settingsManager.isDarkMode ? Colors.white : Colors.black,
          ),
          decoration: InputDecoration(
            hintText: 'Enter playlist name',
            hintStyle: TextStyle(
              color: (_settingsManager.isDarkMode ? Colors.white : Colors.black).withOpacity(0.6),
            ),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(
                color: _settingsManager.themeColor,
              ),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(
                color: _settingsManager.themeColor,
                width: 2,
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: TextStyle(color: _settingsManager.isDarkMode ? Colors.white70 : Colors.black54),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, playlistName),
            child: Text(
              'Create',
              style: TextStyle(color: _settingsManager.themeColor),
            ),
          ),
        ],
      ),
    );

    if (result != null && result.trim().isNotEmpty) {
      await PlaylistManager.createPlaylist(result.trim());
      await _loadPlaylists();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Playlist "$result" created'),
          backgroundColor: _settingsManager.themeColor,
        ),
      );
    }
  }

  Future<void> _deletePlaylist(Playlist playlist) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _settingsManager.isDarkMode ? Colors.grey[900] : Colors.white,
        title: Text(
          'Delete Playlist',
          style: TextStyle(
            color: _settingsManager.isDarkMode ? Colors.white : Colors.black,
          ),
        ),
        content: Text(
          'Are you sure you want to delete "${playlist.name}"?',
          style: TextStyle(
            color: _settingsManager.isDarkMode ? Colors.white : Colors.black,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Cancel',
              style: TextStyle(color: _settingsManager.isDarkMode ? Colors.white70 : Colors.black54),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'Delete',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await PlaylistManager.deletePlaylist(playlist.id);
      await _loadPlaylists();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Playlist "${playlist.name}" deleted'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _settingsManager.isDarkMode ? Colors.black : Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Playlists',
          style: TextStyle(
            color: _settingsManager.isDarkMode ? Colors.white : Colors.black,
            fontSize: 28,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.add, color: _settingsManager.isDarkMode ? Colors.white : Colors.black),
            onPressed: _showCreatePlaylistDialog,
          ),
        ],
      ),
      body: _isLoading
          ? Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(_settingsManager.themeColor),
              ),
            )
          : RefreshIndicator(
              onRefresh: _loadPlaylists,
              color: _settingsManager.themeColor,
              child: ListView(
                padding: EdgeInsets.all(16),
                children: [
                  // Built-in playlists
                  ListTile(
                    leading: Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.purple, Colors.pink],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.history, color: Colors.white),
                    ),
                    title: Text(
                      'Recently Played',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: _settingsManager.isDarkMode ? Colors.white : Colors.black,
                      ),
                    ),
                    subtitle: Text(
                      'Auto-generated • ${AudioManager().recentlyPlayedPaths.length} songs',
                      style: TextStyle(
                        color: (_settingsManager.isDarkMode ? Colors.white : Colors.black).withOpacity(0.7),
                      ),
                    ),
                    trailing: Icon(
                      Icons.chevron_right,
                      color: _settingsManager.isDarkMode ? Colors.white : Colors.black,
                    ),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => RecentlyPlayedScreen(),
                        ),
                      );
                    },
                  ),
                  SizedBox(height: 12),
                  ListTile(
                    leading: Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.red, Colors.pink],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.favorite, color: Colors.white),
                    ),
                    title: Text(
                      'Favorites',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: _settingsManager.isDarkMode ? Colors.white : Colors.black,
                      ),
                    ),
                    subtitle: Text(
                      'Your liked songs • ${AudioManager().favoritePaths.length} songs',
                      style: TextStyle(
                        color: (_settingsManager.isDarkMode ? Colors.white : Colors.black).withOpacity(0.7),
                      ),
                    ),
                    trailing: Icon(
                      Icons.chevron_right,
                      color: _settingsManager.isDarkMode ? Colors.white : Colors.black,
                    ),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => FavoritesScreen(),
                        ),
                      );
                    },
                  ),
                  if (_userPlaylists.isNotEmpty) ...[
                    SizedBox(height: 32),
                    Text(
                      'Your Playlists',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: _settingsManager.isDarkMode ? Colors.white : Colors.black,
                      ),
                    ),
                    SizedBox(height: 16),
                  ],
                  // User-created playlists
                  ..._userPlaylists.map((playlist) => Padding(
                        padding: EdgeInsets.only(bottom: 12),
                        child: ListTile(
                          leading: Container(
                            width: 50,
                            height: 50,
                            decoration: BoxDecoration(
                              color: _settingsManager.themeColor.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: _settingsManager.themeColor.withOpacity(0.5),
                                width: 1,
                              ),
                            ),
                            child: Icon(
                              Icons.queue_music,
                              color: _settingsManager.themeColor,
                            ),
                          ),
                          title: Text(
                            playlist.name,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: _settingsManager.isDarkMode ? Colors.white : Colors.black,
                            ),
                          ),
                          subtitle: Text(
                            '${playlist.songPaths.length} songs',
                            style: TextStyle(
                              color: (_settingsManager.isDarkMode ? Colors.white : Colors.black).withOpacity(0.7),
                            ),
                          ),
                          trailing: PopupMenuButton<String>(
                            icon: Icon(
                              Icons.more_vert,
                              color: _settingsManager.isDarkMode ? Colors.white : Colors.black,
                            ),
                            onSelected: (value) {
                              if (value == 'delete') {
                                _deletePlaylist(playlist);
                              }
                            },
                            itemBuilder: (context) => [
                              PopupMenuItem(
                                value: 'delete',
                                child: Row(
                                  children: [
                                    Icon(Icons.delete, color: Colors.red),
                                    SizedBox(width: 8),
                                    Text('Delete'),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => PlaylistDetailScreen(playlist: playlist),
                              ),
                            ).then((_) => _loadPlaylists());
                          },
                        ),
                      )).toList(),
                  if (_userPlaylists.isEmpty)
                    Padding(
                      padding: EdgeInsets.only(top: 60),
                      child: Column(
                        children: [
                          Icon(
                            Icons.queue_music,
                            size: 80,
                            color: (_settingsManager.isDarkMode ? Colors.white : Colors.black).withOpacity(0.3),
                          ),
                          SizedBox(height: 16),
                          Text(
                            'No playlists yet',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w500,
                              color: (_settingsManager.isDarkMode ? Colors.white : Colors.black).withOpacity(0.6),
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Tap the + button to create your first playlist',
                            style: TextStyle(
                              fontSize: 14,
                              color: (_settingsManager.isDarkMode ? Colors.white : Colors.black).withOpacity(0.5),
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

class PlaylistDetailScreen extends StatefulWidget {
  final Playlist playlist;

  PlaylistDetailScreen({required this.playlist});

  @override
  _PlaylistDetailScreenState createState() => _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends State<PlaylistDetailScreen> {
  final SettingsManager _settingsManager = SettingsManager();
  final AudioManager _audioManager = AudioManager();
  List<CachedSong> _songs = [];
  List<CachedSong> _allSongs = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPlaylistSongs();
  }

  Future<void> _loadPlaylistSongs() async {
    setState(() => _isLoading = true);

    final allCachedSongs = await SongCacheManager.getCachedSongs();
    final playlistSongs = allCachedSongs
        .where((song) => widget.playlist.songPaths.contains(song.path))
        .toList();

    setState(() {
      _songs = playlistSongs;
      _allSongs = allCachedSongs;
      _isLoading = false;
    });
  }

  Future<void> _removeSongFromPlaylist(String songPath) async {
    await PlaylistManager.removeSongFromPlaylist(widget.playlist.id, songPath);
    await _loadPlaylistSongs();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Song removed from playlist'),
        backgroundColor: Colors.red,
      ),
    );
  }

  Future<void> _showAddSongsDialog() async {
    final availableSongs = _allSongs
        .where((song) => !widget.playlist.songPaths.contains(song.path))
        .toList();

    if (availableSongs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('All songs are already in this playlist'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final selectedSongs = await showDialog<List<CachedSong>>(
      context: context,
      builder: (context) => AddSongsDialog(
        availableSongs: availableSongs,
        settingsManager: _settingsManager,
      ),
    );

    if (selectedSongs != null && selectedSongs.isNotEmpty) {
      for (final song in selectedSongs) {
        await PlaylistManager.addSongToPlaylist(widget.playlist.id, song.path);
      }
      await _loadPlaylistSongs();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${selectedSongs.length} song(s) added to playlist'),
          backgroundColor: _settingsManager.themeColor,
        ),
      );
    }
  }

  void _playPlaylist() {
    if (_songs.isNotEmpty) {
      final firstSong = _songs[0];
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => NowPlayingScreenWithData(
            songTitle: firstSong.title,
            artist: firstSong.artist,
            filePath: firstSong.path,
            allSongs: _songs.map((song) => File(song.path)).toList(),
            currentIndex: 0,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _settingsManager.isDarkMode ? Colors.black : Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back,
            color: _settingsManager.isDarkMode ? Colors.white : Colors.black,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.playlist.name,
          style: TextStyle(
            color: _settingsManager.isDarkMode ? Colors.white : Colors.black,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(
              Icons.add,
              color: _settingsManager.isDarkMode ? Colors.white : Colors.black,
            ),
            onPressed: _showAddSongsDialog,
          ),
        ],
      ),
      body: _isLoading
          ? Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(_settingsManager.themeColor),
              ),
            )
          : Column(
              children: [
                // Playlist header
                Container(
                  padding: EdgeInsets.all(24),
                  child: Row(
                    children: [
                      Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          color: _settingsManager.themeColor.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _settingsManager.themeColor.withOpacity(0.5),
                            width: 2,
                          ),
                        ),
                        child: Icon(
                          Icons.queue_music,
                          size: 50,
                          color: _settingsManager.themeColor,
                        ),
                      ),
                      SizedBox(width: 20),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.playlist.name,
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: _settingsManager.isDarkMode ? Colors.white : Colors.black,
                              ),
                            ),
                            SizedBox(height: 8),
                            Text(
                              '${_songs.length} songs',
                              style: TextStyle(
                                fontSize: 16,
                                color: (_settingsManager.isDarkMode ? Colors.white : Colors.black).withOpacity(0.7),
                              ),
                            ),
                            if (_songs.isNotEmpty) ...[
                              SizedBox(height: 16),
                              ElevatedButton.icon(
                                onPressed: _playPlaylist,
                                icon: Icon(Icons.play_arrow, color: Colors.white),
                                label: Text(
                                  'Play',
                                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _settingsManager.themeColor,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(25),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                // Songs list
                Expanded(
                  child: _songs.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.music_note,
                                size: 80,
                                color: (_settingsManager.isDarkMode ? Colors.white : Colors.black).withOpacity(0.3),
                              ),
                              SizedBox(height: 16),
                              Text(
                                'No songs in this playlist',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w500,
                                  color: (_settingsManager.isDarkMode ? Colors.white : Colors.black).withOpacity(0.6),
                                ),
                              ),
                              SizedBox(height: 8),
                              Text(
                                'Tap the + button to add songs',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: (_settingsManager.isDarkMode ? Colors.white : Colors.black).withOpacity(0.5),
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          itemCount: _songs.length,
                          itemBuilder: (context, index) {
                            final song = _songs[index];
                            return ListTile(
                              leading: Container(
                                width: 50,
                                height: 50,
                                decoration: BoxDecoration(
                                  color: _settingsManager.themeColor.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(
                                  Icons.music_note,
                                  color: _settingsManager.themeColor,
                                ),
                              ),
                              title: Text(
                                song.title,
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: _settingsManager.isDarkMode ? Colors.white : Colors.black,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                song.artist,
                                style: TextStyle(
                                  color: (_settingsManager.isDarkMode ? Colors.white : Colors.black).withOpacity(0.7),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: PopupMenuButton<String>(
                                icon: Icon(
                                  Icons.more_vert,
                                  color: _settingsManager.isDarkMode ? Colors.white : Colors.black,
                                ),
                                onSelected: (value) {
                                  if (value == 'remove') {
                                    _removeSongFromPlaylist(song.path);
                                  }
                                },
                                itemBuilder: (context) => [
                                  PopupMenuItem(
                                    value: 'remove',
                                    child: Row(
                                      children: [
                                        Icon(Icons.remove_circle, color: Colors.red),
                                        SizedBox(width: 8),
                                        Text('Remove from playlist'),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              onTap: () {
                                final song = _songs[index];
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => NowPlayingScreenWithData(
                                      songTitle: song.title,
                                      artist: song.artist,
                                      filePath: song.path,
                                      allSongs: _songs.map((s) => File(s.path)).toList(),
                                      currentIndex: index,
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}

class AddSongsDialog extends StatefulWidget {
  final List<CachedSong> availableSongs;
  final SettingsManager settingsManager;

  AddSongsDialog({required this.availableSongs, required this.settingsManager});

  @override
  _AddSongsDialogState createState() => _AddSongsDialogState();
}

class _AddSongsDialogState extends State<AddSongsDialog> {
  Set<CachedSong> _selectedSongs = {};
  String _searchQuery = '';

  List<CachedSong> get _filteredSongs {
    if (_searchQuery.isEmpty) return widget.availableSongs;
    return widget.availableSongs
        .where((song) =>
            song.title.toLowerCase().contains(_searchQuery.toLowerCase()) ||
            song.artist.toLowerCase().contains(_searchQuery.toLowerCase()))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: widget.settingsManager.isDarkMode ? Colors.grey[900] : Colors.white,
      title: Text(
        'Add Songs',
        style: TextStyle(
          color: widget.settingsManager.isDarkMode ? Colors.white : Colors.black,
        ),
      ),
      content: Container(
        width: double.maxFinite,
        height: 400,
        child: Column(
          children: [
            TextField(
              onChanged: (value) => setState(() => _searchQuery = value),
              style: TextStyle(
                color: widget.settingsManager.isDarkMode ? Colors.white : Colors.black,
              ),
              decoration: InputDecoration(
                hintText: 'Search songs...',
                hintStyle: TextStyle(
                  color: (widget.settingsManager.isDarkMode ? Colors.white : Colors.black).withOpacity(0.6),
                ),
                prefixIcon: Icon(
                  Icons.search,
                  color: widget.settingsManager.themeColor,
                ),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: widget.settingsManager.themeColor),
                ),
                focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: widget.settingsManager.themeColor, width: 2),
                ),
              ),
            ),
            SizedBox(height: 16),
            Expanded(
              child: ListView.builder(
                itemCount: _filteredSongs.length,
                itemBuilder: (context, index) {
                  final song = _filteredSongs[index];
                  final isSelected = _selectedSongs.contains(song);
                  return CheckboxListTile(
                    value: isSelected,
                    onChanged: (value) {
                      setState(() {
                        if (value == true) {
                          _selectedSongs.add(song);
                        } else {
                          _selectedSongs.remove(song);
                        }
                      });
                    },
                    title: Text(
                      song.title,
                      style: TextStyle(
                        color: widget.settingsManager.isDarkMode ? Colors.white : Colors.black,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      song.artist,
                      style: TextStyle(
                        color: (widget.settingsManager.isDarkMode ? Colors.white : Colors.black).withOpacity(0.7),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    activeColor: widget.settingsManager.themeColor,
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            'Cancel',
            style: TextStyle(
              color: widget.settingsManager.isDarkMode ? Colors.white70 : Colors.black54,
            ),
          ),
        ),
        TextButton(
          onPressed: _selectedSongs.isNotEmpty
              ? () => Navigator.pop(context, _selectedSongs.toList())
              : null,
          child: Text(
            'Add (${_selectedSongs.length})',
            style: TextStyle(
              color: _selectedSongs.isNotEmpty
                  ? widget.settingsManager.themeColor
                  : (widget.settingsManager.isDarkMode ? Colors.white70 : Colors.black54),
            ),
          ),
        ),
      ],
    );
  }
}

class SettingsScreen extends StatefulWidget {
  final VoidCallback? onThemeChanged;

  SettingsScreen({this.onThemeChanged});

  @override
  _SettingsScreenState createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final SettingsManager _settingsManager = SettingsManager();
  final AudioManager _audioManager = AudioManager();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Settings',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: ListView(
        padding: EdgeInsets.all(16),
        children: [
          _buildSettingsSection('Appearance', [
            _buildDarkModeItem(),
            _buildThemeColorItem(),
          ]),
          _buildSettingsSection('Storage', [
            _buildMusicFoldersItem(),
            _buildSettingsItem(Icons.storage, 'Cache Size', '156 MB'),
          ]),
          _buildSettingsSection('About', [
            _buildSettingsItem(Icons.info, 'Version', '1.0.0'),
            _buildSettingsItem(Icons.help, 'Help & Support', ''),
          ]),
        ],
      ),
    );
  }


  Widget _buildDarkModeItem() {
    return ListTile(
      leading: Icon(Icons.dark_mode, color: _settingsManager.themeColor),
      title: Text('Dark Mode', style: TextStyle(fontWeight: FontWeight.w500)),
      trailing: Switch(
        value: _settingsManager.isDarkMode,
        activeColor: _settingsManager.themeColor,
        onChanged: (value) async {
          setState(() {});
          await _settingsManager.toggleDarkMode();
          widget.onThemeChanged?.call();
        },
      ),
    );
  }

  Widget _buildThemeColorItem() {
    return ListTile(
      leading: Icon(Icons.color_lens, color: _settingsManager.themeColor),
      title: Text('Theme Color', style: TextStyle(fontWeight: FontWeight.w500)),
      subtitle: Text(_getColorName(_settingsManager.themeColor)),
      trailing: Icon(Icons.chevron_right, color: Colors.grey),
      onTap: () {
        _showColorPicker();
      },
    );
  }

  Widget _buildMusicFoldersItem() {
    return ListTile(
      leading: Icon(Icons.folder, color: _settingsManager.themeColor),
      title: Text('Music Folders', style: TextStyle(fontWeight: FontWeight.w500)),
      subtitle: Text('${_settingsManager.musicFolders.length} folders'),
      trailing: Icon(Icons.chevron_right, color: Colors.grey),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => MusicFoldersScreen(),
          ),
        );
      },
    );
  }

  void _showColorPicker() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Choose Theme Color'),
          content: Container(
            width: 300,
            height: 200,
            child: GridView.builder(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
              ),
              itemCount: _settingsManager.availableColors.length,
              itemBuilder: (context, index) {
                final color = _settingsManager.availableColors[index];
                return GestureDetector(
                  onTap: () async {
                    setState(() {});
                    await _settingsManager.setThemeColor(color);
                    widget.onThemeChanged?.call();
                    Navigator.pop(context);

                    // Also refresh the main screen
                    if (Navigator.canPop(context)) {
                      Navigator.popUntil(context, (route) => route.isFirst);
                    }
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: _settingsManager.themeColor == color
                          ? Border.all(color: Colors.white, width: 3)
                          : null,
                    ),
                    child: _settingsManager.themeColor == color
                        ? Icon(Icons.check, color: Colors.white)
                        : null,
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  String _getColorName(Color color) {
    if (color == Color(0xFF10B981)) return 'Green';
    if (color == Color(0xFF3B82F6)) return 'Blue';
    if (color == Color(0xFFEF4444)) return 'Red';
    if (color == Color(0xFF8B5CF6)) return 'Purple';
    if (color == Color(0xFFF59E0B)) return 'Orange';
    if (color == Color(0xFFEC4899)) return 'Pink';
    return 'Custom';
  }

  Widget _buildSettingsSection(String title, List<Widget> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        ...items,
        SizedBox(height: 16),
      ],
    );
  }

  Widget _buildSettingsItem(IconData icon, String title, String subtitle) {
    return ListTile(
      leading: Icon(icon, color: _settingsManager.themeColor),
      title: Text(
        title,
        style: TextStyle(fontWeight: FontWeight.w500),
      ),
      subtitle: subtitle.isNotEmpty ? Text(subtitle) : null,
      trailing: Icon(Icons.chevron_right, color: Colors.grey),
      onTap: () {},
    );
  }
}

class MusicFoldersScreen extends StatefulWidget {
  @override
  _MusicFoldersScreenState createState() => _MusicFoldersScreenState();
}

class _MusicFoldersScreenState extends State<MusicFoldersScreen> {
  final SettingsManager _settingsManager = SettingsManager();

  @override
  void initState() {
    super.initState();
    // Initialize default folders if empty
    if (_settingsManager.musicFolders.isEmpty) {
      _settingsManager.addMusicFolder('/storage/emulated/0/Music');
      _settingsManager.addMusicFolder('/storage/emulated/0/Download');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Music Folders'),
        actions: [
          IconButton(
            icon: Icon(Icons.add),
            onPressed: _addMusicFolder,
          ),
        ],
      ),
      body: _settingsManager.musicFolders.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.folder_open, size: 80, color: Colors.grey[300]),
                  SizedBox(height: 16),
                  Text(
                    'No music folders added',
                    style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Tap + to add a music folder',
                    style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: EdgeInsets.all(16),
              itemCount: _settingsManager.musicFolders.length,
              itemBuilder: (context, index) {
                final folder = _settingsManager.musicFolders[index];
                return Card(
                  child: ListTile(
                    leading: Icon(Icons.folder, color: _settingsManager.themeColor),
                    title: Text(
                      folder.split('/').last,
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      folder,
                      style: TextStyle(fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: IconButton(
                      icon: Icon(Icons.delete, color: Colors.red),
                      onPressed: () {
                        setState(() {
                          _settingsManager.removeMusicFolder(folder);
                        });
                      },
                    ),
                  ),
                );
              },
            ),
    );
  }

  void _addMusicFolder() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Add Music Folder'),
          content: TextField(
            controller: controller,
            decoration: InputDecoration(
              hintText: 'Enter folder path',
              prefixText: '/storage/emulated/0/',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                final path = '/storage/emulated/0/${controller.text}';
                if (controller.text.isNotEmpty) {
                  setState(() {
                    _settingsManager.addMusicFolder(path);
                  });
                }
                Navigator.pop(context);
              },
              child: Text('Add'),
            ),
          ],
        );
      },
    );
  }
}

// Data Models
class Album {
  final String title;
  final String artist;
  final String imagePath;
  final Color color;

  Album(this.title, this.artist, this.imagePath, this.color);
}

class Song {
  final String title;
  final String duration;

  Song(this.title, this.duration);
}

class RecentlyPlayedScreen extends StatefulWidget {
  @override
  _RecentlyPlayedScreenState createState() => _RecentlyPlayedScreenState();
}

class _RecentlyPlayedScreenState extends State<RecentlyPlayedScreen> {
  final AudioManager _audioManager = AudioManager();
  final SettingsManager _settingsManager = SettingsManager();
  List<FileSystemEntity> recentlyPlayedFiles = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadRecentlyPlayed();
  }

  Future<void> _loadRecentlyPlayed() async {
    setState(() => isLoading = true);
    List<FileSystemEntity> validFiles = [];

    for (String path in _audioManager.recentlyPlayedPaths) {
      final file = File(path);
      if (await file.exists()) {
        validFiles.add(file);
      }
    }

    setState(() {
      recentlyPlayedFiles = validFiles;
      isLoading = false;
    });
  }

  String _getFileName(String path) {
    return path.split('/').last.replaceAll(RegExp(r'\.[^.]*$'), '');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _settingsManager.isDarkMode ? Colors.grey[900] : Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios, color: _settingsManager.isDarkMode ? Colors.white : Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Recently Played',
          style: TextStyle(
            color: _settingsManager.isDarkMode ? Colors.white : Colors.black,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: isLoading
        ? Center(child: CircularProgressIndicator(color: _settingsManager.themeColor))
        : recentlyPlayedFiles.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.history,
                    size: 80,
                    color: Colors.grey[300],
                  ),
                  SizedBox(height: 16),
                  Text(
                    'No recently played songs',
                    style: TextStyle(
                      fontSize: 18,
                      color: _settingsManager.isDarkMode ? Colors.grey[400] : Colors.grey[600],
                    ),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: EdgeInsets.all(16),
              itemCount: recentlyPlayedFiles.length,
              itemBuilder: (context, index) {
                final file = recentlyPlayedFiles[index];
                final fileName = _getFileName(file.path);

                return ListTile(
                  leading: Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: SettingsManager().themeColor,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.music_note,
                      color: Colors.white,
                    ),
                  ),
                  title: Text(
                    fileName,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: _settingsManager.isDarkMode ? Colors.white : Colors.black,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    'Recently played',
                    style: TextStyle(
                      color: _settingsManager.isDarkMode ? Colors.grey[400] : Colors.grey[600],
                      fontSize: 12
                    ),
                  ),
                  trailing: IconButton(
                    icon: Icon(Icons.play_arrow, color: SettingsManager().themeColor),
                    onPressed: () async {
                      await _audioManager.playFromFile(file.path);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => NowPlayingScreenWithData(
                            songTitle: fileName,
                            artist: 'Unknown Artist',
                            filePath: file.path,
                            allSongs: recentlyPlayedFiles,
                            currentIndex: index,
                          ),
                        ),
                      );
                    },
                  ),
                  onTap: () async {
                    await _audioManager.playFromFile(file.path);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => NowPlayingScreenWithData(
                          songTitle: fileName,
                          artist: 'Unknown Artist',
                          filePath: file.path,
                          allSongs: recentlyPlayedFiles,
                          currentIndex: index,
                        ),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}

class FavoritesScreen extends StatefulWidget {
  @override
  _FavoritesScreenState createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  final AudioManager _audioManager = AudioManager();
  final SettingsManager _settingsManager = SettingsManager();
  List<FileSystemEntity> favoriteFiles = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadFavorites();
  }

  Future<void> _loadFavorites() async {
    setState(() => isLoading = true);
    List<FileSystemEntity> validFiles = [];

    for (String path in _audioManager.favoritePaths) {
      final file = File(path);
      if (await file.exists()) {
        validFiles.add(file);
      }
    }

    setState(() {
      favoriteFiles = validFiles;
      isLoading = false;
    });
  }

  String _getFileName(String path) {
    return path.split('/').last.replaceAll(RegExp(r'\.[^.]*$'), '');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _settingsManager.isDarkMode ? Colors.grey[900] : Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios, color: _settingsManager.isDarkMode ? Colors.white : Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Favorites',
          style: TextStyle(
            color: _settingsManager.isDarkMode ? Colors.white : Colors.black,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: isLoading
        ? Center(child: CircularProgressIndicator(color: _settingsManager.themeColor))
        : favoriteFiles.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.favorite_border,
                    size: 80,
                    color: Colors.grey[300],
                  ),
                  SizedBox(height: 16),
                  Text(
                    'No favorite songs yet',
                    style: TextStyle(
                      fontSize: 18,
                      color: _settingsManager.isDarkMode ? Colors.grey[400] : Colors.grey[600],
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Tap the heart icon to add songs to favorites',
                    style: TextStyle(
                      fontSize: 14,
                      color: _settingsManager.isDarkMode ? Colors.grey[500] : Colors.grey[500],
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: EdgeInsets.all(16),
              itemCount: favoriteFiles.length,
              itemBuilder: (context, index) {
                final file = favoriteFiles[index];
                final fileName = _getFileName(file.path);

                return ListTile(
                  leading: Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: SettingsManager().themeColor,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.music_note,
                      color: Colors.white,
                    ),
                  ),
                  title: Text(
                    fileName,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: _settingsManager.isDarkMode ? Colors.white : Colors.black,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    'Favorite song',
                    style: TextStyle(
                      color: _settingsManager.isDarkMode ? Colors.grey[400] : Colors.grey[600],
                      fontSize: 12
                    ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Icon(Icons.favorite, color: Colors.red),
                        onPressed: () async {
                          await _audioManager.toggleFavorite(file.path);
                          _loadFavorites();
                        },
                      ),
                      IconButton(
                        icon: Icon(Icons.play_arrow, color: SettingsManager().themeColor),
                        onPressed: () async {
                          await _audioManager.playFromFile(file.path);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => NowPlayingScreenWithData(
                                songTitle: fileName,
                                artist: 'Unknown Artist',
                                filePath: file.path,
                                allSongs: favoriteFiles,
                                currentIndex: index,
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                  onTap: () async {
                    await _audioManager.playFromFile(file.path);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => NowPlayingScreenWithData(
                          songTitle: fileName,
                          artist: 'Unknown Artist',
                          filePath: file.path,
                          allSongs: favoriteFiles,
                          currentIndex: index,
                        ),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}