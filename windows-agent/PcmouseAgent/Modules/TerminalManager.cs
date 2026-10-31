using System;
using System.Diagnostics;
using System.Text;

namespace PcmouseAgent.Modules
{
    public class TerminalManager
    {
        /// <summary>
        /// Execute PowerShell or CMD command asynchronously on Windows PC without stream deadlocks
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
                    psi.Arguments = $"/c \"{command}\"";
                }
                else
                {
                    psi.FileName = "powershell.exe";
                    psi.Arguments = $"-NoProfile -NonInteractive -ExecutionPolicy Bypass -Command \"{command.Replace("\"", "\\\"")}\"";
                }

                psi.RedirectStandardOutput = true;
                psi.RedirectStandardError = true;
                psi.StandardOutputEncoding = Encoding.UTF8;
                psi.StandardErrorEncoding = Encoding.UTF8;
                psi.UseShellExecute = false;
                psi.CreateNoWindow = true;

                StringBuilder stdoutBuilder = new StringBuilder();
                StringBuilder stderrBuilder = new StringBuilder();

                using Process proc = new Process { StartInfo = psi };

                proc.OutputDataReceived += (sender, e) =>
                {
                    if (e.Data != null)
                    {
                        stdoutBuilder.AppendLine(e.Data);
                    }
                };

                proc.ErrorDataReceived += (sender, e) =>
                {
                    if (e.Data != null)
                    {
                        stderrBuilder.AppendLine(e.Data);
                    }
                };

                proc.Start();
                proc.BeginOutputReadLine();
                proc.BeginErrorReadLine();

                bool exited = proc.WaitForExit(10000); // 10 second timeout

                if (!exited)
                {
                    try { proc.Kill(true); } catch { }
                    return "[TIMEOUT ERROR]: Command execution timed out (10s limit).";
                }

                StringBuilder finalResult = new StringBuilder();
                if (stdoutBuilder.Length > 0)
                {
                    finalResult.AppendLine(stdoutBuilder.ToString().TrimEnd());
                }

                if (stderrBuilder.Length > 0)
                {
                    if (finalResult.Length > 0) finalResult.AppendLine("\n--- STDERR ---");
                    finalResult.AppendLine(stderrBuilder.ToString().TrimEnd());
                }

                return finalResult.Length > 0 ? finalResult.ToString() : "Command executed successfully (no output).";
            }
            catch (Exception ex)
            {
                return $"[EXECUTION ERROR]: {ex.Message}";
            }
        }
    }
}
