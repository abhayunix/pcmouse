using System;
using System.Collections.Generic;
using System.Diagnostics;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using Newtonsoft.Json.Serialization;

namespace PcmouseAgent.Modules
{
    public enum AgentConnectionState
    {
        Disconnected,
        Discovering,
        Pairing,
        Connecting,
        Authenticating,
        Connected,
        Reconnecting,
        Failed
    }

    public class ConnectionManager
    {
        private static readonly JsonSerializerSettings CamelCaseSettings = new JsonSerializerSettings
        {
            ContractResolver = new CamelCasePropertyNamesContractResolver()
        };

        public AgentConnectionState State { get; private set; } = AgentConnectionState.Disconnected;

        // Subsystems
        public MouseController Mouse { get; } = new MouseController();
        public KeyboardController Keyboard { get; } = new KeyboardController();
        public AudioController Audio { get; } = new AudioController();
        public PowerManager Power { get; } = new PowerManager();
        public SystemMonitor Monitor { get; } = new SystemMonitor();
        public ProcessManager Processes { get; } = new ProcessManager();
        public FileManager Files { get; } = new FileManager();
        public ClipboardManager Clipboard { get; } = new ClipboardManager();
        public TerminalManager Terminal { get; } = new TerminalManager();
        public PairingManager Pairing { get; } = new PairingManager();
        public SecurityManager Security { get; } = new SecurityManager();

        // Events
        public event Action<AgentConnectionState>? StateChanged;
        public event Action<string>? LogMessage;

        public ConnectionManager()
        {
            SetState(AgentConnectionState.Disconnected);
        }

        public void SetState(AgentConnectionState newState)
        {
            if (State != newState)
            {
                State = newState;
                Security.LogAudit($"Connection state changed to: {newState}");
                StateChanged?.Invoke(newState);
            }
        }

        /// <summary>
        /// Process raw incoming JSON packet from any transport (WebSocket, Bluetooth, WebRTC)
        /// </summary>
        public string? ProcessIncomingFrame(string rawJson, string clientIp = "127.0.0.1")
        {
            try
            {
                if (!Security.AllowRequest(clientIp))
                {
                    return CreateErrorResponse("Rate limit exceeded");
                }

                var frame = JObject.Parse(rawJson);
                string msgId = frame["msgId"]?.ToString() ?? Guid.NewGuid().ToString();
                string type = frame["type"]?.ToString() ?? string.Empty;

                JObject payload = (JObject?)(frame["payload"]) ?? new JObject();

                // 1. Handshake & Pairing
                if (type.Equals("HANDSHAKE_REQ", StringComparison.OrdinalIgnoreCase))
                {
                    string code = payload["code"]?.ToString() ?? string.Empty;
                    if (Pairing.ValidatePairingCode(code, out string sessionToken))
                    {
                        Security.AuthorizeToken(sessionToken);
                        SetState(AgentConnectionState.Connected);
                        LogMessage?.Invoke($"Client ({clientIp}) paired successfully.");

                        return JsonConvert.SerializeObject(new
                        {
                            version = 1,
                            msgId,
                            type = "HANDSHAKE_RESP",
                            timestamp = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds(),
                            payload = new { success = true, token = sessionToken, message = "Pairing successful" }
                        }, CamelCaseSettings);
                    }
                    else
                    {
                        return CreateErrorResponse("Invalid pairing code", msgId);
                    }
                }

                // 2. Mouse Events
                if (type.Equals("MOUSE_EVENT", StringComparison.OrdinalIgnoreCase))
                {
                    HandleMouseEvent(payload);
                    return null;
                }

                // 3. Keyboard Events
                if (type.Equals("KEYBOARD_EVENT", StringComparison.OrdinalIgnoreCase))
                {
                    HandleKeyboardEvent(payload);
                    return null;
                }

                // 4. Volume Commands
                if (type.Equals("VOLUME_COMMAND", StringComparison.OrdinalIgnoreCase))
                {
                    HandleVolumeCommand(payload);
                    return null;
                }

                // 5. System Commands
                if (type.Equals("SYSTEM_COMMAND", StringComparison.OrdinalIgnoreCase))
                {
                    HandleSystemCommand(payload);
                    return null;
                }

                // 6. Terminal PowerShell & CMD Commands
                if (type.Equals("TERMINAL_CMD_REQ", StringComparison.OrdinalIgnoreCase))
                {
                    string cmd = payload["command"]?.ToString() ?? string.Empty;
                    string shell = payload["shell"]?.ToString() ?? "powershell";
                    string result = Terminal.ExecuteCommand(cmd, shell);
                    Security.LogAudit($"Executed {shell.ToUpper()} command remotely: {cmd}");

                    return JsonConvert.SerializeObject(new
                    {
                        version = 1,
                        msgId,
                        type = "TERMINAL_CMD_RESP",
                        timestamp = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds(),
                        payload = new { command = cmd, shell, result }
                    }, CamelCaseSettings);
                }

                // 7. System Metrics Request
                if (type.Equals("SYSTEM_METRICS_REQ", StringComparison.OrdinalIgnoreCase))
                {
                    var metrics = Monitor.GetMetrics();
                    return JsonConvert.SerializeObject(new
                    {
                        version = 1,
                        msgId,
                        type = "SYSTEM_METRICS_RESP",
                        timestamp = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds(),
                        payload = metrics
                    }, CamelCaseSettings);
                }

                // 8. Process List Request
                if (type.Equals("PROCESS_LIST_REQ", StringComparison.OrdinalIgnoreCase))
                {
                    var procs = Processes.GetRunningProcesses(onlyWithWindow: true);
                    return JsonConvert.SerializeObject(new
                    {
                        version = 1,
                        msgId,
                        type = "PROCESS_LIST_RESP",
                        timestamp = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds(),
                        payload = procs
                    }, CamelCaseSettings);
                }

                // 9. File System Enumeration
                if (type.Equals("FILE_LIST_REQ", StringComparison.OrdinalIgnoreCase))
                {
                    string path = payload["path"]?.ToString() ?? string.Empty;
                    var items = Files.ListDirectory(path);
                    return JsonConvert.SerializeObject(new
                    {
                        version = 1,
                        msgId,
                        type = "FILE_LIST_RESP",
                        timestamp = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds(),
                        payload = new { path, items }
                    }, CamelCaseSettings);
                }

                // 10. File Upload Start
                if (type.Equals("FILE_TRANSFER_START", StringComparison.OrdinalIgnoreCase))
                {
                    string name = payload["fileName"]?.ToString() ?? "file.dat";
                    string dest = payload["destFolder"]?.ToString() ?? string.Empty;
                    long size = payload["fileSizeBytes"]?.Value<long>() ?? 0;
                    string checksum = payload["checksum"]?.ToString() ?? string.Empty;

                    string id = Files.StartIncomingUpload(name, dest, size, checksum);
                    return JsonConvert.SerializeObject(new
                    {
                        version = 1,
                        msgId,
                        type = "FILE_TRANSFER_START_RESP",
                        timestamp = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds(),
                        payload = new { success = !string.IsNullOrEmpty(id), transferId = id }
                    }, CamelCaseSettings);
                }

                // 11. File Chunk
                if (type.Equals("FILE_TRANSFER_CHUNK", StringComparison.OrdinalIgnoreCase))
                {
                    string id = payload["transferId"]?.ToString() ?? string.Empty;
                    string chunk = payload["chunkBase64"]?.ToString() ?? string.Empty;
                    bool ok = Files.ProcessUploadChunk(id, chunk);

                    return JsonConvert.SerializeObject(new
                    {
                        version = 1,
                        msgId,
                        type = "FILE_TRANSFER_CHUNK_RESP",
                        timestamp = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds(),
                        payload = new { success = ok }
                    }, CamelCaseSettings);
                }

                // 12. File Complete
                if (type.Equals("FILE_TRANSFER_COMPLETE", StringComparison.OrdinalIgnoreCase))
                {
                    string id = payload["transferId"]?.ToString() ?? string.Empty;
                    bool ok = Files.CompleteUpload(id, out string finalPath);

                    return JsonConvert.SerializeObject(new
                    {
                        version = 1,
                        msgId,
                        type = "FILE_TRANSFER_COMPLETE_RESP",
                        timestamp = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds(),
                        payload = new { success = ok, finalPath }
                    }, CamelCaseSettings);
                }

                // 13. Cross-Device Shared Clipboard Sync
                if (type.Equals("CLIPBOARD_SET_REQ", StringComparison.OrdinalIgnoreCase))
                {
                    string text = payload["text"]?.ToString() ?? string.Empty;
                    bool ok = Clipboard.SetClipboardText(text);
                    Security.LogAudit($"Synced phone text ({text.Length} chars) to PC Clipboard.");

                    return JsonConvert.SerializeObject(new
                    {
                        version = 1,
                        msgId,
                        type = "CLIPBOARD_SET_RESP",
                        timestamp = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds(),
                        payload = new { success = ok }
                    }, CamelCaseSettings);
                }

                if (type.Equals("CLIPBOARD_GET_REQ", StringComparison.OrdinalIgnoreCase))
                {
                    string text = Clipboard.GetClipboardText();
                    return JsonConvert.SerializeObject(new
                    {
                        version = 1,
                        msgId,
                        type = "CLIPBOARD_GET_RESP",
                        timestamp = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds(),
                        payload = new { text }
                    }, CamelCaseSettings);
                }

                return null;
            }
            catch (Exception ex)
            {
                Debug.WriteLine($"ProcessIncomingFrame error: {ex.Message}");
                return CreateErrorResponse($"Frame processing error: {ex.Message}");
            }
        }

        private void HandleMouseEvent(JObject payload)
        {
            string action = payload["action"]?.ToString() ?? string.Empty;
            int dx = payload["dx"]?.Value<int>() ?? 0;
            int dy = payload["dy"]?.Value<int>() ?? 0;
            double normX = payload["absoluteX"]?.Value<double>() ?? -1.0;
            double normY = payload["absoluteY"]?.Value<double>() ?? -1.0;

            if (action.Equals("MOVE", StringComparison.OrdinalIgnoreCase))
            {
                if (normX >= 0.0 && normY >= 0.0)
                    Mouse.MoveAbsoluteNormalized(normX, normY);
                else
                    Mouse.MoveRelative(dx, dy);
            }
            else if (action.Equals("CLICK", StringComparison.OrdinalIgnoreCase))
            {
                Mouse.LeftClick();
            }
            else if (action.Equals("RIGHT_CLICK", StringComparison.OrdinalIgnoreCase))
            {
                Mouse.RightClick();
            }
            else if (action.Equals("SCROLL", StringComparison.OrdinalIgnoreCase))
            {
                int scrollY = payload["scrollDeltaY"]?.Value<int>() ?? 0;
                int scrollX = payload["scrollDeltaX"]?.Value<int>() ?? 0;
                Mouse.Scroll(scrollY, scrollX);
            }
            else if (action.Equals("BUTTON", StringComparison.OrdinalIgnoreCase))
            {
                string button = payload["button"]?.ToString() ?? "LEFT";
                bool isDown = payload["isDown"]?.Value<bool>() ?? false;
                Mouse.SetButtonState(button, isDown);
            }
        }

        private void HandleKeyboardEvent(JObject payload)
        {
            string action = payload["action"]?.ToString() ?? string.Empty;
            ushort vk = payload["keyCode"]?.Value<ushort>() ?? 0;
            string text = payload["text"]?.ToString() ?? string.Empty;

            if (action.Equals("TEXT", StringComparison.OrdinalIgnoreCase) && !string.IsNullOrEmpty(text))
            {
                Keyboard.SendText(text);
            }
            else if (action.Equals("KEY_PRESS", StringComparison.OrdinalIgnoreCase) && vk > 0)
            {
                Keyboard.PressVirtualKey(vk);
            }
            else if (action.Equals("KEY_DOWN", StringComparison.OrdinalIgnoreCase) && vk > 0)
            {
                Keyboard.SendVirtualKey(vk, isDown: true);
            }
            else if (action.Equals("KEY_UP", StringComparison.OrdinalIgnoreCase) && vk > 0)
            {
                Keyboard.SendVirtualKey(vk, isDown: false);
            }
        }

        private void HandleVolumeCommand(JObject payload)
        {
            string action = payload["action"]?.ToString() ?? string.Empty;

            if (action.Equals("SET_VOLUME", StringComparison.OrdinalIgnoreCase))
            {
                float level = payload["level"]?.Value<float>() ?? 0.5f;
                Audio.SetVolume(level);
            }
            else if (action.Equals("MUTE", StringComparison.OrdinalIgnoreCase))
            {
                Audio.SetMute(true);
            }
            else if (action.Equals("UNMUTE", StringComparison.OrdinalIgnoreCase))
            {
                Audio.SetMute(false);
            }
            else if (action.Equals("TOGGLE_MUTE", StringComparison.OrdinalIgnoreCase))
            {
                Audio.ToggleMute();
            }
        }

        private void HandleSystemCommand(JObject payload)
        {
            string action = payload["action"]?.ToString() ?? string.Empty;
            bool force = payload["force"]?.Value<bool>() ?? false;

            if (action.Equals("SHUTDOWN", StringComparison.OrdinalIgnoreCase))
            {
                Power.Shutdown(force);
            }
            else if (action.Equals("RESTART", StringComparison.OrdinalIgnoreCase))
            {
                Power.Restart(force);
            }
            else if (action.Equals("LOCK", StringComparison.OrdinalIgnoreCase))
            {
                Power.Lock();
            }
            else if (action.Equals("SLEEP", StringComparison.OrdinalIgnoreCase))
            {
                Power.Sleep();
            }
        }

        private string CreateErrorResponse(string message, string? msgId = null)
        {
            return JsonConvert.SerializeObject(new
            {
                version = 1,
                msgId = msgId ?? Guid.NewGuid().ToString(),
                type = "ERROR_RESP",
                timestamp = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds(),
                payload = new { message }
            }, CamelCaseSettings);
        }
    }
}
