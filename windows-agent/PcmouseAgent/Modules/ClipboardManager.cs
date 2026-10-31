using System;
using System.Diagnostics;
using System.Windows;

namespace PcmouseAgent.Modules
{
    public class ClipboardManager
    {
        /// <summary>
        /// Set text on Windows Clipboard (runs safely on WPF UI/STA thread)
        /// </summary>
        public bool SetClipboardText(string text)
        {
            if (string.IsNullOrEmpty(text)) return false;

            try
            {
                if (Application.Current != null && Application.Current.Dispatcher != null)
                {
                    Application.Current.Dispatcher.Invoke(() =>
                    {
                        Clipboard.SetText(text);
                    });
                    return true;
                }
                else
                {
                    // Fallback STA thread execution
                    var thread = new System.Threading.Thread(() => Clipboard.SetText(text));
                    thread.SetApartmentState(System.Threading.ApartmentState.STA);
                    thread.Start();
                    thread.Join();
                    return true;
                }
            }
            catch (Exception ex)
            {
                Debug.WriteLine($"SetClipboardText error: {ex.Message}");
                return false;
            }
        }

        /// <summary>
        /// Get current text from Windows Clipboard
        /// </summary>
        public string GetClipboardText()
        {
            try
            {
                string result = string.Empty;
                if (Application.Current != null && Application.Current.Dispatcher != null)
                {
                    Application.Current.Dispatcher.Invoke(() =>
                    {
                        if (Clipboard.ContainsText())
                        {
                            result = Clipboard.GetText();
                        }
                    });
                }
                return result;
            }
            catch (Exception ex)
            {
                Debug.WriteLine($"GetClipboardText error: {ex.Message}");
                return string.Empty;
            }
        }
    }
}
