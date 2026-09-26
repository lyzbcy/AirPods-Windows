$ErrorActionPreference='Stop'
function Get-ActiveRenderEndpoints {
    if (-not ('APBRepair.Audio' -as [type])) {
        Add-Type @'
using System; using System.Collections.Generic; using System.Runtime.InteropServices;
namespace APBRepair {
 [ComImport,Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")] class Enumerator {}
 [ComImport,Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"),InterfaceType(ComInterfaceType.InterfaceIsIUnknown)] interface IEnum {
  [PreserveSig] int EnumAudioEndpoints(int flow,uint mask,out ICollection list);
 }
 [ComImport,Guid("0BD7A1BE-7A1A-44DB-8397-CC5392387B5E"),InterfaceType(ComInterfaceType.InterfaceIsIUnknown)] interface ICollection {
  [PreserveSig] int GetCount(out uint count); [PreserveSig] int Item(uint index,out IDevice device);
 }
 [ComImport,Guid("D666063F-1587-4E43-81F1-B948E807363F"),InterfaceType(ComInterfaceType.InterfaceIsIUnknown)] interface IDevice {
  [PreserveSig] int Activate(ref Guid id,uint context,IntPtr parameters,out IntPtr result);
  [PreserveSig] int OpenPropertyStore(uint access,out IntPtr store); [PreserveSig] int GetId([MarshalAs(UnmanagedType.LPWStr)]out string id);
 }
 public static class Audio {
  public static string[] ActiveRenderIds() {
   var e=(IEnum)new Enumerator();ICollection c=null;var ids=new List<string>();
   try {Marshal.ThrowExceptionForHR(e.EnumAudioEndpoints(0,1,out c));uint n;Marshal.ThrowExceptionForHR(c.GetCount(out n));
    for(uint i=0;i<n;i++){IDevice d=null;try{Marshal.ThrowExceptionForHR(c.Item(i,out d));string id;Marshal.ThrowExceptionForHR(d.GetId(out id));ids.Add(id);}finally{if(d!=null)Marshal.ReleaseComObject(d);}}
   } finally {if(c!=null)Marshal.ReleaseComObject(c);Marshal.ReleaseComObject(e);}return ids.ToArray();
  }
 }
}
'@
    }
    return @([APBRepair.Audio]::ActiveRenderIds())
}
function Invoke-TargetedRepair {
    param([string]$InstanceId,[string]$EndpointId,[scriptblock]$Disable,[scriptblock]$Enable,[scriptblock]$Probe,[scriptblock]$Wait)
    if ($InstanceId -notmatch '^BTHENUM\\' -or $EndpointId -notmatch '^\{0\.0\.0\.') { throw 'Exact Bluetooth node and render endpoint required' }
    try {
        & $Disable $InstanceId
        & $Wait
    } finally { & $Enable $InstanceId }
    & $Wait
    return @(& $Probe) -contains $EndpointId
}
Export-ModuleMember -Function Get-ActiveRenderEndpoints,Invoke-TargetedRepair
