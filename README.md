# Music Player App

A beautiful local music player built with Flutter that provides an elegant interface for playing your local music files.

## Features

### Core Functionality
- **Local Music Playback**: Play audio files from your device storage
- **Album Art Display**: Automatically extracts and displays album artwork from music files
- **Playlist Management**: Create, edit, and manage custom playlists
- **Shuffle & Repeat**: Shuffle playback and automatic playlist looping
- **Favorites**: Mark songs as favorites for quick access

### User Interface
- **Beautiful Now Playing Screen**: Vinyl-style rotating album art with smooth animations
- **Dark/Light Mode**: Theme support with user preference persistence
- **Progress Control**: Seek through tracks with visual progress indicators
- **Responsive Design**: Optimized for different screen sizes

### Audio Controls
- **Play/Pause/Skip**: Full media control functionality
- **Previous/Next**: Navigate through playlist or shuffled tracks
- **Position Tracking**: Real-time playback position updates
- **Duration Display**: Shows current position and total track length

## Technical Details

### Dependencies
- **just_audio**: High-quality audio playback
- **audiotags**: Extract metadata and album art from audio files
- **hive_flutter**: Local data persistence and caching
- **permission_handler**: Handle device storage permissions
- **audio_session**: Proper audio session management

### Architecture
- **Cached Song Management**: Efficient caching system for song metadata
- **Playlist Persistence**: Playlists saved locally with Hive database
- **Settings Management**: User preferences and theme settings
- **Background Playback**: Continues playing when app is backgrounded

## Getting Started

### Prerequisites
- Flutter SDK (>=3.0.0)
- Dart SDK (>=2.19.0)

### Installation
1. Clone the repository:
   ```bash
   git clone https://github.com/rianphlox/music_app.git
   cd music_app
   ```

2. Install dependencies:
   ```bash
   flutter pub get
   ```

3. Run the app:
   ```bash
   flutter run
   ```

### Permissions
The app requires storage permissions to access local music files. Permissions are handled automatically on first launch.

## Usage

1. **First Launch**: Grant storage permissions when prompted
2. **Browse Music**: The app automatically scans for music files on your device
3. **Create Playlists**: Organize your music into custom playlists
4. **Now Playing**: Tap any song to open the beautiful now playing screen with album art
5. **Controls**: Use the bottom controls for playback management

## Features in Detail

### Album Art
- Automatically extracts embedded album artwork from music files
- Displays as rotating vinyl record animation during playback
- Falls back to themed gradient when no artwork is available

### Playlist Looping
- When reaching the end of a playlist, automatically loops back to the beginning
- Works with both normal and shuffle playback modes
- Seamless transition between tracks

### Theme Support
- Dark and light mode support
- Customizable theme colors
- Persistent user preference settings

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## License

This project is open source and available under the MIT License.

## Author

Created with ❤️ using Flutter
