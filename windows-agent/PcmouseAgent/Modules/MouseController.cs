using System;
using System.Runtime.InteropServices;
using System.Windows;

namespace PcmouseAgent.Modules
{
    public class MouseController
    {
        #region Win32 P/Invoke Definitions

        [DllImport("user32.dll", SetLastError = true)]
        private static extern bool SetCursorPos(int X, int Y);

        [DllImport("user32.dll")]
        private static extern bool GetCursorPos(out POINT lpPoint);

        [DllImport("user32.dll")]
        private static extern void mouse_event(uint dwFlags, int dx, int dy, uint dwData, UIntPtr dwExtraInfo);

        [StructLayout(LayoutKind.Sequential)]
        private struct POINT
        {
            public int X;
            public int Y;
        }

        private const uint MOUSEEVENTF_MOVE = 0x0001;
        private const uint MOUSEEVENTF_LEFTDOWN = 0x0002;
        private const uint MOUSEEVENTF_LEFTUP = 0x0004;
        private const uint MOUSEEVENTF_RIGHTDOWN = 0x0008;
        private const uint MOUSEEVENTF_RIGHTUP = 0x0010;
        private const uint MOUSEEVENTF_MIDDLEDOWN = 0x0020;
        private const uint MOUSEEVENTF_MIDDLEUP = 0x0040;
        private const uint MOUSEEVENTF_WHEEL = 0x0800;
        private const uint MOUSEEVENTF_HWHEEL = 0x01000;
        private const uint MOUSEEVENTF_ABSOLUTE = 0x8000;

        #endregion

        /// <summary>
        /// Move cursor by relative dx and dy deltas smoothly using hardware-accelerated Win32 mouse_event
        /// </summary>
        public void MoveRelative(int dx, int dy)
        {
            mouse_event(MOUSEEVENTF_MOVE, dx, dy, 0, UIntPtr.Zero);
        }

        /// <summary>
        /// Move cursor to normalized absolute position (0.0 to 1.0)
        /// </summary>
        public void MoveAbsoluteNormalized(double normX, double normY)
        {
            try
            {
                int screenWidth = (int)SystemParameters.PrimaryScreenWidth;
                int screenHeight = (int)SystemParameters.PrimaryScreenHeight;

                int posX = (int)(normX * screenWidth);
                int posY = (int)(normY * screenHeight);

                SetCursorPos(posX, posY);
            }
            catch
            {
                int absoluteX = (int)(normX * 65535.0);
                int absoluteY = (int)(normY * 65535.0);
                mouse_event(MOUSEEVENTF_MOVE | MOUSEEVENTF_ABSOLUTE, absoluteX, absoluteY, 0, UIntPtr.Zero);
            }
        }

        /// <summary>
        /// Execute left mouse click
        /// </summary>
        public void LeftClick()
        {
            mouse_event(MOUSEEVENTF_LEFTDOWN, 0, 0, 0, UIntPtr.Zero);
            mouse_event(MOUSEEVENTF_LEFTUP, 0, 0, 0, UIntPtr.Zero);
        }

        /// <summary>
        /// Execute right mouse click
        /// </summary>
        public void RightClick()
        {
            mouse_event(MOUSEEVENTF_RIGHTDOWN, 0, 0, 0, UIntPtr.Zero);
            mouse_event(MOUSEEVENTF_RIGHTUP, 0, 0, 0, UIntPtr.Zero);
        }

        /// <summary>
        /// Set mouse button state (down / up)
        /// </summary>
        public void SetButtonState(string button, bool isDown)
        {
            if (button.Equals("LEFT", StringComparison.OrdinalIgnoreCase))
            {
                uint flag = isDown ? MOUSEEVENTF_LEFTDOWN : MOUSEEVENTF_LEFTUP;
                mouse_event(flag, 0, 0, 0, UIntPtr.Zero);
            }
            else if (button.Equals("RIGHT", StringComparison.OrdinalIgnoreCase))
            {
                uint flag = isDown ? MOUSEEVENTF_RIGHTDOWN : MOUSEEVENTF_RIGHTUP;
                mouse_event(flag, 0, 0, 0, UIntPtr.Zero);
            }
            else if (button.Equals("MIDDLE", StringComparison.OrdinalIgnoreCase))
            {
                uint flag = isDown ? MOUSEEVENTF_MIDDLEDOWN : MOUSEEVENTF_MIDDLEUP;
                mouse_event(flag, 0, 0, 0, UIntPtr.Zero);
            }
        }

        /// <summary>
        /// Scroll vertical or horizontal wheel
        /// </summary>
        public void Scroll(int scrollDeltaY, int scrollDeltaX = 0)
        {
            if (scrollDeltaY != 0)
            {
                mouse_event(MOUSEEVENTF_WHEEL, 0, 0, (uint)scrollDeltaY, UIntPtr.Zero);
            }

            if (scrollDeltaX != 0)
            {
                mouse_event(MOUSEEVENTF_HWHEEL, 0, 0, (uint)scrollDeltaX, UIntPtr.Zero);
            }
        }
    }
}
