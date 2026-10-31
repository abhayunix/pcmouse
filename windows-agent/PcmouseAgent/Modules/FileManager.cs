using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using Newtonsoft.Json;

namespace PcmouseAgent.Modules
{
    public class FileItem
    {
        public string Name { get; set; } = string.Empty;
        public string Path { get; set; } = string.Empty;
        public bool IsDirectory { get; set; }
        public long SizeBytes { get; set; }
        public DateTime LastModified { get; set; }
    }

    public class FileTransferSession
    {
        public string TransferId { get; set; } = Guid.NewGuid().ToString();
        public string FileName { get; set; } = string.Empty;
        public string TargetPath { get; set; } = string.Empty;
        public long FileSizeBytes { get; set; }
        public long ReceivedBytes { get; set; }
        public FileStream? Stream { get; set; }
        public string ExpectedChecksum { get; set; } = string.Empty;
    }

    public class FileManager
    {
        private readonly ConcurrentDictionary<string, FileTransferSession> _activeUploads = new ConcurrentDictionary<string, FileTransferSession>();

        /// <summary>
        /// Get directory contents (files and folders) for requested path
        /// </summary>
        public List<FileItem> ListDirectory(string? requestedPath = null)
        {
            var items = new List<FileItem>();

            try
            {
                if (string.IsNullOrWhiteSpace(requestedPath))
                {
                    // Return drive roots if empty
                    foreach (var drive in DriveInfo.GetDrives())
                    {
                        if (drive.IsReady)
                        {
                            items.Add(new FileItem
                            {
                                Name = drive.Name,
                                Path = drive.RootDirectory.FullName,
                                IsDirectory = true,
                                SizeBytes = drive.TotalSize,
                                LastModified = DateTime.Now
                            });
                        }
                    }
                    return items;
                }

                DirectoryInfo dir = new DirectoryInfo(requestedPath);
                if (!dir.Exists) return items;

                // Directories
                foreach (var subDir in dir.GetDirectories())
                {
                    try
                    {
                        items.Add(new FileItem
                        {
                            Name = subDir.Name,
                            Path = subDir.FullName,
                            IsDirectory = true,
                            SizeBytes = 0,
                            LastModified = subDir.LastWriteTime
                        });
                    }
                    catch { }
                }

                // Files
                foreach (var file in dir.GetFiles())
                {
                    try
                    {
                        items.Add(new FileItem
                        {
                            Name = file.Name,
                            Path = file.FullName,
                            IsDirectory = false,
                            SizeBytes = file.Length,
                            LastModified = file.LastWriteTime
                        });
                    }
                    catch { }
                }
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"ListDirectory error: {ex.Message}");
            }

            return items.OrderByDescending(x => x.IsDirectory).ThenBy(x => x.Name).ToList();
        }

        /// <summary>
        /// Start receiving file upload from Android client
        /// </summary>
        public string StartIncomingUpload(string fileName, string destFolder, long fileSize, string expectedChecksum)
        {
            try
            {
                if (string.IsNullOrWhiteSpace(destFolder) || !Directory.Exists(destFolder))
                {
                    destFolder = Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments);
                }

                string fullPath = Path.Combine(destFolder, fileName);
                string tempPath = fullPath + ".tmp";

                var session = new FileTransferSession
                {
                    FileName = fileName,
                    TargetPath = fullPath,
                    FileSizeBytes = fileSize,
                    ExpectedChecksum = expectedChecksum,
                    Stream = new FileStream(tempPath, FileMode.Create, FileAccess.Write, FileShare.None)
                };

                _activeUploads.TryAdd(session.TransferId, session);
                return session.TransferId;
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"StartIncomingUpload error: {ex.Message}");
                return string.Empty;
            }
        }

        /// <summary>
        /// Write base64 chunk to active incoming upload stream
        /// </summary>
        public bool ProcessUploadChunk(string transferId, string base64Chunk)
        {
            if (!_activeUploads.TryGetValue(transferId, out var session) || session.Stream == null)
            {
                return false;
            }

            try
            {
                byte[] chunkBytes = Convert.FromBase64String(base64Chunk);
                session.Stream.Write(chunkBytes, 0, chunkBytes.Length);
                session.ReceivedBytes += chunkBytes.Length;
                return true;
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"ProcessUploadChunk error: {ex.Message}");
                return false;
            }
        }

        /// <summary>
        /// Complete incoming file upload and verify SHA-256 checksum
        /// </summary>
        public bool CompleteUpload(string transferId, out string finalFilePath)
        {
            finalFilePath = string.Empty;

            if (!_activeUploads.TryRemove(transferId, out var session) || session.Stream == null)
            {
                return false;
            }

            try
            {
                string tempPath = session.Stream.Name;
                session.Stream.Flush();
                session.Stream.Close();
                session.Stream.Dispose();

                // Compute SHA-256 checksum
                using (var sha256 = SHA256.Create())
                using (var fs = File.OpenRead(tempPath))
                {
                    byte[] hash = sha256.ComputeHash(fs);
                    string actualChecksum = Convert.ToHexString(hash);

                    if (!string.IsNullOrEmpty(session.ExpectedChecksum) &&
                        !string.Equals(actualChecksum, session.ExpectedChecksum, StringComparison.OrdinalIgnoreCase))
                    {
                        System.Diagnostics.Debug.WriteLine($"Checksum mismatch! Expected: {session.ExpectedChecksum}, Actual: {actualChecksum}");
                        File.Delete(tempPath);
                        return false;
                    }
                }

                // Move temp file to final target
                if (File.Exists(session.TargetPath))
                {
                    File.Delete(session.TargetPath);
                }

                File.Move(tempPath, session.TargetPath);
                finalFilePath = session.TargetPath;
                return true;
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"CompleteUpload error: {ex.Message}");
                return false;
            }
        }

        /// <summary>
        /// Compute file SHA-256 hash helper
        /// </summary>
        public static string ComputeFileChecksum(string filePath)
        {
            try
            {
                using var sha256 = SHA256.Create();
                using var stream = File.OpenRead(filePath);
                byte[] hash = sha256.ComputeHash(stream);
                return Convert.ToHexString(hash);
            }
            catch
            {
                return string.Empty;
            }
        }
    }
}
