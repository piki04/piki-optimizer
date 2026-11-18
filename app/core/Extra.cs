// Piki Optimizer 2.0 - small helpers that need WPF (motion curve) or raw speed (read-only measurements).
// Compiled once and cached like Native.cs. If it ever fails to compile the app falls back to built-in easing.
using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Media.Animation;
using Microsoft.Win32.SafeHandles;

namespace VeloxPC
{
    // cubic-bezier(x1, y1, x2, y2) like CSS: the Piki site curve is (.22, 1, .36, 1)
    public class BezierEase : EasingFunctionBase
    {
        public double X1 = 0.22, Y1 = 1, X2 = 0.36, Y2 = 1;
        public BezierEase() { EasingMode = EasingMode.EaseIn; }   // EaseIn = curve used as written
        public BezierEase(double x1, double y1, double x2, double y2) : this() { X1 = x1; Y1 = y1; X2 = x2; Y2 = y2; }
        protected override double EaseInCore(double t)
        {
            if (t <= 0) return 0; if (t >= 1) return 1;
            // solve x(u) = t with Newton, then return y(u)
            double u = t;
            for (int i = 0; i < 8; i++)
            {
                double x = Bez(u, X1, X2) - t;
                double d = Der(u, X1, X2);
                if (Math.Abs(x) < 1e-5) break;
                if (Math.Abs(d) < 1e-6) break;
                u -= x / d;
                if (u < 0) u = 0; if (u > 1) u = 1;
            }
            return Bez(u, Y1, Y2);
        }
        static double Bez(double u, double a, double b) { double v = 1 - u; return 3 * v * v * u * a + 3 * v * u * u * b + u * u * u; }
        static double Der(double u, double a, double b) { double v = 1 - u; return 3 * v * v * a + 6 * v * u * (b - a) + 3 * u * u * (1 - b); }
        protected override Freezable CreateInstanceCore() { return new BezierEase(X1, Y1, X2, Y2); }
    }

    public static class Extra
    {
        [DllImport("kernel32.dll")] static extern bool SetProcessWorkingSetSize(IntPtr proc, IntPtr min, IntPtr max);
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        static extern SafeFileHandle CreateFile(string name, uint access, uint share, IntPtr sec, uint disp, uint flags, IntPtr template);
        [DllImport("kernel32.dll", SetLastError = true)] static extern bool ReadFile(SafeFileHandle h, IntPtr buf, uint n, out uint read, IntPtr ov);
        [DllImport("kernel32.dll", SetLastError = true)] static extern bool SetFilePointerEx(SafeFileHandle h, long dist, IntPtr newPos, uint method);
        [DllImport("kernel32.dll")] static extern IntPtr VirtualAlloc(IntPtr addr, UIntPtr size, uint type, uint protect);
        [DllImport("kernel32.dll")] static extern bool VirtualFree(IntPtr addr, UIntPtr size, uint type);

        // gives unused memory pages of this process back to Windows (used when the app goes to the tray)
        public static void TrimWorkingSet()
        {
            try { SetProcessWorkingSetSize(Process.GetCurrentProcess().Handle, new IntPtr(-1), new IntPtr(-1)); } catch { }
        }

        // single-thread CPU score: integer + floating point loop for `ms` milliseconds, iterations per ms
        public static double CpuBench(int ms)
        {
            var sw = Stopwatch.StartNew();
            long it = 0; double acc = 1.0; uint x = 2463534242;
            while (sw.ElapsedMilliseconds < ms)
            {
                for (int i = 0; i < 20000; i++)
                {
                    x ^= x << 13; x ^= x >> 17; x ^= x << 5;
                    acc = acc * 1.0000001 + (x & 1023) * 1e-9;
                }
                it += 20000;
            }
            if (acc < 0) it++;   // keep the loop from being optimised away
            return it / (double)sw.ElapsedMilliseconds;
        }

        // 4 KB random reads that bypass the Windows cache, on a temporary file of `mb` MB. Returns MB/s (-1 on error).
        // The file is created in `dir` and always deleted.
        public static double DiskRandomRead(string dir, int mb, int ms)
        {
            string path = Path.Combine(dir, "piki-disktest-" + Guid.NewGuid().ToString("N").Substring(0, 8) + ".tmp");
            IntPtr buf = IntPtr.Zero;
            try
            {
                byte[] chunk = new byte[1024 * 1024];
                new Random(7).NextBytes(chunk);
                using (var fs = new FileStream(path, FileMode.CreateNew, FileAccess.Write, FileShare.None, 1 << 16, FileOptions.WriteThrough))
                {
                    for (int i = 0; i < mb; i++) fs.Write(chunk, 0, chunk.Length);
                    fs.Flush(true);
                }
                const uint GENERIC_READ = 0x80000000, OPEN_EXISTING = 3, NO_BUFFERING = 0x20000000, RANDOM = 0x10000000;
                buf = VirtualAlloc(IntPtr.Zero, new UIntPtr(4096), 0x3000, 0x04);
                long blocks = (long)mb * 256;
                var rnd = new Random(11);
                long bytes = 0;
                using (var h = CreateFile(path, GENERIC_READ, 1, IntPtr.Zero, OPEN_EXISTING, NO_BUFFERING | RANDOM, IntPtr.Zero))
                {
                    if (h.IsInvalid) return -1;
                    var sw = Stopwatch.StartNew();
                    while (sw.ElapsedMilliseconds < ms)
                    {
                        long off = (long)(rnd.NextDouble() * blocks) * 4096;
                        uint read;
                        if (!SetFilePointerEx(h, off, IntPtr.Zero, 0)) break;
                        if (!ReadFile(h, buf, 4096, out read, IntPtr.Zero) || read == 0) break;
                        bytes += read;
                    }
                    double secs = sw.Elapsed.TotalSeconds;
                    return secs > 0 ? bytes / 1048576.0 / secs : -1;
                }
            }
            catch { return -1; }
            finally
            {
                if (buf != IntPtr.Zero) VirtualFree(buf, UIntPtr.Zero, 0x8000);
                try { if (File.Exists(path)) File.Delete(path); } catch { }
            }
        }
    }
}
