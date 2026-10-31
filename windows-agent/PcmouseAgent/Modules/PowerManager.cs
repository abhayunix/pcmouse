using System;
using System.Diagnostics;
using System.Runtime.InteropServices;

namespace PcmouseAgent.Modules
{
    public class PowerManager
    {
        #region Win32 P/Invoke Definitions

        [DllImport("user32.dll", SetLastError = true)]
        private static extern bool LockWorkStation();

        [DllImport("powrprof.dll", SetLastError = true)]
        private static extern bool SetSuspendState(bool hibernate, bool forceCritical, bool disableWakeEvent);

        #endregion

        /// <summary>
        /// Shutdown computer immediately
        /// </summary>
        public bool Shutdown(bool force = false)
        {
            try
            {
                string args = force ? "/s /f /t 0" : "/s /t 0";
                Process.Start(new ProcessStartInfo("shutdown.exe", args)
                {
                    CreateNoWindow = true,
                    UseShellExecute = false
                });
                return true;
            }
            catch (Exception ex)
            {
                Debug.WriteLine($"Shutdown error: {ex.Message}");
                return false;
            }
        }

        /// <summary>
        /// Restart computer immediately
        /// </summary>
        public bool Restart(bool force = false)
        {
            try
            {
                string args = force ? "/r /f /t 0" : "/r /t 0";
                Process.Start(new ProcessStartInfo("shutdown.exe", args)
                {
                    CreateNoWindow = true,
                    UseShellExecute = false
                });
                return true;
            }
            catch (Exception ex)
            {
                Debug.WriteLine($"Restart error: {ex.Message}");
                return false;
            }
        }

        /// <summary>
        /// Lock active Windows user session
        /// </summary>
        public bool Lock()
        {
            try
            {
                return LockWorkStation();
            }
            catch (Exception ex)
            {
                Debug.WriteLine($"Lock error: {ex.Message}");
                return false;
            }
        }

        /// <summary>
        /// Put computer into Sleep / Standby state
        /// </summary>
        public bool Sleep()
        {
            try
            {
                return SetSuspendState(hibernate: false, forceCritical: false, disableWakeEvent: false);
            }
            catch (Exception ex)
            {
                Debug.WriteLine($"Sleep error: {ex.Message}");
                return false;
            }
        }
    }
}
