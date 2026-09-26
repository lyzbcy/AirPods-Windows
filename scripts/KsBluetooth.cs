/*
MIT License

Copyright (c) 2026 Jeremy Leff

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
*/
// Windows KS Bluetooth audio backend. No service/driver install, radio reset or pairing mutation.
// Topology/KS approach: m2jean/ToothTray (BSD-2-Clause), jeremyleff/BTAudioSysTrayTool (MIT).
// Interop adapted and hardened from BTAudioSysTrayTool; see THIRD_PARTY_NOTICES.md.
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
namespace AirPodsBuddy.Ks {
 public sealed class Endpoint {
  public string Id; public string Name; public string ContainerId; public string FilterId;
  public int Flow; public uint State; public bool ReconnectSupported; public bool DisconnectSupported;
  public string Error;
 }
 public sealed class RequestResult {
  public bool Accepted; public int Requested; public string Error; public string RenderId; public string CaptureId;
  // Diagnostic-only, UTC FILETIME ticks shared with the read-only state sampler.
  public string KsTrace=""; public string TargetEndpoints="";
 }
 public interface IBackend {
  Endpoint[] List(string container); int Send(string endpointId, uint property);
 }
 // Pure transaction policy is shared by the native backend and fault-injection tests.
 public static class Policy {
  public static Endpoint SelectRender(Endpoint[] rows, string container) {
   Guid target; if(!Guid.TryParse(container,out target)||target==Guid.Empty)throw new ArgumentException("Invalid target container");
   var render=new List<Endpoint>();
   foreach(var ep in rows) {
    Guid c; if(!Guid.TryParse(ep.ContainerId,out c)||c!=target||ep.Flow!=0||(ep.State!=1&&ep.State!=8))continue;
    string filter=(ep.FilterId??"").ToUpperInvariant();
    // Do not promote a known HFP filter to a stereo render route.
    if(filter.Contains("BTHHFENUM")||filter.Contains("0000111E"))continue;
    render.Add(ep);
   }
   if(render.Count!=1)throw new InvalidOperationException(render.Count==0?"No usable target render endpoint":"Ambiguous target render endpoints");
   return render[0];
  }
  public static RequestResult Run(IBackend backend,string container,bool connect,bool microphone) {
   var result=new RequestResult();var rows=backend.List(container);
   Guid target; if(!Guid.TryParse(container,out target)||target==Guid.Empty)throw new ArgumentException("Invalid target container");
   Endpoint render=null;
   if(connect){render=SelectRender(rows,container);result.RenderId=render.Id;}
   var pending=new List<Endpoint>();var filters=new HashSet<string>(StringComparer.OrdinalIgnoreCase);
   foreach(var ep in rows) {
    Guid c;if(!Guid.TryParse(ep.ContainerId,out c)||c!=target)continue;
    if(ep.State!=1&&ep.State!=8)continue; // never enable user-disabled/absent devices
    if(!connect&&(ep.Flow==0||ep.Flow==1)) {
     if(result.TargetEndpoints.Length>0)result.TargetEndpoints+=";";
     result.TargetEndpoints+=ep.Flow+"|"+ep.Id;
    }
    if(connect&&ep.Flow==0&&ep.Id!=render.Id)continue;
    if(connect&&ep.Flow==1&&!microphone)continue;
    if(ep.Flow==1&&String.IsNullOrEmpty(result.CaptureId))result.CaptureId=ep.Id;
    // UNPLUGGED audio does not prove the Bluetooth/control link is down.
    // Explicit disconnect must reach every target driver filter, even in state 8.
    bool already=connect&&ep.State==1;
    if(already)continue;
    if(!(connect?ep.ReconnectSupported:ep.DisconnectSupported)) {
     result.Error="Target driver does not support requested KS operation";return result;
    }
    if(String.IsNullOrEmpty(ep.FilterId)){result.Error="Target filter identity missing";return result;}
    if(filters.Add(ep.FilterId))pending.Add(ep);
   }
  // Finish all preflight checks before the first state-changing request.
  if(!connect&&result.TargetEndpoints.Length==0){result.Error="No target audio endpoints to verify";return result;}
   foreach(var ep in pending) {
    long before=DateTime.UtcNow.ToFileTimeUtc();
    int hr;
    try {hr=backend.Send(ep.Id,connect?0u:1u);}
    catch(Exception ex) {
     long failedAt=DateTime.UtcNow.ToFileTimeUtc();result.Requested++;
     if(result.KsTrace.Length>0)result.KsTrace+=";";
     result.KsTrace+=before+","+failedAt+","+(connect?0:1)+","+ep.Id+",0x"+ex.HResult.ToString("X8");
     result.Error="KS request exception HRESULT=0x"+ex.HResult.ToString("X8");return result;
    }
    long after=DateTime.UtcNow.ToFileTimeUtc();result.Requested++;
    if(result.KsTrace.Length>0)result.KsTrace+=";";
    result.KsTrace+=before+","+after+","+(connect?0:1)+","+ep.Id+",0x"+hr.ToString("X8");
    if(hr<0){result.Error="KS request failed HRESULT=0x"+hr.ToString("X8");return result;}
   }
   result.Accepted=true; // submission only; caller MUST verify live endpoint/link state
   return result;
  }
 }
 public sealed class NativeBackend : IBackend {
  private Guid boundContainer=Guid.Empty;
  static readonly Guid BtAudio=new Guid("7FA06C40-B8F6-4C7E-8556-E8C33A12E54D");
  static readonly Guid TopologyId=new Guid("2A07407E-6497-4A18-9787-32F79BD0D98F");
  static readonly Guid KsId=new Guid("28F54685-06FD-11D2-B27A-00A0C9223196");
  static PROPERTYKEY Friendly=new PROPERTYKEY(new Guid("a45c254e-df1c-4efd-8020-67d146a850e0"),14);
  static PROPERTYKEY Container=new PROPERTYKEY(new Guid("8c7ed206-3f8a-4827-b3ab-ae9e1faefc6c"),2);
  static void HR(int h){Marshal.ThrowExceptionForHR(h);}
  static void Release(object o){if(o!=null&&Marshal.IsComObject(o))Marshal.ReleaseComObject(o);}
  static string ReadProperty(IMMDevice d,PROPERTYKEY key,bool guid) {
   IPropertyStore store=null;PROPVARIANT value=new PROPVARIANT();
   try {HR(d.OpenPropertyStore(0,out store));HR(store.GetValue(ref key,out value));
    if(guid&&value.vt==72&&value.ptr!=IntPtr.Zero)return ((Guid)Marshal.PtrToStructure(value.ptr,typeof(Guid))).ToString("D");
    if(!guid&&value.vt==31&&value.ptr!=IntPtr.Zero)return Marshal.PtrToStringUni(value.ptr);
    return "";
   }finally{PropVariantClear(ref value);Release(store);}
  }
  static IKsControl Control(IMMDevice endpoint,out string filterId) {
   filterId="";object topologyObject=null;Guid iid=TopologyId;
   HR(endpoint.Activate(ref iid,23,IntPtr.Zero,out topologyObject));
   try {
    var topology=(IDeviceTopology)topologyObject;uint count;HR(topology.GetConnectorCount(out count));
    for(uint i=0;i<count;i++) {
     IConnector conn=null,other=null;IDeviceTopology otherTopology=null;IMMDevice adapter=null;IMMDeviceEnumerator enumerator=null;
     try {
      HR(topology.GetConnector(i,out conn));int hr=conn.GetConnectedTo(out other);if(hr<0||other==null)continue;
      HR(((IPart)other).GetTopologyObject(out otherTopology));string id;HR(otherTopology.GetDeviceId(out id));
      enumerator=(IMMDeviceEnumerator)new MMDeviceEnumerator();HR(enumerator.GetDevice(id,out adapter));
      iid=KsId;object control;hr=adapter.Activate(ref iid,23,IntPtr.Zero,out control);
      if(hr>=0&&control!=null){filterId=id;return (IKsControl)control;}
     }finally{Release(adapter);Release(enumerator);Release(otherTopology);Release(other);Release(conn);}
    }
    return null;
   }finally{Release(topologyObject);}
  }
  static bool Supports(IKsControl control,uint id) {
   var prop=new KSPROPERTY{Set=BtAudio,Id=id,Flags=0x200};IntPtr data=Marshal.AllocHGlobal(4);
   try {Marshal.WriteInt32(data,0);uint bytes;int hr=control.KsProperty(ref prop,24,data,4,out bytes);
    return hr>=0&&bytes>=4&&(Marshal.ReadInt32(data)&1)!=0;
   }finally{Marshal.FreeHGlobal(data);}
  }
  public Endpoint[] List(string container) {
   Guid target;if(!Guid.TryParse(container,out target)||target==Guid.Empty)throw new ArgumentException("Invalid target container");
   boundContainer=target;
   var rows=new List<Endpoint>();var enumerator=(IMMDeviceEnumerator)new MMDeviceEnumerator();
   try {
    for(int flow=0;flow<2;flow++) {
     IMMDeviceCollection collection=null;
     try {HR(enumerator.EnumAudioEndpoints(flow,15,out collection));uint count;HR(collection.GetCount(out count));
      for(uint i=0;i<count;i++) {
       IMMDevice device=null;IKsControl ks=null;Endpoint ep=null;
       try {HR(collection.Item(i,out device));string c=ReadProperty(device,Container,true);Guid cid;
        if(!Guid.TryParse(c,out cid)||cid!=target)continue;
        ep=new Endpoint();ep.ContainerId=c;ep.Flow=flow;HR(device.GetId(out ep.Id));HR(device.GetState(out ep.State));ep.Name=ReadProperty(device,Friendly,false);
        if(ep.State==1||ep.State==8){ks=Control(device,out ep.FilterId);if(ks!=null){ep.ReconnectSupported=Supports(ks,0);ep.DisconnectSupported=Supports(ks,1);}}
       }catch(Exception ex){if(ep!=null)ep.Error=ex.Message;}
       finally{if(ep!=null)rows.Add(ep);Release(ks);Release(device);}
      }
     }finally{Release(collection);}
    }
   }finally{Release(enumerator);}
   return rows.ToArray();
  }
  public int Send(string endpointId,uint property) {
   if(property>1)throw new ArgumentException("Unsupported KS command");
   var e=(IMMDeviceEnumerator)new MMDeviceEnumerator();IMMDevice d=null;IKsControl ks=null;
   try {HR(e.GetDevice(endpointId,out d));
    Guid current;uint state;HR(d.GetState(out state));
    if(boundContainer==Guid.Empty||!Guid.TryParse(ReadProperty(d,Container,true),out current)||current!=boundContainer)return unchecked((int)0x80070057);
    if(state!=1&&state!=8)return unchecked((int)0x80070490);
    if(property==0&&state==1)return 0;
    string filter;ks=Control(d,out filter);if(ks==null)return unchecked((int)0x80004002);
    if(!Supports(ks,property))return unchecked((int)0x80070490);
    var p=new KSPROPERTY{Set=BtAudio,Id=property,Flags=1};uint bytes;
    return ks.KsProperty(ref p,24,IntPtr.Zero,0,out bytes);
   }finally{Release(ks);Release(d);Release(e);}
  }
  [StructLayout(LayoutKind.Sequential)]struct PROPERTYKEY{public Guid fmtid;public uint pid;public PROPERTYKEY(Guid g,uint p){fmtid=g;pid=p;}}
  [StructLayout(LayoutKind.Explicit,Size=24)]struct PROPVARIANT{[FieldOffset(0)]public ushort vt;[FieldOffset(8)]public IntPtr ptr;}
  [StructLayout(LayoutKind.Sequential)]struct KSPROPERTY{public Guid Set;public uint Id;public uint Flags;}
  [DllImport("ole32.dll")]static extern int PropVariantClear(ref PROPVARIANT p);
  [ComImport,Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")]class MMDeviceEnumerator{}
  [ComImport,Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"),InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]interface IMMDeviceEnumerator{
   [PreserveSig]int EnumAudioEndpoints(int flow,uint states,out IMMDeviceCollection list);
   [PreserveSig]int GetDefaultAudioEndpoint(int flow,int role,out IMMDevice device);
   [PreserveSig]int GetDevice([MarshalAs(UnmanagedType.LPWStr)]string id,out IMMDevice device);
  }
  [ComImport,Guid("0BD7A1BE-7A1A-44DB-8397-CC5392387B5E"),InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]interface IMMDeviceCollection{
   [PreserveSig]int GetCount(out uint count);[PreserveSig]int Item(uint index,out IMMDevice device);
  }
  [ComImport,Guid("D666063F-1587-4E43-81F1-B948E807363F"),InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]interface IMMDevice{
   [PreserveSig]int Activate(ref Guid iid,int context,IntPtr parameters,[MarshalAs(UnmanagedType.IUnknown)]out object result);
   [PreserveSig]int OpenPropertyStore(uint access,out IPropertyStore store);
   [PreserveSig]int GetId([MarshalAs(UnmanagedType.LPWStr)]out string id);[PreserveSig]int GetState(out uint state);
  }
  [ComImport,Guid("886d8eeb-8cf2-4446-8d02-cdba1dbdcf99"),InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]interface IPropertyStore{
   [PreserveSig]int GetCount(out uint count);[PreserveSig]int GetAt(uint index,out PROPERTYKEY key);
   [PreserveSig]int GetValue(ref PROPERTYKEY key,out PROPVARIANT value);
  }
  [ComImport,Guid("2A07407E-6497-4A18-9787-32F79BD0D98F"),InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]interface IDeviceTopology{
   [PreserveSig]int GetConnectorCount(out uint count);[PreserveSig]int GetConnector(uint index,out IConnector connector);
   [PreserveSig]int GetSubunitCount(out uint count);[PreserveSig]int GetSubunit(uint index,out IntPtr subunit);
   [PreserveSig]int GetPartById(uint id,out IntPtr part);[PreserveSig]int GetDeviceId([MarshalAs(UnmanagedType.LPWStr)]out string id);
  }
  [ComImport,Guid("9c2c4058-23f5-41de-877a-df3af236a09e"),InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]interface IConnector{
   [PreserveSig]int GetType(out int type);[PreserveSig]int GetDataFlow(out int flow);
   [PreserveSig]int ConnectTo(IConnector other);[PreserveSig]int Disconnect();
   [PreserveSig]int IsConnected([MarshalAs(UnmanagedType.Bool)]out bool connected);[PreserveSig]int GetConnectedTo(out IConnector other);
  }
  [ComImport,Guid("AE2DE0E4-5BCA-4F2D-AA46-5D13F8FDB3A9"),InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]interface IPart{
   [PreserveSig]int GetName([MarshalAs(UnmanagedType.LPWStr)]out string name);[PreserveSig]int GetLocalId(out uint id);
   [PreserveSig]int GetGlobalId([MarshalAs(UnmanagedType.LPWStr)]out string id);[PreserveSig]int GetPartType(out int type);
   [PreserveSig]int GetSubType(out Guid guid);[PreserveSig]int GetControlInterfaceCount(out uint count);
   [PreserveSig]int GetControlInterface(uint index,out IntPtr control);[PreserveSig]int EnumPartsIncoming(out IntPtr parts);
   [PreserveSig]int EnumPartsOutgoing(out IntPtr parts);[PreserveSig]int GetTopologyObject(out IDeviceTopology topology);
  }
  [ComImport,Guid("28F54685-06FD-11D2-B27A-00A0C9223196"),InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]interface IKsControl{
   [PreserveSig]int KsProperty(ref KSPROPERTY property,uint length,IntPtr data,uint dataLength,out uint bytesReturned);
  }
 }
}
