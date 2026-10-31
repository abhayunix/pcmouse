using System;
using System.Drawing;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Windows;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using QRCoder;
using PcmouseAgent.Modules;

namespace PcmouseAgent
{
    public partial class MainWindow : Window
    {
        private readonly ConnectionManager _connectionManager;
        private readonly LocalWebSocketServer _webSocketServer;
        private readonly BluetoothManager _bluetoothManager;
        private readonly DispatcherTimer _metricsTimer;

        public MainWindow()
        {
            InitializeComponent();
            _connectionManager = new ConnectionManager();
            _connectionManager.StateChanged += OnConnectionStateChanged;
            _connectionManager.LogMessage += OnLogMessage;

            _webSocketServer = new LocalWebSocketServer(_connectionManager);
            _bluetoothManager = new BluetoothManager(_connectionManager);

            // Timer for UI hardware telemetry updates
            _metricsTimer = new DispatcherTimer
            {
                Interval = TimeSpan.FromSeconds(2)
            };
            _metricsTimer.Tick += OnMetricsTimerTick;

            Loaded += MainWindow_Loaded;
            Unloaded += MainWindow_Unloaded;
        }

        private void MainWindow_Loaded(object sender, RoutedEventArgs e)
        {
            _webSocketServer.Start(8443);
            _bluetoothManager.StartListener();
            RefreshPairingCode();
            _metricsTimer.Start();
            UpdateMetricsUI();
        }

        private void MainWindow_Unloaded(object sender, RoutedEventArgs e)
        {
            _metricsTimer.Stop();
            _bluetoothManager.StopListener();
            _webSocketServer.Stop();
        }

        private void RefreshPairing_Click(object sender, RoutedEventArgs e)
        {
            RefreshPairingCode();
        }

        private void RefreshPairingCode()
        {
            string localIp = GetLocalIPAddress();
            LocalIpText.Text = $"Local IP: {localIp}:8443";

            var session = _connectionManager.Pairing.GenerateNewPairingCode(validMinutes: 15);
            string qrPayload = $"pcmouse://pair?ip={localIp}&port=8443&code={session.PairingCode}&token={session.SessionToken}";

            GenerateQrCode(qrPayload);
            PairingCodeText.Text = $"Pairing PIN: {session.PairingCode}";
            _connectionManager.Security.LogAudit($"New pairing PIN generated: {session.PairingCode}");
        }

        private void OnMetricsTimerTick(object? sender, EventArgs e)
        {
            UpdateMetricsUI();
        }

        private void UpdateMetricsUI()
        {
            try
            {
                var metrics = _connectionManager.Monitor.GetMetrics();
                CpuText.Text = $"CPU: {metrics.CpuUsagePercent:F1}%";
                RamText.Text = $"RAM: {metrics.RamUsedMb} MB / {metrics.RamTotalMb} MB ({metrics.RamUsagePercent:F1}%)";
                BatteryText.Text = $"Battery: {metrics.BatteryPercent}% {(metrics.IsCharging ? "[Charging]" : "[Discharging]")}";
                UptimeText.Text = $"Uptime: {TimeSpan.FromSeconds(metrics.UptimeSeconds):dd\\d\\ hh\\h\\ mm\\m}";
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"UpdateMetricsUI error: {ex.Message}");
            }
        }

        private void OnConnectionStateChanged(AgentConnectionState newState)
        {
            Dispatcher.Invoke(() =>
            {
                StatusText.Text = $"Status: {newState}";
                StatusText.Foreground = newState == AgentConnectionState.Connected
                    ? System.Windows.Media.Brushes.LightGreen
                    : System.Windows.Media.Brushes.Orange;
            });
        }

        private void OnLogMessage(string log)
        {
            Dispatcher.Invoke(() =>
            {
                AuditLogListBox.Items.Insert(0, $"[{DateTime.Now:HH:mm:ss}] {log}");
                if (AuditLogListBox.Items.Count > 100)
                {
                    AuditLogListBox.Items.RemoveAt(AuditLogListBox.Items.Count - 1);
                }
            });
        }

        private string GetLocalIPAddress()
        {
            try
            {
                var host = Dns.GetHostEntry(Dns.GetHostName());
                foreach (var ip in host.AddressList)
                {
                    if (ip.AddressFamily == AddressFamily.InterNetwork && !IPAddress.IsLoopback(ip))
                    {
                        return ip.ToString();
                    }
                }
            }
            catch { }
            return "127.0.0.1";
        }

        private void GenerateQrCode(string content)
        {
            try
            {
                using QRCodeGenerator qrGenerator = new QRCodeGenerator();
                using QRCodeData qrCodeData = qrGenerator.CreateQrCode(content, QRCodeGenerator.ECCLevel.Q);
                using QRCode qrCode = new QRCode(qrCodeData);
                using Bitmap qrBitmap = qrCode.GetGraphic(20);

                using MemoryStream ms = new MemoryStream();
                qrBitmap.Save(ms, System.Drawing.Imaging.ImageFormat.Png);
                ms.Position = 0;

                BitmapImage bitmapImage = new BitmapImage();
                bitmapImage.BeginInit();
                bitmapImage.CacheOption = BitmapCacheOption.OnLoad;
                bitmapImage.StreamSource = ms;
                bitmapImage.EndInit();

                QrCodeImage.Source = bitmapImage;
            }
            catch (Exception ex)
            {
                StatusText.Text = $"QR Error: {ex.Message}";
            }
        }
    }
}
