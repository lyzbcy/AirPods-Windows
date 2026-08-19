# AirPods 降噪/通透模式切换（Windows 原生实现）
# 原理：通过 Classic Bluetooth L2CAP 连接 Apple 私有服务
#   74ec2172-0bad-4d01-8f77-997b2be0722a，
#   写入控制指令 04 00 04 00 09 00 0D <mode> 00 00 00 00。
# 协议事实来自 librepods 项目的逆向文档（GPLv3，本项目仅引用协议规范，
# 实现为独立编写，致谢见 README）。
# 用法: powershell -File noise_mode.ps1 -Mac "00:11:22:33:44:55" -Mode anc
#   Mode: off | anc | trans | adapt
param(
    [Parameter(Mandatory=$true)][string]$Mac,
    [Parameter(Mandatory=$true)][ValidateSet("off","anc","trans","adapt")][string]$Mode
)
$ErrorActionPreference = "Stop"

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public class AirPodsL2Cap {
    // ---- Winsock / Bluetooth 常量 ----
    const int AF_BTH = 32;
    const int SOCK_STREAM = 1;
    const int BTHPROTO_L2CAP = 0x0100;
    const int NS_BTH = 16;
    const int LUP_RETURN_ADDR = 0x0100;

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct WSAQUERYSETW {
        public int dwSize;
        public string lpszServiceInstanceName;
        public IntPtr lpServiceClassId;
        public IntPtr lpVersion;
        public string lpszComment;
        public int dwNameSpace;
        public IntPtr lpNSProviderId;
        public string lpszContext;
        public int dwNumberOfProtocols;
        public IntPtr lpafpProtocols;
        public string lpszQueryString;
        public int dwNumberOfCsAddrs;
        public IntPtr lpcsaBuffer;
        public int dwOutputFlags;
        public IntPtr lpBlob;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct SOCKADDR_BTH {
        public short addressFamily;
        public ulong btAddr;
        public Guid serviceClassId;
        public int port;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct CSADDR_INFO {
        public IntPtr Local;
        public IntPtr Remote;
        public int iSocketType;
        public int iProtocol;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct WSAData { public short wVersion, wHighVersion; public IntPtr iMaxSockets_desc; public short iMaxSockets; public short iMaxUdpDg; public IntPtr lpVendorInfo; public char szDescription; public char szSystemStatus; }

    [DllImport("ws2_32.dll")] static extern int WSAStartup(short v, out WSAData d);
    [DllImport("ws2_32.dll")] static extern int WSACleanup();
    [DllImport("ws2_32.dll", CharSet = CharSet.Unicode)]
    static extern int WSALookupServiceBeginW(ref WSAQUERYSETW q, int flags, out IntPtr h);
    [DllImport("ws2_32.dll", CharSet = CharSet.Unicode)]
    static extern int WSALookupServiceNextW(IntPtr h, int flags, ref int len, IntPtr buf);
    [DllImport("ws2_32.dll")] static extern int WSALookupServiceEnd(IntPtr h);
    [DllImport("ws2_32.dll")] static extern int socket(int af, int type, int proto);
    [DllImport("ws2_32.dll")] static extern int connect(int s, byte[] name, int namelen);
    [DllImport("ws2_32.dll")] static extern int send(int s, byte[] buf, int len, int flags);
    [DllImport("ws2_32.dll")] static extern int closesocket(int s);
    [DllImport("ws2_32.dll")] static extern int WSAGetLastError();

    static ulong MacToUlong(string mac) {
        ulong v = 0;
        foreach (string part in mac.Split(':')) {
            v = (v << 8) | ulong.Parse(part, System.Globalization.NumberStyles.HexNumber);
        }
        return v;
    }

    public static string SendCommand(string mac, byte[] payload) {
        WSAData wd;
        if (WSAStartup(0x0202, out wd) != 0) throw new Exception("WSAStartup failed");
        try {
            // 1) SDP 查询：该设备上 Apple 服务的 L2CAP PSM
            Guid appleSvc = new Guid("74ec2172-0bad-4d01-8f77-997b2be0722a");
            IntPtr pGuid = Marshal.AllocHGlobal(Marshal.SizeOf(typeof(Guid)));
            Marshal.StructureToPtr(appleSvc, pGuid, false);
            IntPtr h;
            var q = new WSAQUERYSETW();
            q.dwSize = Marshal.SizeOf(typeof(WSAQUERYSETW));
            q.lpServiceClassId = pGuid;
            q.dwNameSpace = NS_BTH;
            q.lpszContext = mac;   // 限定在这台耳机上查
            int rc = WSALookupServiceBeginW(ref q, LUP_RETURN_ADDR, out h);
            Marshal.FreeHGlobal(pGuid);
            if (rc != 0) throw new Exception("SDP lookup begin failed, err=" + WSAGetLastError());

            int len = 4096;
            IntPtr buf = Marshal.AllocHGlobal(len);
            SOCKADDR_BTH sa = new SOCKADDR_BTH();
            try {
                rc = WSALookupServiceNextW(h, LUP_RETURN_ADDR, ref len, buf);
                if (rc != 0) throw new Exception("SDP lookup next failed, err=" + WSAGetLastError());
                var res = Marshal.PtrToStructure<WSAQUERYSETW>(buf);
                if (res.lpcsaBuffer == IntPtr.Zero) throw new Exception("no csaddr in SDP result");
                var csa = Marshal.PtrToStructure<CSADDR_INFO>(res.lpcsaBuffer);
                if (csa.Remote == IntPtr.Zero) throw new Exception("no remote sockaddr in SDP result");
                sa = Marshal.PtrToStructure<SOCKADDR_BTH>(csa.Remote);
            } finally {
                Marshal.FreeHGlobal(buf);
                WSALookupServiceEnd(h);
            }
            if (sa.port <= 0) throw new Exception("PSM not resolved");

            // 2) 连接 L2CAP
            int s = socket(AF_BTH, SOCK_STREAM, BTHPROTO_L2CAP);
            if (s < 0) throw new Exception("socket failed, err=" + WSAGetLastError());
            try {
                var target = new SOCKADDR_BTH();
                target.addressFamily = AF_BTH;
                target.btAddr = MacToUlong(mac);
                target.port = sa.port;
                int saLen = Marshal.SizeOf(typeof(SOCKADDR_BTH));
                byte[] saBuf = new byte[saLen];
                IntPtr pSa = Marshal.AllocHGlobal(saLen);
                Marshal.StructureToPtr(target, pSa, false);
                Marshal.Copy(pSa, saBuf, 0, saLen);
                Marshal.FreeHGlobal(pSa);
                if (connect(s, saBuf, saLen) != 0)
                    throw new Exception("L2CAP connect failed, err=" + WSAGetLastError() + "（耳机可能未连接）");
                int sent = send(s, payload, payload.Length, 0);
                if (sent != payload.Length)
                    throw new Exception("send incomplete (" + sent + "/" + payload.Length + ")");
                return "OK psm=" + sa.port + " sent=" + sent;
            } finally {
                closesocket(s);
            }
        } finally {
            WSACleanup();
        }
    }
}
"@

$payloadMap = @{
    "off"    = [byte[]](0x04,0x00,0x04,0x00,0x09,0x00,0x0D,0x01,0x00,0x00,0x00)
    "anc"    = [byte[]](0x04,0x00,0x04,0x00,0x09,0x00,0x0D,0x02,0x00,0x00,0x00)
    "trans"  = [byte[]](0x04,0x00,0x04,0x00,0x09,0x00,0x0D,0x03,0x00,0x00,0x00)
    "adapt"  = [byte[]](0x04,0x00,0x04,0x00,0x09,0x00,0x0D,0x04,0x00,0x00,0x00)
}
try {
    $r = [AirPodsL2Cap]::SendCommand($Mac.ToUpper(), $payloadMap[$Mode])
    Write-Output $r
    exit 0
} catch {
    Write-Output ("FAIL: " + $_.Exception.Message)
    exit 1
}
