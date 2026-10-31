using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

namespace PcmouseAgent.Modules
{
    public class KeyboardController
    {
        #region Win32 P/Invoke Definitions

        [DllImport("user32.dll", SetLastError = true)]
        private static extern uint SendInput(uint nInputs, INPUT[] pInputs, int cbSize);

        [DllImport("user32.dll", CharSet = CharSet.Auto)]
        private static extern short VkKeyScan(char ch);

        [StructLayout(LayoutKind.Sequential)]
        private struct INPUT
        {
            public uint type;
            public InputUnion u;
        }

        [StructLayout(LayoutKind.Explicit)]
        private struct InputUnion
        {
            [FieldOffset(0)] public KEYBDINPUT ki;
            [FieldOffset(0)] public MOUSEINPUT mi;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct KEYBDINPUT
        {
            public ushort wVk;
            public ushort wScan;
            public uint dwFlags;
            public uint time;
            public IntPtr dwExtraInfo;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct MOUSEINPUT
        {
            public int dx;
            public int dy;
            public uint mouseData;
            public uint dwFlags;
            public uint time;
            public IntPtr dwExtraInfo;
        }

        private const uint INPUT_KEYBOARD = 1;

        private const uint KEYEVENTF_KEYDOWN = 0x0000;
        private const uint KEYEVENTF_EXTENDEDKEY = 0x0001;
        private const uint KEYEVENTF_KEYUP = 0x0002;
        private const uint KEYEVENTF_UNICODE = 0x0004;

        #endregion

        /// <summary>
        /// Send a single virtual key state (Down or Up)
        /// </summary>
        public void SendVirtualKey(ushort vkCode, bool isDown)
        {
            INPUT[] inputs = new INPUT[1];
            inputs[0].type = INPUT_KEYBOARD;
            inputs[0].u.ki = new KEYBDINPUT
            {
                wVk = vkCode,
                wScan = 0,
                dwFlags = isDown ? KEYEVENTF_KEYDOWN : KEYEVENTF_KEYUP,
                time = 0,
                dwExtraInfo = IntPtr.Zero
            };

            SendInput(1, inputs, Marshal.SizeOf(typeof(INPUT)));
        }

        /// <summary>
        /// Send key stroke (KeyDown followed immediately by KeyUp)
        /// </summary>
        public void PressVirtualKey(ushort vkCode)
        {
            SendVirtualKey(vkCode, isDown: true);
            SendVirtualKey(vkCode, isDown: false);
        }

        /// <summary>
        /// Inject Unicode or Virtual-Key text character directly live
        /// </summary>
        public void SendText(string text)
        {
            if (string.IsNullOrEmpty(text)) return;

            foreach (char ch in text)
            {
                if (ch == '\b') // Backspace
                {
                    PressVirtualKey(0x08);
                    continue;
                }
                if (ch == '\r' || ch == '\n') // Enter
                {
                    PressVirtualKey(0x0D);
                    continue;
                }
                if (ch == '\t') // Tab
                {
                    PressVirtualKey(0x09);
                    continue;
                }

                short vkScan = VkKeyScan(ch);
                byte vk = (byte)(vkScan & 0xFF);
                byte shiftState = (byte)((vkScan >> 8) & 0xFF);

                if (vkScan != -1 && vk != 0)
                {
                    bool needShift = (shiftState & 1) != 0;

                    if (needShift) SendVirtualKey(0x10, isDown: true); // VK_SHIFT down

                    PressVirtualKey(vk);

                    if (needShift) SendVirtualKey(0x10, isDown: false); // VK_SHIFT up
                }
                else
                {
                    // Fallback to Unicode for non-ASCII or complex chars
                    INPUT[] inputs = new INPUT[2];
                    inputs[0].type = INPUT_KEYBOARD;
                    inputs[0].u.ki = new KEYBDINPUT
                    {
                        wVk = 0,
                        wScan = ch,
                        dwFlags = KEYEVENTF_UNICODE,
                        time = 0,
                        dwExtraInfo = IntPtr.Zero
                    };

                    inputs[1].type = INPUT_KEYBOARD;
                    inputs[1].u.ki = new KEYBDINPUT
                    {
                        wVk = 0,
                        wScan = ch,
                        dwFlags = KEYEVENTF_UNICODE | KEYEVENTF_KEYUP,
                        time = 0,
                        dwExtraInfo = IntPtr.Zero
                    };

                    SendInput(2, inputs, Marshal.SizeOf(typeof(INPUT)));
                }
            }
        }

        /// <summary>
        /// Press keyboard shortcut with modifier keys (e.g. CTRL+C, ALT+TAB, WIN+D)
        /// </summary>
        public void SendShortcut(ushort targetVk, List<ushort> modifierVks)
        {
            List<INPUT> inputs = new List<INPUT>();

            // Press modifiers
            foreach (var mod in modifierVks)
            {
                inputs.Add(new INPUT
                {
                    type = INPUT_KEYBOARD,
                    u = new InputUnion
                    {
                        ki = new KEYBDINPUT { wVk = mod, dwFlags = KEYEVENTF_KEYDOWN }
                    }
                });
            }

            // Press target key down and up
            inputs.Add(new INPUT
            {
                type = INPUT_KEYBOARD,
                u = new InputUnion
                {
                    ki = new KEYBDINPUT { wVk = targetVk, dwFlags = KEYEVENTF_KEYDOWN }
                }
            });
            inputs.Add(new INPUT
            {
                type = INPUT_KEYBOARD,
                u = new InputUnion
                {
                    ki = new KEYBDINPUT { wVk = targetVk, dwFlags = KEYEVENTF_KEYUP }
                }
            });

            // Release modifiers in reverse
            for (int i = modifierVks.Count - 1; i >= 0; i--)
            {
                inputs.Add(new INPUT
                {
                    type = INPUT_KEYBOARD,
                    u = new InputUnion
                    {
                        ki = new KEYBDINPUT { wVk = modifierVks[i], dwFlags = KEYEVENTF_KEYUP }
                    }
                });
            }

            SendInput((uint)inputs.Count, inputs.ToArray(), Marshal.SizeOf(typeof(INPUT)));
        }
    }
}
