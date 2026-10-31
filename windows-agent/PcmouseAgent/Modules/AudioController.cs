using System;
using NAudio.CoreAudioApi;

namespace PcmouseAgent.Modules
{
    public class AudioController
    {
        private MMDeviceEnumerator? _enumerator;
        private MMDevice? _audioDevice;

        public AudioController()
        {
            try
            {
                _enumerator = new MMDeviceEnumerator();
                _audioDevice = _enumerator.GetDefaultAudioEndpoint(DataFlow.Render, Role.Multimedia);
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"AudioController init error: {ex.Message}");
            }
        }

        /// <summary>
        /// Get current master volume scalar (0.0 to 1.0)
        /// </summary>
        public float GetVolume()
        {
            try
            {
                return _audioDevice?.AudioEndpointVolume?.MasterVolumeLevelScalar ?? 0.0f;
            }
            catch
            {
                return 0.0f;
            }
        }

        /// <summary>
        /// Set master volume scalar (0.0 to 1.0)
        /// </summary>
        public void SetVolume(float level)
        {
            try
            {
                if (_audioDevice?.AudioEndpointVolume != null)
                {
                    level = Math.Clamp(level, 0.0f, 1.0f);
                    _audioDevice.AudioEndpointVolume.MasterVolumeLevelScalar = level;
                }
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"SetVolume error: {ex.Message}");
            }
        }

        /// <summary>
        /// Get current mute state
        /// </summary>
        public bool IsMuted()
        {
            try
            {
                return _audioDevice?.AudioEndpointVolume?.Mute ?? false;
            }
            catch
            {
                return false;
            }
        }

        /// <summary>
        /// Set mute state
        /// </summary>
        public void SetMute(bool mute)
        {
            try
            {
                if (_audioDevice?.AudioEndpointVolume != null)
                {
                    _audioDevice.AudioEndpointVolume.Mute = mute;
                }
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"SetMute error: {ex.Message}");
            }
        }

        /// <summary>
        /// Toggle mute state
        /// </summary>
        public bool ToggleMute()
        {
            bool newMuteState = !IsMuted();
            SetMute(newMuteState);
            return newMuteState;
        }

        /// <summary>
        /// Step volume up or down by step percentage (default 5%)
        /// </summary>
        public float AdjustVolume(float stepDelta)
        {
            float current = GetVolume();
            float target = current + stepDelta;
            SetVolume(target);
            return GetVolume();
        }
    }
}
