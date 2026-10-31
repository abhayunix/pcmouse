using System;
using System.Collections.Concurrent;
using System.Diagnostics;
using System.Net;
using Fleck;

namespace PcmouseAgent.Modules
{
    public class LocalWebSocketServer
    {
        private readonly ConnectionManager _connectionManager;
        private WebSocketServer? _server;
        private readonly ConcurrentDictionary<Guid, IWebSocketConnection> _clients = new ConcurrentDictionary<Guid, IWebSocketConnection>();

        public int Port { get; private set; } = 8443;
        public bool IsRunning { get; private set; }

        public LocalWebSocketServer(ConnectionManager connectionManager)
        {
            _connectionManager = connectionManager;
        }

        public void Start(int port = 8443)
        {
            if (IsRunning) return;

            Port = port;
            try
            {
                // Listen on all network interfaces (0.0.0.0)
                _server = new WebSocketServer($"ws://0.0.0.0:{Port}");

                _server.Start(socket =>
                {
                    socket.OnOpen = () =>
                    {
                        _clients.TryAdd(socket.ConnectionInfo.Id, socket);
                        string ip = socket.ConnectionInfo.ClientIpAddress;
                        _connectionManager.Security.LogAudit($"WebSocket client connected from {ip}");
                        _connectionManager.SetState(AgentConnectionState.Connecting);
                    };

                    socket.OnClose = () =>
                    {
                        _clients.TryRemove(socket.ConnectionInfo.Id, out _);
                        string ip = socket.ConnectionInfo.ClientIpAddress;
                        _connectionManager.Security.LogAudit($"WebSocket client disconnected ({ip})");

                        if (_clients.IsEmpty)
                        {
                            _connectionManager.SetState(AgentConnectionState.Disconnected);
                        }
                    };

                    socket.OnMessage = message =>
                    {
                        string clientIp = socket.ConnectionInfo.ClientIpAddress;
                        string? response = _connectionManager.ProcessIncomingFrame(message, clientIp);

                        if (!string.IsNullOrEmpty(response))
                        {
                            socket.Send(response);
                        }
                    };

                    socket.OnError = ex =>
                    {
                        Debug.WriteLine($"WebSocket socket error: {ex.Message}");
                    };
                });

                IsRunning = true;
                _connectionManager.Security.LogAudit($"Local WebSocket server started on ws://0.0.0.0:{Port}");
            }
            catch (Exception ex)
            {
                Debug.WriteLine($"LocalWebSocketServer start error: {ex.Message}");
                _connectionManager.Security.LogAudit($"WebSocket server start failed: {ex.Message}");
            }
        }

        public void Broadcast(string jsonMessage)
        {
            foreach (var client in _clients.Values)
            {
                if (client.IsAvailable)
                {
                    client.Send(jsonMessage);
                }
            }
        }

        public void Stop()
        {
            if (!IsRunning) return;

            try
            {
                foreach (var client in _clients.Values)
                {
                    client.Close();
                }
                _clients.Clear();

                _server?.Dispose();
                IsRunning = false;
                _connectionManager.Security.LogAudit("Local WebSocket server stopped.");
            }
            catch (Exception ex)
            {
                Debug.WriteLine($"LocalWebSocketServer stop error: {ex.Message}");
            }
        }
    }
}
