using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Diagnostics;
using Newtonsoft.Json.Linq;

namespace PcmouseAgent.Modules
{
    public class SecurityManager
    {
        private readonly HashSet<string> _authenticatedTokens = new HashSet<string>();
        private readonly ConcurrentQueue<string> _auditLogs = new ConcurrentQueue<string>();
        private const int MaxAuditLogs = 500;

        // Rate limiter tracking: IP -> Timestamp list
        private readonly ConcurrentDictionary<string, List<DateTime>> _rateLimiter = new ConcurrentDictionary<string, List<DateTime>>();
        private const int MaxEventsPerSecond = 120; // Allow fast mouse deltas up to 120Hz

        /// <summary>
        /// Register an authorized session token
        /// </summary>
        public void AuthorizeToken(string token)
        {
            if (!string.IsNullOrEmpty(token))
            {
                lock (_authenticatedTokens)
                {
                    _authenticatedTokens.Add(token);
                }
                LogAudit($"Session token authorized: {token.Substring(0, Math.Min(8, token.Length))}...");
            }
        }

        /// <summary>
        /// Check if token is authorized
        /// </summary>
        public bool IsTokenAuthorized(string token)
        {
            if (string.IsNullOrEmpty(token)) return false;
            lock (_authenticatedTokens)
            {
                return _authenticatedTokens.Contains(token);
            }
        }

        /// <summary>
        /// Revoke a session token
        /// </summary>
        public void RevokeToken(string token)
        {
            lock (_authenticatedTokens)
            {
                _authenticatedTokens.Remove(token);
            }
            LogAudit("Session token revoked.");
        }

        /// <summary>
        /// Validate packet structure and ensure type is whitelisted
        /// </summary>
        public bool ValidatePacketType(string messageType)
        {
            var whitelistedTypes = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
            {
                "HANDSHAKE_REQ",
                "AUTH_REQ",
                "MOUSE_EVENT",
                "KEYBOARD_EVENT",
                "SYSTEM_COMMAND",
                "VOLUME_COMMAND",
                "FILE_TRANSFER_START",
                "FILE_TRANSFER_CHUNK",
                "FILE_TRANSFER_COMPLETE",
                "FILE_TRANSFER_CANCEL",
                "SYSTEM_METRICS_REQ",
                "PROCESS_LIST_REQ",
                "PROCESS_CONTROL_CMD"
            };

            return whitelistedTypes.Contains(messageType);
        }

        /// <summary>
        /// Enforce rate limiting per client IP
        /// </summary>
        public bool AllowRequest(string clientIp)
        {
            var now = DateTime.UtcNow;
            var windowStart = now.AddSeconds(-1);

            var timestamps = _rateLimiter.GetOrAdd(clientIp, _ => new List<DateTime>());

            lock (timestamps)
            {
                timestamps.RemoveAll(t => t < windowStart);
                if (timestamps.Count >= MaxEventsPerSecond)
                {
                    LogAudit($"Rate limit exceeded for IP: {clientIp}");
                    return false;
                }
                timestamps.Add(now);
                return true;
            }
        }

        /// <summary>
        /// Record audit log entry
        /// </summary>
        public void LogAudit(string message)
        {
            string entry = $"[{DateTime.Now:yyyy-MM-dd HH:mm:ss}] {message}";
            _auditLogs.Enqueue(entry);
            Debug.WriteLine(entry);

            while (_auditLogs.Count > MaxAuditLogs)
            {
                _auditLogs.TryDequeue(out _);
            }
        }

        public IEnumerable<string> GetAuditLogs() => _auditLogs.ToArray();
    }
}
