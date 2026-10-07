// Original lab helper. SetupAPI ABI/constants are from Microsoft's SetupAPI.h.
// Selection requests a reboot and suppresses live ConfigMgr removal/reenumeration.
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;

public static class DeferredDeckDriver {
    const string Instance = @"PCI\VEN_1002&DEV_163F&SUBSYS_01231002&REV_AE\4&2E94418C&0&0041";
    const uint Compatible = 2, DontCallConfigMgr = 0x20000, NeedReboot = 0x100;
    const uint SingleInf = 0x10000, Quiet = 0x800000, AllowExcluded = 0x800;
    const uint NoFileCopy = 0x1000000;
    static readonly Guid DisplayClass = new Guid("4d36e968-e325-11ce-bfc1-08002be10318");

    [StructLayout(LayoutKind.Sequential)] public struct DeviceInfo {
        public uint cbSize; public Guid ClassGuid; public uint DevInst; public UIntPtr Reserved;
    }
    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)] public struct InstallParams {
        public uint cbSize, Flags, FlagsEx;
        public IntPtr hwndParent, InstallMsgHandler, InstallMsgHandlerContext, FileQueue;
        public UIntPtr ClassInstallReserved; public uint Reserved;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst=260)] public string DriverPath;
    }
    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)] public struct DriverInfo {
        public uint cbSize, DriverType; public UIntPtr Reserved;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst=256)] public string Description;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst=256)] public string Manufacturer;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst=256)] public string Provider;
        public System.Runtime.InteropServices.ComTypes.FILETIME DriverDate;
        public ulong DriverVersion;
    }
    public sealed class SelectionResult {
        public string InfPath, DriverStoreInfPath, Description, Provider; public ulong DriverVersion;
        public uint CompatibleCount, FinalFlags; public bool InstallationRequested, RestartRequired;
        public bool FileCopySuppressed;
    }
    [DllImport("setupapi.dll", SetLastError=true)] static extern IntPtr SetupDiCreateDeviceInfoList(ref Guid ClassGuid, IntPtr hwndParent);
    [DllImport("setupapi.dll", CharSet=CharSet.Unicode, SetLastError=true)] [return: MarshalAs(UnmanagedType.Bool)] static extern bool SetupDiOpenDeviceInfoW(IntPtr set, string instance, IntPtr hwnd, uint flags, ref DeviceInfo info);
    [DllImport("setupapi.dll", CharSet=CharSet.Unicode, SetLastError=true)] [return: MarshalAs(UnmanagedType.Bool)] static extern bool SetupDiGetDeviceInstallParamsW(IntPtr set, ref DeviceInfo info, ref InstallParams parameters);
    [DllImport("setupapi.dll", CharSet=CharSet.Unicode, SetLastError=true)] [return: MarshalAs(UnmanagedType.Bool)] static extern bool SetupDiSetDeviceInstallParamsW(IntPtr set, ref DeviceInfo info, ref InstallParams parameters);
    [DllImport("setupapi.dll", SetLastError=true)] [return: MarshalAs(UnmanagedType.Bool)] static extern bool SetupDiBuildDriverInfoList(IntPtr set, ref DeviceInfo info, uint type);
    [DllImport("setupapi.dll", CharSet=CharSet.Unicode, SetLastError=true)] [return: MarshalAs(UnmanagedType.Bool)] static extern bool SetupDiEnumDriverInfoW(IntPtr set, ref DeviceInfo info, uint type, uint index, ref DriverInfo driver);
    [DllImport("setupapi.dll", CharSet=CharSet.Unicode, SetLastError=true)] [return: MarshalAs(UnmanagedType.Bool)] static extern bool SetupDiSetSelectedDriverW(IntPtr set, ref DeviceInfo info, ref DriverInfo driver);
    [DllImport("setupapi.dll", SetLastError=true)] [return: MarshalAs(UnmanagedType.Bool)] static extern bool SetupDiCallClassInstaller(uint function, IntPtr set, ref DeviceInfo info);
    [DllImport("setupapi.dll", SetLastError=true)] [return: MarshalAs(UnmanagedType.Bool)] static extern bool SetupDiDestroyDriverInfoList(IntPtr set, ref DeviceInfo info, uint type);
    [DllImport("setupapi.dll", SetLastError=true)] [return: MarshalAs(UnmanagedType.Bool)] static extern bool SetupDiDestroyDeviceInfoList(IntPtr set);
    [DllImport("setupapi.dll", CharSet=CharSet.Unicode, SetLastError=true)] [return: MarshalAs(UnmanagedType.Bool)] static extern bool SetupGetInfDriverStoreLocationW(string inf, IntPtr alternate, string locale, StringBuilder buffer, uint size, out uint required);
    [DllImport("ntdll.dll")] public static extern int NtQuerySystemInformation(int infoClass, IntPtr buffer, int length, out int returnedLength);
    [DllImport("kernel32.dll")] public static extern uint SetThreadExecutionState(uint flags);

    static void Check(bool ok, string name) { if (!ok) throw new Win32Exception(Marshal.GetLastWin32Error(), name); }
    public static int[] StructureSizes() { return new int[] { Marshal.SizeOf(typeof(DeviceInfo)), Marshal.SizeOf(typeof(InstallParams)), Marshal.SizeOf(typeof(DriverInfo)) }; }
    public static string ResolveStagedInf(string inf) {
        inf = Path.GetFullPath(inf);
        StringBuilder buffer = new StringBuilder(260); uint required;
        Check(SetupGetInfDriverStoreLocationW(inf, IntPtr.Zero, null, buffer, (uint)buffer.Capacity, out required), "Resolve published INF to DriverStore");
        string staged = Path.GetFullPath(buffer.ToString());
        string root = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), @"DriverStore\FileRepository") + Path.DirectorySeparatorChar;
        if (!staged.StartsWith(root, StringComparison.OrdinalIgnoreCase) || !File.Exists(staged)) throw new InvalidOperationException("The INF is not an existing staged DriverStore package.");
        return staged;
    }
    public static SelectionResult Inspect(string inf) { return Run(inf, false, null); }
    // Caller must hash-check the staged payload and shared system destinations
    // before selecting: NOFILECOPY is only appropriate for an existing package.
    public static SelectionResult SelectForReboot(string inf) { return Run(inf, true, null); }
    public static SelectionResult SelectForReboot(string inf, Action<string> progress) { return Run(inf, true, progress); }
    static SelectionResult Run(string inf, bool install, Action<string> progress) {
        if (IntPtr.Size != 8) throw new InvalidOperationException("Use 64-bit Windows PowerShell.");
        inf = Path.GetFullPath(inf);
        if (!File.Exists(inf) || inf.Length >= 260) throw new ArgumentException("Missing or excessively long INF path.");
        string staged = ResolveStagedInf(inf);
        int[] sizes = StructureSizes();
        if (sizes[0] != 32 || sizes[1] != 584 || sizes[2] != 1568) throw new InvalidOperationException("Unexpected SetupAPI structure ABI.");
        Guid cls = DisplayClass;
        IntPtr set = SetupDiCreateDeviceInfoList(ref cls, IntPtr.Zero);
        if (set == new IntPtr(-1)) throw new Win32Exception(Marshal.GetLastWin32Error());
        DeviceInfo device = new DeviceInfo(); device.cbSize = (uint)sizes[0];
        bool built = false;
        try {
            Check(SetupDiOpenDeviceInfoW(set, Instance, IntPtr.Zero, 0, ref device), "Open exact LCD Deck GPU");
            InstallParams parameters = new InstallParams(); parameters.cbSize = (uint)sizes[1];
            Check(SetupDiGetDeviceInstallParamsW(set, ref device, ref parameters), "Get installation parameters");
            parameters.DriverPath = staged;
            parameters.Flags |= SingleInf | Quiet;
            parameters.FlagsEx |= AllowExcluded;
            Check(SetupDiSetDeviceInstallParamsW(set, ref device, ref parameters), "Set private INF search");
            Check(SetupDiBuildDriverInfoList(set, ref device, Compatible), "Enumerate compatible INF model");
            built = true;
            List<DriverInfo> drivers = new List<DriverInfo>();
            for (uint i=0; ; i++) {
                DriverInfo driver = new DriverInfo(); driver.cbSize = (uint)sizes[2];
                if (!SetupDiEnumDriverInfoW(set, ref device, Compatible, i, ref driver)) {
                    int error = Marshal.GetLastWin32Error();
                    if (error != 259) throw new Win32Exception(error, "Enumerate exact driver");
                    break;
                }
                drivers.Add(driver);
            }
            if (drivers.Count != 1) throw new InvalidOperationException("Expected exactly one compatible model in the verified INF; found " + drivers.Count);
            DriverInfo chosen = drivers[0];
            SelectionResult result = new SelectionResult();
            result.InfPath = inf; result.DriverStoreInfPath = staged; result.Description = chosen.Description;
            result.Provider = chosen.Provider; result.DriverVersion = chosen.DriverVersion;
            result.CompatibleCount = (uint)drivers.Count;
            if (!install) return result;
            if (progress != null) progress("SelectVerifiedModel");
            Check(SetupDiSetSelectedDriverW(set, ref device, ref chosen), "Select verified driver model");
            // Register the selected package's co-installers/interfaces, then install.
            // Reapply the no-live-restart flags before every DIF operation.
            foreach (uint request in new uint[] { 0x22, 0x20, 0x02 }) {
                parameters = new InstallParams(); parameters.cbSize = (uint)sizes[1];
                Check(SetupDiGetDeviceInstallParamsW(set, ref device, ref parameters), "Refresh installation parameters");
                parameters.Flags |= DontCallConfigMgr | NeedReboot | Quiet | NoFileCopy;
                Check(SetupDiSetDeviceInstallParamsW(set, ref device, ref parameters), "Defer device restart");
                if (progress != null) progress("BeforeDIF" + request.ToString("X"));
                Check(SetupDiCallClassInstaller(request, set, ref device), "Install DIF " + request.ToString("X"));
                if (progress != null) progress("AfterDIF" + request.ToString("X"));
            }
            parameters = new InstallParams(); parameters.cbSize = (uint)sizes[1];
            Check(SetupDiGetDeviceInstallParamsW(set, ref device, ref parameters), "Read final restart flags");
            result.FinalFlags = parameters.Flags;
            result.RestartRequired = (parameters.Flags & (NeedReboot | 0x80)) != 0;
            result.InstallationRequested = true;
            result.FileCopySuppressed = (parameters.Flags & NoFileCopy) != 0;
            if (!result.RestartRequired) throw new InvalidOperationException("Deferred installation did not request a reboot.");
            if (!result.FileCopySuppressed) throw new InvalidOperationException("The installer cleared the no-file-copy setting.");
            return result;
        } finally {
            if (built) SetupDiDestroyDriverInfoList(set, ref device, Compatible);
            SetupDiDestroyDeviceInfoList(set);
        }
    }
}
