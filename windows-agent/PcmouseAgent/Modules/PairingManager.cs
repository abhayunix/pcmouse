using System;
using System.Security.Cryptography;
using System.Text;

namespace PcmouseAgent.Modules
{
    public class PairingSession
    {
        public string PairingCode { get; set; } = string.Empty;
        public string SessionToken { get; set; } = string.Empty;
        public DateTime ExpiryTime { get; set; }
        public bool IsPaired { get; set; }
    }

    public class PairingManager
    {
        private PairingSession? _currentSession;

        /// <summary>
        /// Generate a new 6-digit pairing code and session token
        /// </summary>
        public PairingSession GenerateNewPairingCode(int validMinutes = 10)
        {
            byte[] randomNumber = new byte[4];
            using var rng = RandomNumberGenerator.Create();
            rng.GetBytes(randomNumber);

            uint val = BitConverter.ToUInt32(randomNumber, 0) % 1000000;
            string code = val.ToString("D6");

            byte[] tokenBytes = new byte[32];
            rng.GetBytes(tokenBytes);
            string token = Convert.ToHexString(tokenBytes);

            _currentSession = new PairingSession
            {
                PairingCode = code,
                SessionToken = token,
                ExpiryTime = DateTime.UtcNow.AddMinutes(validMinutes),
                IsPaired = false
            };

            return _currentSession;
        }

        /// <summary>
        /// Validate candidate pairing code
        /// </summary>
        public bool ValidatePairingCode(string inputCode, out string sessionToken)
        {
            sessionToken = string.Empty;

            if (_currentSession == null) return false;
            if (DateTime.UtcNow > _currentSession.ExpiryTime) return false;

            if (string.Equals(_currentSession.PairingCode, inputCode?.Trim(), StringComparison.Ordinal))
            {
                _currentSession.IsPaired = true;
                sessionToken = _currentSession.SessionToken;
                return true;
            }

            return false;
        }

        public PairingSession? GetCurrentSession() => _currentSession;
    }
}
