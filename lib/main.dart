import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'dart:math';
import 'dart:convert';

void main() {
  runApp(MusicPlayerApp());
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

  // Theme colors available
  final List<Color> availableColors = [
    Color(0xFF10B981), // Green (default)
    Color(0xFF3B82F6), // Blue
    Color(0xFFEF4444), // Red
    Color(0xFF8B5CF6), // Purple
    Color(0xFFF59E0B), // Orange
    Color(0xFFEC4899), // Pink
  ];

  void toggleDarkMode() {
    isDarkMode = !isDarkMode;
  }

  void setThemeColor(Color color) {
    themeColor = color;
  }

  void addMusicFolder(String path) {
    if (!musicFolders.contains(path)) {
      musicFolders.add(path);
    }
  }

  void removeMusicFolder(String path) {
    musicFolders.remove(path);
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
  bool isPlaying = false;
  bool isShuffleOn = false;
  bool isRepeatOn = false;
  LoopMode loopMode = LoopMode.off;
  Duration duration = Duration.zero;
  Duration position = Duration.zero;
  List<String> recentlyPlayedPaths = [];
  List<String> favoritePaths = [];

  AudioPlayer get player => _audioPlayer;

  Future<void> init() async {
    _audioPlayer.durationStream.listen((d) => duration = d ?? Duration.zero);
    _audioPlayer.positionStream.listen((p) => position = p);
    _audioPlayer.playerStateStream.listen((state) {
      isPlaying = state.playing;
    });
    await loadSavedData();
  }

  Future<void> playFromFile(String filePath) async {
    try {
      await _audioPlayer.setFilePath(filePath);
      await _audioPlayer.play();
      await _addToRecentlyPlayed(filePath);
    } catch (e) {
      print('Error playing file: $e');
    }
  }

  Future<void> _addToRecentlyPlayed(String filePath) async {
    recentlyPlayedPaths.remove(filePath);
    recentlyPlayedPaths.insert(0, filePath);
    if (recentlyPlayedPaths.length > 50) {
      recentlyPlayedPaths = recentlyPlayedPaths.take(50).toList();
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
    setState(() {});
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
  
  late final List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    _screens = [
      LibraryScreen(),
      SearchScreen(),
      PlaylistScreen(),
      SettingsScreen(onThemeChanged: widget.onThemeChanged),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        type: BottomNavigationBarType.fixed,
        selectedItemColor: Color(0xFF10B981),
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
  List<FileSystemEntity> musicFiles = [];
  List<FileSystemEntity> recentSongs = [];
  bool isLoading = false;

  final List<Color> randomColors = [
    Color(0xFFFF69B4), Color(0xFFFFB347), Color(0xFFDDA0DD),
    Color(0xFF10B981), Color(0xFFFF6347), Color(0xFF98FB98),
    Color(0xFF87CEEB), Color(0xFFDDA0DD), Color(0xFFF0E68C),
    Color(0xFFFF7F50), Color(0xFF20B2AA), Color(0xFFBA55D3),
  ];

  @override
  void initState() {
    super.initState();
    _scanForMusicFiles();
  }

  Future<void> _scanForMusicFiles() async {
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
      
      // Sort by date modified (most recent first)
      foundFiles.sort((a, b) {
        final aStat = (a as File).lastModifiedSync();
        final bStat = (b as File).lastModifiedSync();
        return bStat.compareTo(aStat);
      });
      
      setState(() {
        musicFiles = foundFiles;
        recentSongs = foundFiles.take(6).toList();
        isLoading = false;
      });
    } catch (e) {
      print('Error scanning for music files: $e');
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Library',
          style: TextStyle(
            color: Colors.black,
            fontSize: 28,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh, color: Colors.black),
            onPressed: _scanForMusicFiles,
          ),
        ],
      ),
      body: isLoading 
        ? Center(child: CircularProgressIndicator(color: Color(0xFF10B981)))
        : SingleChildScrollView(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                musicFiles.isNotEmpty
                  ? Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () async {
                              if (musicFiles.isNotEmpty) {
                                final firstSong = musicFiles.first;
                                final fileName = _getFileName(firstSong.path);
                                await _audioManager.playFromFile(firstSong.path);
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => NowPlayingScreenWithData(
                                      songTitle: fileName,
                                      artist: 'Unknown Artist',
                                      filePath: firstSong.path,
                                      allSongs: musicFiles,
                                      currentIndex: 0,
                                    ),
                                  ),
                                );
                              }
                            },
                            child: Column(
                              children: [
                                Container(
                                  width: 160,
                                  height: 160,
                                  decoration: BoxDecoration(
                                    color: randomColors[0],
                                    borderRadius: BorderRadius.circular(80),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.1),
                                        blurRadius: 10,
                                        offset: Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: Stack(
                                    children: [
                                      Center(
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
                                                color: randomColors[0],
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                SizedBox(height: 16),
                                Text(
                                  'Disc 1',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black,
                                  ),
                                ),
                                Text(
                                  '${(musicFiles.length / 2).ceil()} songs',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        SizedBox(width: 20),
                        Expanded(
                          child: GestureDetector(
                            onTap: () async {
                              if (musicFiles.length > 1) {
                                final midIndex = (musicFiles.length / 2).ceil();
                                final secondDiscFirstSong = musicFiles[midIndex];
                                final fileName = _getFileName(secondDiscFirstSong.path);
                                await _audioManager.playFromFile(secondDiscFirstSong.path);
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => NowPlayingScreenWithData(
                                      songTitle: fileName,
                                      artist: 'Unknown Artist',
                                      filePath: secondDiscFirstSong.path,
                                      allSongs: musicFiles,
                                      currentIndex: midIndex,
                                    ),
                                  ),
                                );
                              }
                            },
                            child: Column(
                              children: [
                                Container(
                                  width: 160,
                                  height: 160,
                                  decoration: BoxDecoration(
                                    color: randomColors[1],
                                    borderRadius: BorderRadius.circular(80),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.1),
                                        blurRadius: 10,
                                        offset: Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: Stack(
                                    children: [
                                      Center(
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
                                                color: randomColors[1],
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                SizedBox(height: 16),
                                Text(
                                  'Disc 2',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black,
                                  ),
                                ),
                                Text(
                                  '${musicFiles.length - (musicFiles.length / 2).ceil()} songs',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    )
                  : Container(
                      height: 200,
                      child: Center(
                        child: Text(
                          'No music found',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                
                if (musicFiles.isNotEmpty) ...[
                  SizedBox(height: 32),
                  Text(
                    'Your Music (${musicFiles.length} songs)',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                  SizedBox(height: 16),
                  ListView.builder(
                    shrinkWrap: true,
                    physics: NeverScrollableScrollPhysics(),
                    itemCount: musicFiles.length,
                    itemBuilder: (context, index) {
                      final file = musicFiles[index];
                      final fileName = _getFileName(file.path);
                      
                      return ListTile(
                        leading: Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            color: Color(0xFF10B981),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            Icons.music_note,
                            color: Colors.white,
                          ),
                        ),
                        title: Text(
                          fileName,
                          style: TextStyle(fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          file.path.split('/').last,
                          style: TextStyle(color: Colors.grey[600], fontSize: 12),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: IconButton(
                          icon: Icon(Icons.play_arrow, color: Color(0xFF10B981)),
                          onPressed: () async {
                            await _audioManager.playFromFile(file.path);
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => NowPlayingScreenWithData(
                                  songTitle: fileName,
                                  artist: 'Unknown Artist',
                                  filePath: file.path,
                                  allSongs: musicFiles,
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
                                allSongs: musicFiles,
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
  final TextEditingController _searchController = TextEditingController();
  List<FileSystemEntity> allMusicFiles = [];
  List<FileSystemEntity> filteredFiles = [];
  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadMusicFiles();
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

  void _filterSongs(String query) {
    setState(() {
      if (query.isEmpty) {
        filteredFiles = allMusicFiles;
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
            color: Colors.black,
            fontSize: 28,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _searchController,
              onChanged: _filterSongs,
              decoration: InputDecoration(
                hintText: 'Search songs, artists, albums...',
                prefixIcon: Icon(Icons.search, color: Colors.grey),
                filled: true,
                fillColor: Colors.grey[100],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            SizedBox(height: 20),
            Expanded(
              child: isLoading
                ? Center(child: CircularProgressIndicator(color: Color(0xFF10B981)))
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
                              color: Color(0xFF10B981),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              Icons.music_note,
                              color: Colors.white,
                            ),
                          ),
                          title: Text(
                            fileName,
                            style: TextStyle(fontWeight: FontWeight.w600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            file.path.split('/').last,
                            style: TextStyle(color: Colors.grey[600], fontSize: 12),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: IconButton(
                            icon: Icon(Icons.play_arrow, color: Color(0xFF10B981)),
                            onPressed: () async {
                              await _audioManager.playFromFile(file.path);
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => NowPlayingScreenWithData(
                                    songTitle: fileName,
                                    artist: 'Unknown Artist',
                                    filePath: file.path,
                                    allSongs: allMusicFiles,
                                    currentIndex: allMusicFiles.indexOf(file),
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
                                  allSongs: allMusicFiles,
                                  currentIndex: allMusicFiles.indexOf(file),
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
    }
  }

  Future<void> _playCurrentSong() async {
    if (playlist.isNotEmpty && currentIndex >= 0 && currentIndex < playlist.length) {
      final file = playlist[currentIndex];
      await _audioManager.playFromFile(file.path);
      setState(() {
        currentSongTitle = _getFileName(file.path);
        currentArtist = 'Unknown Artist';
      });
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
      }
    } else {
      if (currentIndex < playlist.length - 1) {
        setState(() {
          currentIndex++;
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

  @override
  Widget build(BuildContext context) {
    final progress = duration.inMilliseconds > 0 
        ? position.inMilliseconds / duration.inMilliseconds 
        : 0.0;

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
                        currentSongTitle,
                        style: TextStyle(
                          fontSize: currentSongTitle.length > 8 ? 20 : 28,
                          fontWeight: FontWeight.bold,
                          fontStyle: FontStyle.italic,
                          color: Colors.black,
                        ),
                        maxLines: 2,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 30,
                  left: 40,
                  child: AnimatedRotation(
                    turns: isPlaying ? position.inSeconds / 10.0 : 0,
                    duration: Duration(milliseconds: 100),
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
                ),
                Positioned(
                  bottom: 30,
                  right: 40,
                  child: AnimatedRotation(
                    turns: isPlaying ? position.inSeconds / 8.0 : 0,
                    duration: Duration(milliseconds: 100),
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
                ),
              ],
            ),
          ),
          SizedBox(height: 50),
          Text(
            currentSongTitle,
            style: TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          SizedBox(height: 8),
          Text(
            currentArtist,
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
                      _formatDuration(position),
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.8),
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      _formatDuration(duration),
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
                  color: _audioManager.isShuffleOn ? Colors.green : Colors.white.withOpacity(0.7),
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
                  color: _audioManager.isRepeatOn ? Colors.green : Colors.white.withOpacity(0.7),
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
                icon: Icon(Icons.skip_previous, color: Colors.white, size: 40),
                onPressed: _playPrevious,
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
                  onPressed: _togglePlayPause,
                ),
              ),
              SizedBox(width: 20),
              IconButton(
                icon: Icon(Icons.skip_next, color: Colors.white, size: 40),
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

class PlaylistScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Playlists',
          style: TextStyle(
            color: Colors.black,
            fontSize: 28,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.add, color: Colors.black),
            onPressed: () {},
          ),
        ],
      ),
      body: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
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
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text('Auto-generated • ${AudioManager().recentlyPlayedPaths.length} songs'),
              trailing: Icon(Icons.chevron_right),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => RecentlyPlayedScreen(),
                  ),
                );
              },
            ),
            SizedBox(height: 20),
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
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text('Your liked songs • ${AudioManager().favoritePaths.length} songs'),
              trailing: Icon(Icons.chevron_right),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => FavoritesScreen(),
                  ),
                );
              },
            ),
          ],
        ),
      ),
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
          _buildSettingsSection('Audio', [
            _buildEqualizerItem(),
            _buildVolumeBoostItem(),
            _buildSettingsItem(Icons.high_quality, 'Audio Quality', 'High'),
          ]),
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

  Widget _buildEqualizerItem() {
    return ExpansionTile(
      leading: Icon(Icons.graphic_eq, color: _settingsManager.themeColor),
      title: Text('Equalizer', style: TextStyle(fontWeight: FontWeight.w500)),
      children: [
        Padding(
          padding: EdgeInsets.all(16),
          child: Column(
            children: [
              Text('Bass: ${_settingsManager.equalizerBass.toStringAsFixed(1)}'),
              Slider(
                value: _settingsManager.equalizerBass,
                min: -10.0,
                max: 10.0,
                divisions: 20,
                activeColor: _settingsManager.themeColor,
                onChanged: (value) {
                  setState(() {
                    _settingsManager.equalizerBass = value;
                  });
                },
              ),
              SizedBox(height: 16),
              Text('Treble: ${_settingsManager.equalizerTreble.toStringAsFixed(1)}'),
              Slider(
                value: _settingsManager.equalizerTreble,
                min: -10.0,
                max: 10.0,
                divisions: 20,
                activeColor: _settingsManager.themeColor,
                onChanged: (value) {
                  setState(() {
                    _settingsManager.equalizerTreble = value;
                  });
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildVolumeBoostItem() {
    return ExpansionTile(
      leading: Icon(Icons.volume_up, color: _settingsManager.themeColor),
      title: Text('Volume Boost', style: TextStyle(fontWeight: FontWeight.w500)),
      subtitle: Text('${(_settingsManager.volumeBoost * 100).toInt()}%'),
      children: [
        Padding(
          padding: EdgeInsets.all(16),
          child: Column(
            children: [
              Text('Volume Boost: ${(_settingsManager.volumeBoost * 100).toInt()}%'),
              Slider(
                value: _settingsManager.volumeBoost,
                min: 0.0,
                max: 2.0,
                divisions: 20,
                activeColor: _settingsManager.themeColor,
                onChanged: (value) {
                  setState(() {
                    _settingsManager.volumeBoost = value;
                  });
                },
              ),
              Text('Warning: High values may damage speakers'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDarkModeItem() {
    return ListTile(
      leading: Icon(Icons.dark_mode, color: _settingsManager.themeColor),
      title: Text('Dark Mode', style: TextStyle(fontWeight: FontWeight.w500)),
      trailing: Switch(
        value: _settingsManager.isDarkMode,
        activeColor: _settingsManager.themeColor,
        onChanged: (value) {
          setState(() {
            _settingsManager.toggleDarkMode();
          });
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
                  onTap: () {
                    setState(() {
                      _settingsManager.setThemeColor(color);
                    });
                    widget.onThemeChanged?.call();
                    Navigator.pop(context);
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
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Recently Played',
          style: TextStyle(
            color: Colors.black,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: isLoading
        ? Center(child: CircularProgressIndicator(color: Color(0xFF10B981)))
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
                      color: Colors.grey[600],
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
                      color: Color(0xFF10B981),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.music_note,
                      color: Colors.white,
                    ),
                  ),
                  title: Text(
                    fileName,
                    style: TextStyle(fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    'Recently played',
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
                  trailing: IconButton(
                    icon: Icon(Icons.play_arrow, color: Color(0xFF10B981)),
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
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Favorites',
          style: TextStyle(
            color: Colors.black,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: isLoading
        ? Center(child: CircularProgressIndicator(color: Color(0xFF10B981)))
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
                      color: Colors.grey[600],
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Tap the heart icon to add songs to favorites',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[500],
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
                      color: Color(0xFF10B981),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.music_note,
                      color: Colors.white,
                    ),
                  ),
                  title: Text(
                    fileName,
                    style: TextStyle(fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    'Favorite song',
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
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
                        icon: Icon(Icons.play_arrow, color: Color(0xFF10B981)),
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