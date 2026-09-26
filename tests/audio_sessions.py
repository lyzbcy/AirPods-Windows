"""Read-only WASAPI session snapshot for exact Bluetooth MMDevice endpoints.

Active means a session has a running stream. It is only a proxy for KS pin/SCO
activity, not proof that a particular KS pin is acquired or that audio is heard.
No stream is opened, no default route is changed, and no Bluetooth action occurs.
"""
import argparse
import base64
from datetime import datetime, timezone
import json
from pathlib import Path
import re
import subprocess
import sys


ENDPOINT = re.compile(r'^\{0\.0\.[01]\.00000000\}\.\{[0-9a-fA-F-]{36}\}$')
CS = r'''
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
namespace SessionProbe {
 [ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")] class MMDeviceEnumerator {}
 [ComImport, Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
 interface IMMDeviceEnumerator {
  [PreserveSig] int EnumAudioEndpoints(int flow, uint states, out IntPtr devices);
  [PreserveSig] int GetDefaultAudioEndpoint(int flow, int role, out IntPtr device);
  [PreserveSig] int GetDevice([MarshalAs(UnmanagedType.LPWStr)] string id, out IMMDevice device);
  [PreserveSig] int RegisterEndpointNotificationCallback(IntPtr callback);
  [PreserveSig] int UnregisterEndpointNotificationCallback(IntPtr callback);
 }
 [ComImport, Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
 interface IMMDevice {
  [PreserveSig] int Activate(ref Guid iid, int context, IntPtr parameters, [MarshalAs(UnmanagedType.IUnknown)] out object result);
  [PreserveSig] int OpenPropertyStore(uint access, out IntPtr store);
  [PreserveSig] int GetId([MarshalAs(UnmanagedType.LPWStr)] out string id);
  [PreserveSig] int GetState(out uint state);
 }
 [ComImport, Guid("77AA99A0-1BD6-484F-8BC7-2C654C9A9B6F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
 interface IAudioSessionManager2 {
  [PreserveSig] int GetAudioSessionControl(ref Guid session, int flags, out IntPtr control);
  [PreserveSig] int GetSimpleAudioVolume(ref Guid session, int flags, out IntPtr volume);
  [PreserveSig] int GetSessionEnumerator(out IAudioSessionEnumerator sessions);
  [PreserveSig] int RegisterSessionNotification(IntPtr callback);
  [PreserveSig] int UnregisterSessionNotification(IntPtr callback);
  [PreserveSig] int RegisterDuckNotification([MarshalAs(UnmanagedType.LPWStr)] string id, IntPtr callback);
  [PreserveSig] int UnregisterDuckNotification(IntPtr callback);
 }
 [ComImport, Guid("E2F5BB11-0570-40CA-ACDD-3AA01277DEE8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
 interface IAudioSessionEnumerator {
  [PreserveSig] int GetCount(out int count);
  [PreserveSig] int GetSession(int index, out IAudioSessionControl control);
 }
 [ComImport, Guid("F4B1A599-7266-4319-A8CA-E70ACB11E8CD"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
 interface IAudioSessionControl {
  [PreserveSig] int GetState(out int state);
  [PreserveSig] int GetDisplayName(out IntPtr name);
  [PreserveSig] int SetDisplayName(IntPtr name, ref Guid context);
  [PreserveSig] int GetIconPath(out IntPtr path);
  [PreserveSig] int SetIconPath(IntPtr path, ref Guid context);
  [PreserveSig] int GetGroupingParam(out Guid group);
  [PreserveSig] int SetGroupingParam(ref Guid group, ref Guid context);
  [PreserveSig] int RegisterAudioSessionNotification(IntPtr callback);
  [PreserveSig] int UnregisterAudioSessionNotification(IntPtr callback);
 }
 [ComImport, Guid("BFB7FF88-7239-4FC9-8FA2-07C950BE9C6D"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
 interface IAudioSessionControl2 {
  [PreserveSig] int GetState(out int state);
  [PreserveSig] int GetDisplayName(out IntPtr name);
  [PreserveSig] int SetDisplayName(IntPtr name, ref Guid context);
  [PreserveSig] int GetIconPath(out IntPtr path);
  [PreserveSig] int SetIconPath(IntPtr path, ref Guid context);
  [PreserveSig] int GetGroupingParam(out Guid group);
  [PreserveSig] int SetGroupingParam(ref Guid group, ref Guid context);
  [PreserveSig] int RegisterAudioSessionNotification(IntPtr callback);
  [PreserveSig] int UnregisterAudioSessionNotification(IntPtr callback);
  [PreserveSig] int GetSessionIdentifier(out IntPtr id);
  [PreserveSig] int GetSessionInstanceIdentifier(out IntPtr id);
  [PreserveSig] int GetProcessId(out uint pid);
  [PreserveSig] int IsSystemSoundsSession();
  [PreserveSig] int SetDuckingPreference([MarshalAs(UnmanagedType.Bool)] bool optOut);
 }
 public static class Reader {
  static string H(int hr) { return "0x" + unchecked((uint)hr).ToString("X8"); }
  static void Release(object value) { if (value != null && Marshal.IsComObject(value)) Marshal.ReleaseComObject(value); }
  public static string[] Snapshot(string id) {
   var lines = new List<string>(); IMMDeviceEnumerator devices = null; IMMDevice device = null;
   object managerObject = null; IAudioSessionEnumerator sessions = null;
   try {
    devices = (IMMDeviceEnumerator)new MMDeviceEnumerator();
    int hr = devices.GetDevice(id, out device);
    if (hr < 0 || device == null) { lines.Add("ERROR\t"+H(hr)+"\tGetDevice"); return lines.ToArray(); }
    uint endpointState; hr = device.GetState(out endpointState);
    if (hr < 0) { lines.Add("ERROR\t"+H(hr)+"\tGetState"); return lines.ToArray(); }
    lines.Add("ENDPOINT\t"+endpointState);
    Guid iid = new Guid("77AA99A0-1BD6-484F-8BC7-2C654C9A9B6F");
    hr = device.Activate(ref iid, 23, IntPtr.Zero, out managerObject);
    if (hr < 0 || managerObject == null) { lines.Add("ERROR\t"+H(hr)+"\tActivateSessionManager"); return lines.ToArray(); }
    hr = ((IAudioSessionManager2)managerObject).GetSessionEnumerator(out sessions);
    if (hr < 0 || sessions == null) { lines.Add("ERROR\t"+H(hr)+"\tGetSessionEnumerator"); return lines.ToArray(); }
    int count; hr = sessions.GetCount(out count);
    if (hr < 0) { lines.Add("ERROR\t"+H(hr)+"\tGetCount"); return lines.ToArray(); }
    for (int i=0; i<count; i++) {
     IAudioSessionControl session = null; IAudioSessionControl2 extended = null;
     try {
      hr = sessions.GetSession(i, out session);
      if (hr < 0 || session == null) { lines.Add("SESSION_ERROR\t"+i+"\t"+H(hr)+"\tGetSession"); continue; }
      extended = (IAudioSessionControl2)session;
      int state; int stateHr = extended.GetState(out state); uint pid; int pidHr = extended.GetProcessId(out pid);
      lines.Add("SESSION\t"+i+"\t"+state+"\t"+H(stateHr)+"\t"+pid+"\t"+H(pidHr));
     } catch (Exception e) { lines.Add("SESSION_ERROR\t"+i+"\t"+H(e.HResult)+"\tinterop"); }
     finally { Release(extended); if (!Object.ReferenceEquals(extended,session)) Release(session); }
    }
   } catch (Exception e) { lines.Add("ERROR\t"+H(e.HResult)+"\tinterop"); }
   finally { Release(sessions); Release(managerObject); Release(device); Release(devices); }
   return lines.ToArray();
  }
 }
}
'''


def validate_ids(ids):
    if not ids or len(ids) > 2 or len(set(x.lower() for x in ids)) != len(ids):
        raise ValueError('one or two distinct exact endpoint IDs required')
    if any(not ENDPOINT.fullmatch(x) for x in ids):
        raise ValueError('invalid exact MMDevice endpoint ID')
    return ids


def parse_rows(lines, endpoint_id):
    result = {'endpointId': endpoint_id, 'flow': int(endpoint_id[5]),
              'endpointState': None, 'sessions': [], 'errors': []}
    for line in lines:
        parts = line.split('\t')
        if parts[0] == 'ENDPOINT' and len(parts) == 2:
            result['endpointState'] = int(parts[1])
        elif parts[0] == 'SESSION' and len(parts) == 6:
            state = int(parts[2]); state_hr = parts[3]; pid_hr = parts[5]
            result['sessions'].append({'index': int(parts[1]),
                'state': {0: 'Inactive', 1: 'Active', 2: 'Expired'}.get(state, 'Unknown'),
                'stateHresult': state_hr, 'pid': int(parts[4]), 'pidHresult': pid_hr})
        elif parts[0] in ('ERROR', 'SESSION_ERROR'):
            result['errors'].append(line)
        else:
            raise ValueError('unexpected probe row')
    return result


def snapshot(endpoint_ids):
    # The process performs only COM Get*/Activate calls; no audio client is initialized.
    script = ("$ErrorActionPreference='Stop'; Add-Type -TypeDefinition @'\n" + CS +
              "\n'@\n$json=[Text.Encoding]::UTF8.GetString(" +
              "[Convert]::FromBase64String('" +
              base64.b64encode(json.dumps(endpoint_ids).encode()).decode() + "')); " +
              "$ids=ConvertFrom-Json -InputObject $json; " +
              "foreach($id in $ids){Write-Output ('ID' + [char]9 + $id); " +
              "[SessionProbe.Reader]::Snapshot([string]$id) | Write-Output}")
    encoded = base64.b64encode(script.encode('utf-16le')).decode('ascii')
    proc = subprocess.run(['powershell', '-NoProfile', '-NonInteractive', '-EncodedCommand', encoded],
                          capture_output=True, timeout=30)
    if proc.returncode:
        raise RuntimeError(proc.stderr.decode('utf-8-sig', errors='replace') or
                           proc.stdout.decode('utf-8-sig', errors='replace'))
    output = proc.stdout.decode('utf-8-sig', errors='replace').splitlines()
    groups = {}; current = None
    for line in output:
        if line.startswith('ID\t'):
            current = line[3:]; groups[current] = []
        elif current is not None and line:
            groups[current].append(line)
        elif line:
            raise RuntimeError('unexpected probe output')
    if set(groups) != set(endpoint_ids):
        raise RuntimeError('missing endpoint probe output')
    return [parse_rows(groups[x], x) for x in endpoint_ids]


def self_test():
    valid = '{0.0.0.00000000}.{513b6795-d90c-4d86-9e6d-3d1f823d378a}'
    assert validate_ids([valid]) == [valid]
    for bad in ([], [valid, valid], ['not-an-endpoint']):
        try: validate_ids(bad)
        except ValueError: pass
        else: raise AssertionError('invalid IDs accepted')
    item = parse_rows(['ENDPOINT\t1', 'SESSION\t0\t1\t0x00000000\t123\t0x00000000'], valid)
    assert item['flow'] == 0 and item['sessions'][0]['state'] == 'Active'
    assert item['sessions'][0]['pid'] == 123
    assert 'SetDefault' not in CS and 'BluetoothSetServiceState' not in CS
    assert 'GetAudioSessionControl(' in CS and '.GetAudioSessionControl(' not in CS
    print('PASS exact_endpoint_validation')
    print('PASS session_row_parsing_and_read_only_contract')
    print('RESULT failures=0 tests=2')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--endpoint', action='append', help='exact render/capture MMDevice endpoint ID')
    parser.add_argument('--self-test', action='store_true')
    args = parser.parse_args()
    if args.self_test:
        self_test(); return 0
    try:
        ids = validate_ids(args.endpoint)
        output = {'utc': datetime.now(timezone.utc).isoformat(timespec='milliseconds'),
                  'readOnly': True, 'activeIsProxyNotKsPinProof': True,
                  'endpoints': snapshot(ids)}
        print(json.dumps(output, ensure_ascii=False, separators=(',', ':')))
        return 0 if all(not e['errors'] for e in output['endpoints']) else 3
    except (ValueError, RuntimeError, subprocess.TimeoutExpired) as exc:
        print(json.dumps({'error': str(exc)}, ensure_ascii=False), file=sys.stderr)
        return 2


if __name__ == '__main__':
    sys.exit(main())
