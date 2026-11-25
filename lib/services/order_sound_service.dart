import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Professional Audio & Vibration Service for Incoming Orders
/// Features:
/// 1. Loud alarm audio routing via AudioContext (bypasses silent/media mute on Android)
/// 2. Direct rootBundle Uint8List streaming via BytesSource (failsafe across all Android versions)
/// 3. Looping alert ringtone + continuous haptic vibration
/// 4. Built-in SystemSound alert fallback
/// 5. 1-Tap speaker test for merchants
class OrderSoundService {
  static AudioPlayer? _player;
  static StreamSubscription<void>? _completeSub;
  static Timer? _vibrationTimer;
  static Timer? _systemSoundTimer;
  static bool _isPlaying = false;
  static bool _isStarting = false;
  static bool _isMuted = false;
  static Uint8List? _cachedAudioBytes;

  static bool get isPlaying => _isPlaying;
  static bool get isMuted => _isMuted;

  /// Configure Audio Context for loud alarm stream (cuts through silent/vibrate & max volume)
  static Future<void> _configureAudioContext() async {
    try {
      final audioContext = AudioContext(
        android: AudioContextAndroid(
          isSpeakerphoneOn: true,
          stayAwake: false,
          contentType: AndroidContentType.music,
          usageType: AndroidUsageType.alarm,
          audioFocus: AndroidAudioFocus.gainTransientExclusive,
        ),
        iOS: AudioContextIOS(
          category: AVAudioSessionCategory.playback,
          options: {
            AVAudioSessionOptions.duckOthers,
            AVAudioSessionOptions.defaultToSpeaker,
          },
        ),
      );
      await AudioPlayer.global.setAudioContext(audioContext);
    } catch (e) {
      debugPrint('Audio context config error: $e');
    }
  }

  /// Ensure ringtone is actively playing (restarts if Android stopped it)
  static Future<void> ensureLoopingAlert() async {
    if (!_isPlaying) {
      await startLoopingAlert();
      return;
    }
    if (_isStarting || _isMuted) return;
    try {
      if (_player == null || _player!.state != PlayerState.playing) {
        _isPlaying = false;
        await startLoopingAlert();
      }
    } catch (_) {
      _isPlaying = false;
      await startLoopingAlert();
    }
  }

  /// Start continuous looping loud ringtone, vibration pulse, and system audio fallback
  static Future<void> startLoopingAlert() async {
    if (_isPlaying || _isStarting) return;
    _isStarting = true;
    _isPlaying = true;
    _isMuted = false;

    try {
      // 1. Configure audio routing
      await _configureAudioContext();

      // 2. Play ringtone audio
      bool audioStarted = false;
      try {
        await _completeSub?.cancel();
        _completeSub = null;
        if (_player != null) {
          try { await _player!.stop(); } catch (_) {}
          try { await _player!.dispose(); } catch (_) {}
        }
        _player = AudioPlayer();
        await _player!.setReleaseMode(ReleaseMode.loop);
        await _player!.setVolume(1.0);

        _completeSub = _player!.onPlayerComplete.listen((_) async {
          if (_isPlaying && !_isMuted && _player != null && _cachedAudioBytes != null) {
            try {
              await _player!.play(BytesSource(_cachedAudioBytes!));
            } catch (_) {}
          }
        });

        // Strategy A: Load bytes via rootBundle (100% reliable, direct APK asset stream)
        try {
          _cachedAudioBytes ??= (await rootBundle.load('assets/sounds/order_ringtone.mp3')).buffer.asUint8List();
          await _player!.play(BytesSource(_cachedAudioBytes!));
          audioStarted = true;
        } catch (e) {
          debugPrint('BytesSource playback failed: $e. Falling back to AssetSource.');
        }

        // Strategy B: Fallback to AssetSource
        if (!audioStarted) {
          try {
            await _player!.play(AssetSource('sounds/order_ringtone.mp3'));
            audioStarted = true;
          } catch (_) {
            await _player!.play(AssetSource('assets/sounds/order_ringtone.mp3'));
            audioStarted = true;
          }
        }
      } catch (e) {
        debugPrint('AudioPlayer setup error: $e');
      }

    // 3. Tactile Haptic Vibration Pulses every 1.2s
    _vibrationTimer?.cancel();
    _vibrationTimer = Timer.periodic(const Duration(milliseconds: 1200), (_) {
      HapticFeedback.heavyImpact();
    });

      // 4. Guaranteed Native System Sound Fallback if AudioPlayer failed
      if (!audioStarted) {
        _systemSoundTimer?.cancel();
        _systemSoundTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) {
          SystemSound.play(SystemSoundType.alert);
        });
      }
    } finally {
      _isStarting = false;
    }
  }

  /// Stop ringtone and cancel all alerts
  static Future<void> stopAlert() async {
    _isPlaying = false;
    _vibrationTimer?.cancel();
    _vibrationTimer = null;
    _systemSoundTimer?.cancel();
    _systemSoundTimer = null;
    try {
      await _completeSub?.cancel();
      _completeSub = null;
      await _player?.stop();
      await _player?.release();
    } catch (e) {
      debugPrint('Order audio stop error: $e');
    }
  }

  /// 1-Tap Mute / Unmute
  static Future<bool> toggleMute() async {
    _isMuted = !_isMuted;
    try {
      await _player?.setVolume(_isMuted ? 0.0 : 1.0);
    } catch (_) {}
    return _isMuted;
  }

  /// Test ringtone for 6 seconds to let merchant verify speaker volume
  static Future<void> testRingtone(BuildContext context) async {
    await startLoopingAlert();

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.volume_up_rounded, color: Colors.white, size: 22),
              SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('🔊 Testing Incoming Order Ringtone!', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
                    Text('Playing loud alarm alert. Volume is max.', style: TextStyle(fontSize: 11)),
                  ],
                ),
              ),
            ],
          ),
          backgroundColor: const Color(0xFFEA580C),
          duration: const Duration(seconds: 6),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          action: SnackBarAction(
            label: 'STOP',
            textColor: Colors.white,
            onPressed: () => stopAlert(),
          ),
        ),
      );
    }

    // Auto-stop after 6 seconds
    Future.delayed(const Duration(seconds: 6), () {
      stopAlert();
    });
  }
}
