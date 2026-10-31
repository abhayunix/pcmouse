using System;
using System.Diagnostics;
using System.Text;

namespace PcmouseAgent.Modules
{
    public class TerminalManager
    {
        /// <summary>
        /// Execute PowerShell or CMD command on Windows PC and return stdout/stderr
        /// </summary>
        public string ExecuteCommand(string command, string shell = "powershell")
        {
            if (string.IsNullOrWhiteSpace(command))
            {
                return "Empty command.";
            }

            try
            {
                ProcessStartInfo psi = new ProcessStartInfo();
                if (shell.Equals("cmd", StringComparison.OrdinalIgnoreCase))
                {
                    psi.FileName = "cmd.exe";
                    psi.Arguments = $"/c {command}";
                }
                else
                {
                    psi.FileName = "powershell.exe";
                    psi.Arguments = $"-NoProfile -ExecutionPolicy Bypass -Command \"{command}\"";
                }

                psi.RedirectStandardOutput = true;
                psi.RedirectStandardError = true;
                psi.UseShellExecute = false;
                psi.CreateNoWindow = true;

                using Process proc = new Process { StartInfo = psi };
                StringBuilder output = new StringBuilder();

                proc.Start();
                string stdout = proc.StandardOutput.ReadToEnd();
                string stderr = proc.StandardError.ReadToEnd();
                bool exited = proc.WaitForExit(10000); // 10s execution timeout

                if (!exited)
                {
                    try { proc.Kill(); } catch { }
                    return "[ERROR]: Command execution timed out (10s limit).";
                }

                if (!string.IsNullOrEmpty(stdout))
                {
                    output.AppendLine(stdout);
                }

                if (!string.IsNullOrEmpty(stderr))
                {
                    output.AppendLine($"[ERROR OUTPUT]:\n{stderr}");
                }

                return output.Length > 0 ? output.ToString().TrimEnd() : "Command executed successfully (no output).";
            }
            catch (Exception ex)
            {
                return $"[EXECUTION ERROR]: {ex.Message}";
            }
        }
    }
}
