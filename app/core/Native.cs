// VeloxPC native helpers (compiled at runtime by PowerShell Add-Type, C# 5 / .NET Framework 4.x)
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Net;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

namespace VeloxPC
{
    // ------------------------------------------------------------------ view models
    public class Bindable : INotifyPropertyChanged
    {
        public event PropertyChangedEventHandler PropertyChanged;
        protected void Raise(string name)
        {
            PropertyChangedEventHandler h = PropertyChanged;
            if (h != null) h(this, new PropertyChangedEventArgs(name));
        }
    }

    public class OptionItem : Bindable
    {
        public string Id { get; set; }
        public string Kind { get; set; }
        public string Group { get; set; }
        public string Title { get; set; }
        public string Description { get; set; }
        public string Risk { get; set; }          // safe | caution | advanced | avoid
        public string RiskLabel { get; set; }
        public bool NeedsReboot { get; set; }
        public string RebootLabel { get; set; }
        public object Tag { get; set; }

        private string _warning;
        public string Warning { get { return _warning; } set { _warning = value; Raise("Warning"); Raise("HasWarning"); } }
        public bool HasWarning { get { return !String.IsNullOrEmpty(_warning); } }

        private string _badge;
        public string Badge { get { return _badge; } set { _badge = value; Raise("Badge"); Raise("HasBadge"); } }
        public bool HasBadge { get { return !String.IsNullOrEmpty(_badge); } }
        private string _badgeKind = "info";
        public string BadgeKind { get { return _badgeKind; } set { _badgeKind = value; Raise("BadgeKind"); } }

        private bool _checked;
        public bool IsChecked { get { return _checked; } set { if (_checked != value) { _checked = value; Raise("IsChecked"); Raise("IsDirty"); } } }

        private bool _applied;
        public bool IsApplied { get { return _applied; } set { _applied = value; Raise("IsApplied"); Raise("IsDirty"); } }

        public bool IsDirty { get { return _checked != _applied; } }

        private bool _selectable = true;
        public bool IsSelectable { get { return _selectable; } set { _selectable = value; Raise("IsSelectable"); } }

        private string _status;
        public string Status { get { return _status; } set { _status = value; Raise("Status"); Raise("HasStatus"); } }
        public bool HasStatus { get { return !String.IsNullOrEmpty(_status); } }

        private string _extra;
        public string Extra { get { return _extra; } set { _extra = value; Raise("Extra"); Raise("HasExtra"); } }
        public bool HasExtra { get { return !String.IsNullOrEmpty(_extra); } }

        private long _size;
        public long Size { get { return _size; } set { _size = value; Raise("Size"); } }
    }

    public class Finding : Bindable
    {
        public string Id { get; set; }
        public string Category { get; set; }
        public string Severity { get; set; }      // ok | info | warn | crit
        public string Title { get; set; }
        public string Detail { get; set; }
        public string ActionId { get; set; }
        public string ActionLabel { get; set; }
        public bool HasAction { get { return !String.IsNullOrEmpty(ActionId); } }
        public string Glyph
        {
            get
            {
                switch (Severity)
                {
                    case "crit": return "";
                    case "warn": return "";
                    case "info": return "";
                    default: return "";
                }
            }
        }
        private string _status;
        public string Status { get { return _status; } set { _status = value; Raise("Status"); } }
    }

    public class HwCard
    {
        public string Glyph { get; set; }
        public string Label { get; set; }
        public string Title { get; set; }
        public string Sub { get; set; }
        public string Detail { get; set; }
    }

    public class ProcRow : Bindable
    {
        public string Name { get; set; }
        public int Count { get; set; }
        public double MemMB { get; set; }
        public string MemText { get; set; }
        public double Cpu { get; set; }
        public string CpuText { get; set; }
        public string Description { get; set; }
        public string Risk { get; set; }
        public string RiskLabel { get; set; }
        public string Advice { get; set; }
        public bool CanEnd { get; set; }
        public string Path { get; set; }
    }

    public class PingRow : Bindable
    {
        public string Label { get; set; }
        public string Host { get; set; }
        public string Color { get; set; }
        private string _avg = "-", _jit = "-", _loss = "-", _min = "-", _max = "-", _q = "", _qk = "info";
        public string Avg { get { return _avg; } set { _avg = value; Raise("Avg"); } }
        public string Min { get { return _min; } set { _min = value; Raise("Min"); } }
        public string Max { get { return _max; } set { _max = value; Raise("Max"); } }
        public string Jitter { get { return _jit; } set { _jit = value; Raise("Jitter"); } }
        public string Loss { get { return _loss; } set { _loss = value; Raise("Loss"); } }
        public string Quality { get { return _q; } set { _q = value; Raise("Quality"); } }
        public string QualityKind { get { return _qk; } set { _qk = value; Raise("QualityKind"); } }
    }

    public class DnsRow : Bindable
    {
        public string Provider { get; set; }
        public string Primary { get; set; }
        public string Secondary { get; set; }
        private string _ms = "-";
        public string Ms { get { return _ms; } set { _ms = value; Raise("Ms"); } }
        public double Value { get; set; }
        private bool _best;
        public bool IsBest { get { return _best; } set { _best = value; Raise("IsBest"); } }
    }

    public class HistRow
    {
        public string Id { get; set; }
        public string Time { get; set; }
        public string Title { get; set; }
        public string Detail { get; set; }
        public bool CanUndo { get; set; }
    }

    public class KeyValueRow
    {
        public string Key { get; set; }
        public string Value { get; set; }
        public string Hint { get; set; }
        public bool HasHint { get { return !String.IsNullOrEmpty(Hint); } }
    }

    public class DisplayInfo
    {
        public string Device { get; set; }
        public string Monitor { get; set; }
        public string MonitorId { get; set; }
        public int Width { get; set; }
        public int Height { get; set; }
        public int CurrentHz { get; set; }
        public int MaxHz { get; set; }
        public bool Primary { get; set; }
    }

    public class ProcInfo
    {
        public string Name { get; set; }
        public int Id { get; set; }
        public long WorkingSet { get; set; }
        public double Cpu { get; set; }
        public string Path { get; set; }
        public int SessionId { get; set; }
    }

    // ------------------------------------------------------------------ native helpers
    public static class Native
    {
        [DllImport("kernel32.dll")] static extern bool GetSystemTimes(out long idle, out long kernel, out long user);
        [DllImport("kernel32.dll")] static extern IntPtr GetConsoleWindow();
        [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
        [DllImport("kernel32.dll")] static extern uint SetThreadExecutionState(uint esFlags);
        [DllImport("user32.dll", SetLastError = true)] static extern bool SystemParametersInfo(uint action, uint uiParam, int[] pvParam, uint winIni);
        [DllImport("user32.dll", SetLastError = true)] static extern bool SystemParametersInfo(uint action, uint uiParam, IntPtr pvParam, uint winIni);

        [StructLayout(LayoutKind.Sequential)]
        class MEMORYSTATUSEX
        {
            public uint dwLength = (uint)Marshal.SizeOf(typeof(MEMORYSTATUSEX));
            public uint dwMemoryLoad;
            public ulong ullTotalPhys;
            public ulong ullAvailPhys;
            public ulong ullTotalPageFile;
            public ulong ullAvailPageFile;
            public ulong ullTotalVirtual;
            public ulong ullAvailVirtual;
            public ulong ullAvailExtendedVirtual;
        }
        [DllImport("kernel32.dll", SetLastError = true)] static extern bool GlobalMemoryStatusEx([In, Out] MEMORYSTATUSEX buf);

        static long _pIdle, _pKernel, _pUser;

        /// <summary>Total CPU usage (0-100) since the previous call.</summary>
        public static double CpuUsage()
        {
            long idle, kernel, user;
            if (!GetSystemTimes(out idle, out kernel, out user)) return 0;
            long dIdle = idle - _pIdle, dKernel = kernel - _pKernel, dUser = user - _pUser;
            _pIdle = idle; _pKernel = kernel; _pUser = user;
            long total = dKernel + dUser;
            if (total <= 0) return 0;
            double v = (1.0 - (double)dIdle / total) * 100.0;
            if (v < 0) v = 0; if (v > 100) v = 100;
            return v;
        }

        /// <summary>Returns { loadPercent, totalBytes, availBytes }.</summary>
        public static double[] Memory()
        {
            MEMORYSTATUSEX m = new MEMORYSTATUSEX();
            if (!GlobalMemoryStatusEx(m)) return new double[] { 0, 0, 0 };
            return new double[] { m.dwMemoryLoad, m.ullTotalPhys, m.ullAvailPhys };
        }

        [DllImport("shell32.dll", CharSet = CharSet.Unicode)] static extern int SetCurrentProcessExplicitAppUserModelID(string appID);
        public static int SetAppId(string id) { return SetCurrentProcessExplicitAppUserModelID(id); }

        [StructLayout(LayoutKind.Sequential)] struct MARGINS { public int l, r, t, b; }
        [DllImport("dwmapi.dll")] static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int value, int size);
        [DllImport("user32.dll")] static extern int GetWindowLong(IntPtr hwnd, int index);
        [DllImport("user32.dll")] static extern int SetWindowLong(IntPtr hwnd, int index, int value);
        [DllImport("dwmapi.dll")] static extern int DwmExtendFrameIntoClientArea(IntPtr hwnd, ref MARGINS m);

        /// <summary>Windows 11 glass: 2 = Mica, 3 = Acrylic, 4 = Mica Alt. Returns HRESULT of the backdrop call.</summary>
        public static int EnableBackdrop(IntPtr hwnd, int type)
        {
            // hide the native caption buttons, the app draws its own (avoids a double close button)
            int style = GetWindowLong(hwnd, -16);
            SetWindowLong(hwnd, -16, style & ~0x00080000);           // WS_SYSMENU
            int dark = 1;
            DwmSetWindowAttribute(hwnd, 20, ref dark, 4);           // DWMWA_USE_IMMERSIVE_DARK_MODE
            MARGINS m = new MARGINS(); m.l = -1; m.r = -1; m.t = -1; m.b = -1;
            DwmExtendFrameIntoClientArea(hwnd, ref m);
            int corner = 2;
            DwmSetWindowAttribute(hwnd, 33, ref corner, 4);          // rounded corners
            return DwmSetWindowAttribute(hwnd, 38, ref type, 4);     // DWMWA_SYSTEMBACKDROP_TYPE
        }

        public static void HideConsole()
        {
            IntPtr h = GetConsoleWindow();
            if (h != IntPtr.Zero) ShowWindow(h, 0);
        }

        public static void KeepAwake(bool on)
        {
            // ES_CONTINUOUS | ES_SYSTEM_REQUIRED
            SetThreadExecutionState(on ? 0x80000001u : 0x80000000u);
        }

        /// <summary>Apply mouse acceleration settings live (thresholds and speed).</summary>
        public static bool SetMouse(int t1, int t2, int accel)
        {
            return SystemParametersInfo(0x0004, 0, new int[] { t1, t2, accel }, 0x03);
        }

        /// <summary>Generic SystemParametersInfo with uiParam only (keyboard delay/speed).</summary>
        public static bool Spi(uint action, uint uiParam)
        {
            return SystemParametersInfo(action, uiParam, IntPtr.Zero, 0x03);
        }

        // ---------------------------------------------------------- display / refresh rate
        const int ENUM_CURRENT_SETTINGS = -1;
        const int DM_DISPLAYFREQUENCY = 0x400000;
        const int DM_INTERLACED = 0x2;

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        public struct DEVMODE
        {
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmDeviceName;
            public short dmSpecVersion;
            public short dmDriverVersion;
            public short dmSize;
            public short dmDriverExtra;
            public int dmFields;
            public int dmPositionX;
            public int dmPositionY;
            public int dmDisplayOrientation;
            public int dmDisplayFixedOutput;
            public short dmColor;
            public short dmDuplex;
            public short dmYResolution;
            public short dmTTOption;
            public short dmCollate;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmFormName;
            public short dmLogPixels;
            public int dmBitsPerPel;
            public int dmPelsWidth;
            public int dmPelsHeight;
            public int dmDisplayFlags;
            public int dmDisplayFrequency;
            public int dmICMMethod;
            public int dmICMIntent;
            public int dmMediaType;
            public int dmDitherType;
            public int dmReserved1;
            public int dmReserved2;
            public int dmPanningWidth;
            public int dmPanningHeight;
        }

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        public struct DISPLAY_DEVICE
        {
            public int cb;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string DeviceName;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceString;
            public int StateFlags;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceID;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceKey;
        }

        [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern bool EnumDisplayDevices(string lpDevice, uint iDevNum, ref DISPLAY_DEVICE lpDisplayDevice, uint dwFlags);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern bool EnumDisplaySettings(string deviceName, int modeNum, ref DEVMODE devMode);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int ChangeDisplaySettingsEx(string lpszDeviceName, ref DEVMODE lpDevMode, IntPtr hwnd, uint dwflags, IntPtr lParam);

        public static List<DisplayInfo> GetDisplays()
        {
            List<DisplayInfo> list = new List<DisplayInfo>();
            DISPLAY_DEVICE dd = new DISPLAY_DEVICE();
            dd.cb = Marshal.SizeOf(dd);
            for (uint i = 0; EnumDisplayDevices(null, i, ref dd, 0); i++)
            {
                if ((dd.StateFlags & 0x1) != 0) // attached to desktop
                {
                    DEVMODE cur = new DEVMODE();
                    cur.dmSize = (short)Marshal.SizeOf(typeof(DEVMODE));
                    if (EnumDisplaySettings(dd.DeviceName, ENUM_CURRENT_SETTINGS, ref cur))
                    {
                        DisplayInfo di = new DisplayInfo();
                        di.Device = dd.DeviceName;
                        di.Primary = (dd.StateFlags & 0x4) != 0;
                        di.Width = cur.dmPelsWidth; di.Height = cur.dmPelsHeight; di.CurrentHz = cur.dmDisplayFrequency;
                        int max = cur.dmDisplayFrequency;
                        DEVMODE m = new DEVMODE();
                        m.dmSize = (short)Marshal.SizeOf(typeof(DEVMODE));
                        for (int k = 0; EnumDisplaySettings(dd.DeviceName, k, ref m); k++)
                        {
                            if (m.dmPelsWidth == cur.dmPelsWidth && m.dmPelsHeight == cur.dmPelsHeight &&
                                m.dmBitsPerPel == cur.dmBitsPerPel && (m.dmDisplayFlags & DM_INTERLACED) == 0 &&
                                m.dmDisplayFrequency > max && m.dmDisplayFrequency < 1000)
                                max = m.dmDisplayFrequency;
                            if (k > 4000) break;
                        }
                        di.MaxHz = max;
                        DISPLAY_DEVICE mon = new DISPLAY_DEVICE();
                        mon.cb = Marshal.SizeOf(mon);
                        if (EnumDisplayDevices(dd.DeviceName, 0, ref mon, 0)) { di.Monitor = mon.DeviceString; di.MonitorId = mon.DeviceID; } else di.Monitor = dd.DeviceString;
                        list.Add(di);
                    }
                }
                dd = new DISPLAY_DEVICE();
                dd.cb = Marshal.SizeOf(dd);
            }
            return list;
        }

        /// <summary>Changes the refresh rate of a display (keeps resolution). Returns 0 on success.</summary>
        public static int SetRefreshRate(string device, int hz)
        {
            DEVMODE cur = new DEVMODE();
            cur.dmSize = (short)Marshal.SizeOf(typeof(DEVMODE));
            if (!EnumDisplaySettings(device, ENUM_CURRENT_SETTINGS, ref cur)) return -100;
            cur.dmDisplayFrequency = hz;
            cur.dmFields = DM_DISPLAYFREQUENCY;
            int test = ChangeDisplaySettingsEx(device, ref cur, IntPtr.Zero, 0x2 /*CDS_TEST*/, IntPtr.Zero);
            if (test != 0) return test;
            return ChangeDisplaySettingsEx(device, ref cur, IntPtr.Zero, 0x1 /*CDS_UPDATEREGISTRY*/, IntPtr.Zero);
        }

        // ---------------------------------------------------------- standby memory purge
        [StructLayout(LayoutKind.Sequential, Pack = 4)]
        struct TOKEN_PRIVILEGES { public int PrivilegeCount; public long Luid; public int Attributes; }
        [DllImport("advapi32.dll", SetLastError = true)] static extern bool OpenProcessToken(IntPtr h, uint access, out IntPtr token);
        [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)] static extern bool LookupPrivilegeValue(string sys, string name, out long luid);
        [DllImport("advapi32.dll", SetLastError = true)] static extern bool AdjustTokenPrivileges(IntPtr token, bool disableAll, ref TOKEN_PRIVILEGES state, int len, IntPtr prev, IntPtr retLen);
        [DllImport("kernel32.dll")] static extern IntPtr GetCurrentProcess();
        [DllImport("kernel32.dll", SetLastError = true)] static extern bool CloseHandle(IntPtr h);
        [DllImport("ntdll.dll")] static extern int NtSetSystemInformation(int infoClass, ref int info, int length);
        [DllImport("ntdll.dll")] static extern int NtQueryTimerResolution(out uint maximum, out uint minimum, out uint current);

        static bool EnablePrivilege(string name)
        {
            IntPtr token;
            if (!OpenProcessToken(GetCurrentProcess(), 0x20 | 0x8, out token)) return false;
            try
            {
                TOKEN_PRIVILEGES tp = new TOKEN_PRIVILEGES();
                tp.PrivilegeCount = 1; tp.Attributes = 0x2; // SE_PRIVILEGE_ENABLED
                if (!LookupPrivilegeValue(null, name, out tp.Luid)) return false;
                return AdjustTokenPrivileges(token, false, ref tp, 0, IntPtr.Zero, IntPtr.Zero) && Marshal.GetLastWin32Error() == 0;
            }
            finally { CloseHandle(token); }
        }

        /// <summary>Empties the standby list (cached memory). Returns NTSTATUS (0 = ok).</summary>
        public static int PurgeStandbyList()
        {
            EnablePrivilege("SeProfileSingleProcessPrivilege");
            int cmd = 4; // MemoryPurgeStandbyList
            return NtSetSystemInformation(80, ref cmd, 4); // SystemMemoryListInformation
        }

        /// <summary>Returns { currentMs, bestMs, worstMs }.</summary>
        public static double[] TimerResolution()
        {
            uint max, min, cur;
            if (NtQueryTimerResolution(out max, out min, out cur) != 0) return new double[] { 0, 0, 0 };
            return new double[] { cur / 10000.0, min / 10000.0, max / 10000.0 };
        }

        // ---------------------------------------------------------- processes
        [DllImport("kernel32.dll", SetLastError = true)] static extern IntPtr OpenProcess(uint access, bool inherit, int pid);
        [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)] static extern bool QueryFullProcessImageName(IntPtr h, int flags, StringBuilder name, ref int size);
        [DllImport("kernel32.dll", SetLastError = true)] static extern bool GetProcessTimes(IntPtr h, out long creation, out long exit, out long kernel, out long user);

        static long ProcTime(int pid, out string path)
        {
            path = null;
            IntPtr h = OpenProcess(0x1000, false, pid); // PROCESS_QUERY_LIMITED_INFORMATION
            if (h == IntPtr.Zero) return -1;
            try
            {
                StringBuilder sb = new StringBuilder(1024); int size = sb.Capacity;
                if (QueryFullProcessImageName(h, 0, sb, ref size)) path = sb.ToString();
                long c, e, k, u;
                if (GetProcessTimes(h, out c, out e, out k, out u)) return k + u;
                return -1;
            }
            finally { CloseHandle(h); }
        }

        public static List<ProcInfo> SnapshotProcesses(int sampleMs)
        {
            Dictionary<int, long> t0 = new Dictionary<int, long>();
            Process[] first = Process.GetProcesses();
            foreach (Process p in first)
            {
                string tmp; long t = ProcTime(p.Id, out tmp);
                t0[p.Id] = t;
            }
            Stopwatch sw = Stopwatch.StartNew();
            Thread.Sleep(sampleMs);
            Process[] procs = Process.GetProcesses();
            double elapsed = sw.Elapsed.TotalMilliseconds * 10000.0 * Environment.ProcessorCount; // in 100ns units
            List<ProcInfo> list = new List<ProcInfo>();
            foreach (Process p in procs)
            {
                try
                {
                    ProcInfo pi = new ProcInfo();
                    pi.Name = p.ProcessName; pi.Id = p.Id;
                    try { pi.WorkingSet = p.WorkingSet64; } catch { }
                    try { pi.SessionId = p.SessionId; } catch { }
                    string path; long t1 = ProcTime(p.Id, out path);
                    pi.Path = path;
                    long prev;
                    if (t1 >= 0 && t0.TryGetValue(p.Id, out prev) && prev >= 0 && elapsed > 0)
                        pi.Cpu = Math.Max(0, Math.Min(100, (t1 - prev) / elapsed * 100.0));
                    list.Add(pi);
                }
                catch { }
            }
            return list;
        }

        // ---------------------------------------------------------- files
        /// <summary>Returns { bytes, files } for a folder tree, skipping inaccessible parts.</summary>
        public static long[] DirSize(string path)
        {
            long bytes = 0, files = 0;
            if (String.IsNullOrEmpty(path) || !Directory.Exists(path)) return new long[] { 0, 0 };
            Stack<string> stack = new Stack<string>();
            stack.Push(path);
            while (stack.Count > 0)
            {
                string dir = stack.Pop();
                try
                {
                    DirectoryInfo di = new DirectoryInfo(dir);
                    foreach (FileInfo f in di.GetFiles()) { try { bytes += f.Length; files++; } catch { } }
                    foreach (DirectoryInfo d in di.GetDirectories())
                    {
                        if ((d.Attributes & FileAttributes.ReparsePoint) == 0) stack.Push(d.FullName);
                    }
                }
                catch { }
            }
            return new long[] { bytes, files };
        }

        /// <summary>Deletes the contents of a folder (not the folder). Files in use are skipped. Returns bytes freed.</summary>
        public static long DeleteContents(string path, string pattern)
        {
            long freed = 0;
            if (String.IsNullOrEmpty(path) || !Directory.Exists(path)) return 0;
            if (String.IsNullOrEmpty(pattern)) pattern = "*";
            DirectoryInfo root = new DirectoryInfo(path);
            try
            {
                foreach (FileInfo f in root.GetFiles(pattern))
                {
                    try { long l = f.Length; f.Attributes = FileAttributes.Normal; f.Delete(); freed += l; } catch { }
                }
                if (pattern == "*")
                {
                    foreach (DirectoryInfo d in root.GetDirectories())
                    {
                        if ((d.Attributes & FileAttributes.ReparsePoint) != 0) continue;
                        freed += DeleteContents(d.FullName, "*");
                        try { d.Delete(false); } catch { }
                    }
                }
            }
            catch { }
            return freed;
        }

        /// <summary>12-byte StartupApproved value (disabled = 0x03 + FILETIME).</summary>
        public static byte[] StartupApprovedValue(bool enabled)
        {
            byte[] b = new byte[12];
            b[0] = enabled ? (byte)0x02 : (byte)0x03;
            if (!enabled)
            {
                byte[] ft = BitConverter.GetBytes(DateTime.Now.ToFileTimeUtc());
                Array.Copy(ft, 0, b, 4, 8);
            }
            return b;
        }
    }

    // ------------------------------------------------------------------ network tests
    public class PingSeries
    {
        public string Host;
        public List<int> Rtts = new List<int>();   // -1 = lost
    }

    public class PingRunner
    {
        public volatile bool Running;
        public volatile bool Cancel;
        public List<PingSeries> Series = new List<PingSeries>();
        int _count, _interval;

        public PingRunner(string[] hosts)
        {
            foreach (string h in hosts) { PingSeries s = new PingSeries(); s.Host = h; Series.Add(s); }
        }

        public void Start(int count, int intervalMs)
        {
            _count = count; _interval = intervalMs; Running = true; Cancel = false;
            int remaining = Series.Count;
            object gate = new object();
            foreach (PingSeries s in Series)
            {
                PingSeries series = s;
                Thread t = new Thread(delegate ()
                {
                    using (Ping p = new Ping())
                    {
                        byte[] buf = new byte[32];
                        for (int i = 0; i < _count && !Cancel; i++)
                        {
                            int rtt = -1;
                            try
                            {
                                PingReply r = p.Send(series.Host, 1000, buf);
                                if (r.Status == IPStatus.Success) rtt = (int)r.RoundtripTime;
                            }
                            catch { }
                            lock (series.Rtts) series.Rtts.Add(rtt);
                            Thread.Sleep(_interval);
                        }
                    }
                    lock (gate) { remaining--; if (remaining == 0) Running = false; }
                });
                t.IsBackground = true;
                t.Start();
            }
            if (Series.Count == 0) Running = false;
        }

        public int[] Snapshot(int index)
        {
            PingSeries s = Series[index];
            lock (s.Rtts) return s.Rtts.ToArray();
        }

        /// <summary>Returns { avg, min, max, jitter, lossPercent, samples }.</summary>
        public static double[] Stats(int[] rtts)
        {
            List<int> ok = new List<int>();
            int lost = 0;
            foreach (int r in rtts) { if (r < 0) lost++; else ok.Add(r); }
            if (rtts.Length == 0) return new double[] { 0, 0, 0, 0, 0, 0 };
            double avg = 0, min = 0, max = 0, jit = 0;
            if (ok.Count > 0)
            {
                min = Double.MaxValue;
                foreach (int r in ok) { avg += r; if (r < min) min = r; if (r > max) max = r; }
                avg /= ok.Count;
                for (int i = 1; i < ok.Count; i++) jit += Math.Abs(ok[i] - ok[i - 1]);
                if (ok.Count > 1) jit /= (ok.Count - 1);
            }
            return new double[] { avg, min, max, jit, 100.0 * lost / rtts.Length, rtts.Length };
        }
    }

    /// <summary>Latency under load (bufferbloat) + download speed.</summary>
    public class LoadTest
    {
        public volatile bool Running;
        public volatile bool Cancel;
        public volatile string Phase = "idle";
        public volatile string Error;
        public long Bytes;
        public double LoadSeconds;
        public List<int> IdleRtts = new List<int>();
        public List<int> LoadedRtts = new List<int>();
        public string PingHost = "1.1.1.1";
        public string Url = "https://speed.cloudflare.com/__down?bytes=25000000";

        public void Start(int idleSeconds, int loadSeconds, int streams)
        {
            Running = true; Cancel = false; Error = null; Bytes = 0;
            Thread t = new Thread(delegate () { Run(idleSeconds, loadSeconds, streams); });
            t.IsBackground = true; t.Start();
        }

        void PingLoop(List<int> target, Func<bool> keepGoing)
        {
            using (Ping p = new Ping())
            {
                while (keepGoing() && !Cancel)
                {
                    int rtt = -1;
                    try { PingReply r = p.Send(PingHost, 1000); if (r.Status == IPStatus.Success) rtt = (int)r.RoundtripTime; } catch { }
                    lock (target) target.Add(rtt);
                    Thread.Sleep(200);
                }
            }
        }

        void Run(int idleSeconds, int loadSeconds, int streams)
        {
            try
            {
                try { ServicePointManager.SecurityProtocol |= (SecurityProtocolType)3072; } catch { }
                ServicePointManager.DefaultConnectionLimit = Math.Max(ServicePointManager.DefaultConnectionLimit, streams + 2);
                Phase = "idle";
                Stopwatch sw = Stopwatch.StartNew();
                PingLoop(IdleRtts, delegate () { return sw.Elapsed.TotalSeconds < idleSeconds; });
                if (Cancel) return;

                Phase = "load";
                Stopwatch lsw = Stopwatch.StartNew();
                List<Thread> workers = new List<Thread>();
                for (int i = 0; i < streams; i++)
                {
                    Thread w = new Thread(delegate ()
                    {
                        byte[] buf = new byte[65536];
                        while (lsw.Elapsed.TotalSeconds < loadSeconds && !Cancel)
                        {
                            try
                            {
                                HttpWebRequest req = (HttpWebRequest)WebRequest.Create(Url + "&r=" + Guid.NewGuid().ToString("N"));
                                req.UserAgent = "VeloxPC";
                                req.Timeout = 10000; req.ReadWriteTimeout = 10000;
                                using (WebResponse resp = req.GetResponse())
                                using (Stream s = resp.GetResponseStream())
                                {
                                    int n;
                                    while ((n = s.Read(buf, 0, buf.Length)) > 0)
                                    {
                                        Interlocked.Add(ref Bytes, n);
                                        if (lsw.Elapsed.TotalSeconds >= loadSeconds || Cancel) break;
                                    }
                                }
                            }
                            catch (Exception ex) { Error = ex.Message; Thread.Sleep(300); }
                        }
                    });
                    w.IsBackground = true; w.Start(); workers.Add(w);
                }
                Thread.Sleep(1500); // let the link saturate
                PingLoop(LoadedRtts, delegate () { return lsw.Elapsed.TotalSeconds < loadSeconds; });
                foreach (Thread w in workers) w.Join(12000);
                LoadSeconds = lsw.Elapsed.TotalSeconds;
                Phase = "done";
            }
            catch (Exception ex) { Error = ex.Message; Phase = "done"; }
            finally { Running = false; }
        }

        public double Mbps { get { return LoadSeconds > 0 ? (Interlocked.Read(ref Bytes) * 8.0 / 1000000.0) / LoadSeconds : 0; } }

        public double CurrentMbps(double seconds)
        {
            return seconds > 0 ? (Interlocked.Read(ref Bytes) * 8.0 / 1000000.0) / seconds : 0;
        }

        public static double Median(List<int> list)
        {
            List<int> ok = new List<int>();
            lock (list) { foreach (int r in list) if (r >= 0) ok.Add(r); }
            if (ok.Count == 0) return -1;
            ok.Sort();
            int m = ok.Count / 2;
            return ok.Count % 2 == 1 ? ok[m] : (ok[m - 1] + ok[m]) / 2.0;
        }
    }

    /// <summary>Raw UDP DNS query timing against a specific server.</summary>
    public static class DnsBench
    {
        static readonly Random Rng = new Random();

        public static double Query(string server, string domain, int timeoutMs)
        {
            try
            {
                byte[] packet = Build(domain);
                using (UdpClient udp = new UdpClient())
                {
                    udp.Client.ReceiveTimeout = timeoutMs;
                    IPEndPoint ep = new IPEndPoint(IPAddress.Parse(server), 53);
                    Stopwatch sw = Stopwatch.StartNew();
                    udp.Send(packet, packet.Length, ep);
                    IPEndPoint from = new IPEndPoint(IPAddress.Any, 0);
                    byte[] resp = udp.Receive(ref from);
                    sw.Stop();
                    if (resp.Length < 12 || resp[0] != packet[0] || resp[1] != packet[1]) return -1;
                    return sw.Elapsed.TotalMilliseconds;
                }
            }
            catch { return -1; }
        }

        /// <summary>Average of several rounds over several domains (after one warm-up). -1 if unreachable.</summary>
        public static double Benchmark(string server, string[] domains, int rounds)
        {
            double sum = 0; int n = 0;
            foreach (string d in domains) Query(server, d, 1500);
            for (int r = 0; r < rounds; r++)
                foreach (string d in domains)
                {
                    double ms = Query(server, d, 1500);
                    if (ms >= 0) { sum += ms; n++; }
                }
            return n == 0 ? -1 : sum / n;
        }

        static byte[] Build(string domain)
        {
            List<byte> b = new List<byte>();
            byte[] id = new byte[2]; lock (Rng) Rng.NextBytes(id);
            b.AddRange(id);
            b.AddRange(new byte[] { 0x01, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 });
            foreach (string label in domain.Split('.'))
            {
                byte[] l = Encoding.ASCII.GetBytes(label);
                b.Add((byte)l.Length); b.AddRange(l);
            }
            b.Add(0);
            b.AddRange(new byte[] { 0x00, 0x01, 0x00, 0x01 });
            return b.ToArray();
        }
    }
}
