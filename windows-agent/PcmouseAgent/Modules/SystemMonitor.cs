using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;

namespace PcmouseAgent.Modules
{
    public class SystemMetrics
    {
        public float CpuUsagePercent { get; set; }
        public long RamTotalMb { get; set; }
        public long RamUsedMb { get; set; }
        public float RamUsagePercent { get; set; }
        public List<DiskMetric> Disks { get; set; } = new List<DiskMetric>();
        public int BatteryPercent { get; set; }
        public bool IsCharging { get; set; }
        public long UptimeSeconds { get; set; }
    }

    public class DiskMetric
    {
        public string Name { get; set; } = string.Empty;
        public long TotalGb { get; set; }
        public long FreeGb { get; set; }
        public long UsedGb { get; set; }
        public float UsagePercent { get; set; }
    }

    public class SystemMonitor
    {
        #region Win32 P/Invoke Definitions

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool GetSystemPowerStatus(out SYSTEM_POWER_STATUS lpSystemPowerStatus);

        [StructLayout(LayoutKind.Sequential)]
        private struct SYSTEM_POWER_STATUS
        {
            public byte ACLineStatus;
            public byte BatteryFlag;
            public byte BatteryLifePercent;
            public byte SystemStatusFlag;
            public uint BatteryLifeTime;
            public uint BatteryFullLifeTime;
        }

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
        private class MEMORYSTATUSEX
        {
            public uint dwLength;
            public uint dwMemoryLoad;
            public ulong ullTotalPhys;
            public ulong ullAvailPhys;
            public ulong ullTotalPageFile;
            public ulong ullAvailPageFile;
            public ulong ullTotalVirtual;
            public ulong ullAvailVirtual;
            public ulong ullAvailExtendedVirtual;

            public MEMORYSTATUSEX()
            {
                dwLength = (uint)Marshal.SizeOf(typeof(MEMORYSTATUSEX));
            }
        }

        [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool GlobalMemoryStatusEx([In, Out] MEMORYSTATUSEX lpBuffer);

        #endregion

        private PerformanceCounter? _cpuCounter;

        public SystemMonitor()
        {
            try
            {
                _cpuCounter = new PerformanceCounter("Processor", "% Processor Time", "_Total");
                _cpuCounter.NextValue(); // Initial call reads baseline
            }
            catch (Exception ex)
            {
                Debug.WriteLine($"PerformanceCounter init warning: {ex.Message}");
            }
        }

        /// <summary>
        /// Get complete current system metrics snapshot matching Windows Task Manager
        /// </summary>
        public SystemMetrics GetMetrics()
        {
            var metrics = new SystemMetrics();

            // 1. CPU Usage
            try
            {
                metrics.CpuUsagePercent = _cpuCounter != null ? (float)Math.Round(_cpuCounter.NextValue(), 1) : 0.0f;
            }
            catch
            {
                metrics.CpuUsagePercent = 0.0f;
            }

            // 2. Real-time System-wide RAM Usage via GlobalMemoryStatusEx
            try
            {
                var memStatus = new MEMORYSTATUSEX();
                if (GlobalMemoryStatusEx(memStatus))
                {
                    metrics.RamTotalMb = (long)(memStatus.ullTotalPhys / (1024 * 1024));
                    long availMb = (long)(memStatus.ullAvailPhys / (1024 * 1024));
                    metrics.RamUsedMb = metrics.RamTotalMb - availMb;
                    metrics.RamUsagePercent = (float)memStatus.dwMemoryLoad;
                }
            }
            catch (Exception ex)
            {
                Debug.WriteLine($"RAM metrics error: {ex.Message}");
            }

            // 3. Disk Drives
            try
            {
                foreach (var drive in DriveInfo.GetDrives())
                {
                    if (drive.IsReady && (drive.DriveType == DriveType.Fixed || drive.DriveType == DriveType.Removable))
                    {
                        long totalGb = drive.TotalSize / (1024 * 1024 * 1024);
                        long freeGb = drive.AvailableFreeSpace / (1024 * 1024 * 1024);
                        long usedGb = totalGb - freeGb;
                        float pct = totalGb > 0 ? (float)Math.Round((double)usedGb / totalGb * 100.0, 1) : 0.0f;

                        metrics.Disks.Add(new DiskMetric
                        {
                            Name = drive.Name,
                            TotalGb = totalGb,
                            FreeGb = freeGb,
                            UsedGb = usedGb,
                            UsagePercent = pct
                        });
                    }
                }
            }
            catch (Exception ex)
            {
                Debug.WriteLine($"Disk metrics error: {ex.Message}");
            }

            // 4. Battery Status
            try
            {
                if (GetSystemPowerStatus(out SYSTEM_POWER_STATUS status))
                {
                    metrics.BatteryPercent = status.BatteryLifePercent != 255 ? status.BatteryLifePercent : 100;
                    metrics.IsCharging = status.ACLineStatus == 1;
                }
            }
            catch
            {
                metrics.BatteryPercent = 100;
                metrics.IsCharging = true;
            }

            // 5. System Uptime
            metrics.UptimeSeconds = Environment.TickCount64 / 1000;

            return metrics;
        }
    }
}
