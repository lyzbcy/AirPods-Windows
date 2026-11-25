using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using Microsoft.Win32.SafeHandles;

namespace AirPodsBuddy.Beta;

public sealed record Device(string Path, string Name)
{
    public string Key => Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(Path.ToUpperInvariant())))[..16];
    public override string ToString() => $"{Name} · {Key[..6]}";
}

public static class Driver
{
    // Experimental compatibility ABI; no driver binaries or third-party implementation bundled.
    // Verified in official 2024-06-06 driver: WDF device-interface registration.
    // 74ec2172... is the Bluetooth SERVICE UUID, not the Win32 device-interface GUID.
    static readonly Guid InterfaceId = new("9eec98bb-3c54-45d4-a843-7900c4635e08");
    [StructLayout(LayoutKind.Sequential)] struct InterfaceData { public int Size; public Guid Guid; public int Flags; public IntPtr Reserved; }
    [StructLayout(LayoutKind.Sequential)] struct DevData { public int Size; public Guid Class; public uint Instance; public IntPtr Reserved; }
    [DllImport("setupapi.dll", CharSet = CharSet.Unicode, SetLastError = true)] static extern IntPtr SetupDiGetClassDevsW(ref Guid guid, string? enumerator, IntPtr parent, int flags);
    [DllImport("setupapi.dll", SetLastError = true)] static extern bool SetupDiEnumDeviceInterfaces(IntPtr set, IntPtr dev, ref Guid guid, uint index, ref InterfaceData data);
    [DllImport("setupapi.dll", CharSet = CharSet.Unicode, SetLastError = true)] static extern bool SetupDiGetDeviceInterfaceDetailW(IntPtr set, ref InterfaceData data, IntPtr detail, uint size, out uint needed, ref DevData dev);
    [DllImport("setupapi.dll")] static extern bool SetupDiDestroyDeviceInfoList(IntPtr set);
    [DllImport("cfgmgr32.dll")] static extern uint CM_Get_Parent(out uint parent, uint node, uint flags);
    [DllImport("cfgmgr32.dll", CharSet = CharSet.Unicode)] static extern uint CM_Get_DevNode_Registry_PropertyW(uint node, uint property, out uint type, byte[] buffer, ref uint length, uint flags);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)] static extern SafeFileHandle CreateFileW(string path, uint access, uint share, IntPtr security, uint disposition, uint flags, IntPtr template);

    public static IReadOnlyList<Device> Probe()
    {
        var guid = InterfaceId;
        var set = SetupDiGetClassDevsW(ref guid, null, IntPtr.Zero, 0x12);
        if (set == new IntPtr(-1)) throw new Win32Exception(Marshal.GetLastWin32Error());
        var found = new List<Device>();
        try
        {
            for (uint i = 0; i < 64; i++)
            {
                var data = new InterfaceData { Size = Marshal.SizeOf<InterfaceData>() };
                if (!SetupDiEnumDeviceInterfaces(set, IntPtr.Zero, ref guid, i, ref data))
                {
                    int error = Marshal.GetLastWin32Error();
                    if (error == 259) break;
                    throw new Win32Exception(error);
                }
                var dev = new DevData { Size = Marshal.SizeOf<DevData>() };
                SetupDiGetDeviceInterfaceDetailW(set, ref data, IntPtr.Zero, 0, out uint needed, ref dev);
                if (needed < 8 || needed > 65536) throw new IOException("Invalid interface detail size");
                var detail = Marshal.AllocHGlobal((int)needed);
                try
                {
                    Marshal.WriteInt32(detail, IntPtr.Size == 8 ? 8 : 6);
                    if (!SetupDiGetDeviceInterfaceDetailW(set, ref data, detail, needed, out _, ref dev)) throw new Win32Exception(Marshal.GetLastWin32Error());
                    string path = Marshal.PtrToStringUni(detail + 4) ?? throw new IOException("Missing interface path");
                    found.Add(new Device(path, FindName(dev.Instance)));
                }
                finally { Marshal.FreeHGlobal(detail); }
            }
        }
        finally { SetupDiDestroyDeviceInfoList(set); }
        return found.DistinctBy(x => x.Path, StringComparer.OrdinalIgnoreCase).ToArray();
    }

    static string FindName(uint node)
    {
        string fallback = "AAP 控制设备（型号待选择）";
        for (int level = 0; level < 5; level++)
        {
            foreach (uint property in new uint[] { 13, 1 }) // CM_DRP_FRIENDLYNAME / DEVICEDESC
            {
                byte[] buffer = new byte[2048]; uint size = (uint)buffer.Length;
                if (CM_Get_DevNode_Registry_PropertyW(node, property, out uint type, buffer, ref size, 0) == 0 && type == 1)
                {
                    string name = Encoding.Unicode.GetString(buffer, 0, (int)Math.Min(size, (uint)buffer.Length)).TrimEnd('\0');
                    if (name.Contains("AirPods", StringComparison.OrdinalIgnoreCase)) return name;
                }
            }
            if (CM_Get_Parent(out uint parent, node, 0) != 0) break;
            node = parent;
        }
        return fallback;
    }

    public static IChannel Open(Device selected)
    {
        // Re-enumerate to reject arbitrary persisted paths and disappeared devices.
        if (!Probe().Any(x => x.Path.Equals(selected.Path, StringComparison.OrdinalIgnoreCase))) throw new IOException("Selected interface disappeared");
        var handle = CreateFileW(selected.Path, 0xC0000000, 3, IntPtr.Zero, 3, 0x40000000, IntPtr.Zero);
        if (handle.IsInvalid) { int code = Marshal.GetLastWin32Error(); handle.Dispose(); throw new Win32Exception(code); }
        try { return new DeviceChannel(new FileStream(handle, FileAccess.ReadWrite, 1, true)); }
        catch { handle.Dispose(); throw; }
    }
}

sealed class DeviceChannel(FileStream stream) : IChannel
{
    int disposed;
    public async Task WriteAsync(byte[] packet, CancellationToken token) => await stream.WriteAsync(packet.AsMemory(), token);
    public async Task<byte[]> ReadAsync(CancellationToken token)
    {
        byte[] bytes = new byte[4096];
        int count = await stream.ReadAsync(bytes.AsMemory(), token);
        return bytes[..count];
    }
    public ValueTask DisposeAsync()
    {
        if (Interlocked.Exchange(ref disposed, 1) == 0) stream.Dispose();
        return ValueTask.CompletedTask;
    }
}
