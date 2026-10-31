using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;

namespace PcmouseAgent.Modules
{
    public class ProcessInfo
    {
        public int Id { get; set; }
        public string Name { get; set; } = string.Empty;
        public string WindowTitle { get; set; } = string.Empty;
        public long MemoryMb { get; set; }
        public bool IsResponding { get; set; }
    }

    public class ProcessManager
    {
        /// <summary>
        /// Retrieve list of all running applications with active window titles
        /// </summary>
        public List<ProcessInfo> GetRunningProcesses(bool onlyWithWindow = true)
        {
            List<ProcessInfo> result = new List<ProcessInfo>();

            try
            {
                var processes = Process.GetProcesses();

                foreach (var p in processes)
                {
                    try
                    {
                        if (onlyWithWindow && string.IsNullOrWhiteSpace(p.MainWindowTitle))
                        {
                            continue;
                        }

                        result.Add(new ProcessInfo
                        {
                            Id = p.Id,
                            Name = p.ProcessName,
                            WindowTitle = p.MainWindowTitle,
                            MemoryMb = p.WorkingSet64 / (1024 * 1024),
                            IsResponding = p.Responding
                        });
                    }
                    catch
                    {
                        // Ignore system or protected processes where access is denied
                    }
                }
            }
            catch (Exception ex)
            {
                Debug.WriteLine($"GetRunningProcesses error: {ex.Message}");
            }

            return result.OrderBy(x => x.Name).ToList();
        }

        /// <summary>
        /// Launch an approved executable path or application
        /// </summary>
        public bool LaunchProcess(string fileName, string? arguments = null)
        {
            try
            {
                var psi = new ProcessStartInfo
                {
                    FileName = fileName,
                    Arguments = arguments ?? string.Empty,
                    UseShellExecute = true
                };

                Process.Start(psi);
                return true;
            }
            catch (Exception ex)
            {
                Debug.WriteLine($"LaunchProcess error ({fileName}): {ex.Message}");
                return false;
            }
        }

        /// <summary>
        /// Kill running process by PID
        /// </summary>
        public bool KillProcess(int processId)
        {
            try
            {
                var p = Process.GetProcessById(processId);
                p.Kill(entireProcessTree: true);
                return true;
            }
            catch (Exception ex)
            {
                Debug.WriteLine($"KillProcess error (PID {processId}): {ex.Message}");
                return false;
            }
        }
    }
}
