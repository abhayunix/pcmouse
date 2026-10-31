using System;
using System.IO;
using System.Net.Sockets;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using InTheHand.Net.Bluetooth;
using InTheHand.Net.Sockets;

namespace PcmouseAgent.Modules
{
    public class BluetoothManager
    {
        private readonly ConnectionManager _connectionManager;
        private BluetoothListener? _listener;
        private CancellationTokenSource? _cts;

        public bool IsListening { get; private set; }

        public BluetoothManager(ConnectionManager connectionManager)
        {
            _connectionManager = connectionManager;
        }

        /// <summary>
        /// Start Bluetooth Classic RFCOMM / Serial Port Profile (SPP) socket listener
        /// </summary>
        public void StartListener()
        {
            if (IsListening) return;

            try
            {
                _listener = new BluetoothListener(BluetoothService.SerialPort);
                _listener.Start();

                _cts = new CancellationTokenSource();
                IsListening = true;

                _connectionManager.Security.LogAudit("Bluetooth Classic RFCOMM listener started.");

                Task.Run(() => AcceptBluetoothClientsLoop(_cts.Token));
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"BluetoothListener start warning: {ex.Message}");
                _connectionManager.Security.LogAudit($"Bluetooth Listener unavailable: {ex.Message}");
            }
        }

        private async Task AcceptBluetoothClientsLoop(CancellationToken token)
        {
            while (!token.IsCancellationRequested && _listener != null)
            {
                try
                {
                    BluetoothClient client = await Task.Run(() => _listener.AcceptBluetoothClient(), token);
                    _connectionManager.Security.LogAudit($"Bluetooth client connected: {client.RemoteMachineName}");
                    _connectionManager.SetState(AgentConnectionState.Connected);

                    _ = Task.Run(() => HandleBluetoothClientSession(client, token), token);
                }
                catch (OperationCanceledException)
                {
                    break;
                }
                catch (Exception ex)
                {
                    System.Diagnostics.Debug.WriteLine($"Bluetooth accept error: {ex.Message}");
                }
            }
        }

        private void HandleBluetoothClientSession(BluetoothClient client, CancellationToken token)
        {
            try
            {
                using var stream = client.GetStream();
                using var reader = new StreamReader(stream, Encoding.UTF8);
                using var writer = new StreamWriter(stream, Encoding.UTF8) { AutoFlush = true };

                while (!token.IsCancellationRequested && client.Connected)
                {
                    string? line = reader.ReadLine();
                    if (string.IsNullOrEmpty(line)) break;

                    string? response = _connectionManager.ProcessIncomingFrame(line, client.RemoteMachineName);
                    if (!string.IsNullOrEmpty(response))
                    {
                        writer.WriteLine(response);
                    }
                }
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"Bluetooth session error: {ex.Message}");
            }
            finally
            {
                client.Close();
                _connectionManager.Security.LogAudit("Bluetooth client disconnected.");
            }
        }

        /// <summary>
        /// Stop Bluetooth listener
        /// </summary>
        public void StopListener()
        {
            if (!IsListening) return;

            try
            {
                _cts?.Cancel();
                _listener?.Stop();
                IsListening = false;
                _connectionManager.Security.LogAudit("Bluetooth RFCOMM listener stopped.");
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"Bluetooth stop error: {ex.Message}");
            }
        }
    }
}
