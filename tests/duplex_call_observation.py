"""Independent read-only duplex observation for a user-initiated voice call.

No stream initialization, audio buffer access, playback, route changes, or
Bluetooth requests. Endpoint identifiers and session process IDs are held only
in memory; stdout contains aggregate status and format metadata, not device IDs.
An observed stereo mix is NOT proof of the physical headset microphone or sound.
"""
import argparse
import ctypes as C
from ctypes import wintypes as W
import json
import re
import sys
from audio_sessions import snapshot, ENDPOINT

OK = '0x00000000'


def validate_pair(render, capture):
    if not (ENDPOINT.fullmatch(render or '') and render.startswith('{0.0.0.')
            and ENDPOINT.fullmatch(capture or '') and capture.startswith('{0.0.1.')):
        raise ValueError('one exact render and one exact capture endpoint required')
    return [render, capture]


def active_summary(item):
    if not isinstance(item, dict) or item.get('endpointState') != 1 or item.get('errors'):
        return 'unknown'
    sessions = item.get('sessions')
    if not isinstance(sessions, list) or any(r.get('stateHresult') != OK or
                                            r.get('state') not in ('Active', 'Inactive', 'Expired')
                                            for r in sessions):
        return 'unknown'
    return 'active' if any(r['state'] == 'Active' for r in sessions) else 'inactive'


def safe_format(value):
    if not isinstance(value, dict):
        return None
    ch, rate, bits = (value.get(k) for k in ('channels', 'sampleRate', 'bits'))
    if not all(type(x) is int for x in (ch, rate, bits)):
        return None
    if not(1 <= ch <= 32 and 8000 <= rate <= 384000 and bits in (8, 16, 24, 32, 64)):
        return None
    return {'channels': ch, 'sampleRate': rate, 'bits': bits}


def assess(before, after, render_format, capture_format):
    """Require active endpoint sessions on both sides of the format query."""
    states = [[active_summary(row) for row in pair] for pair in (before, after)]
    out = {
        'status': 'insufficient_observation',
        'renderActiveBeforeAfter': [states[0][0], states[1][0]],
        'captureActiveBeforeAfter': [states[0][1], states[1][1]],
        'renderMixFormat': safe_format(render_format),
        'captureMixFormat': safe_format(capture_format),
        'physicalMicVerified': False,
        'audibleStereoVerified': False,
        'readOnly': True,
    }
    if any(state != 'active' for group in states for state in group):
        return out
    if out['renderMixFormat'] is None or out['captureMixFormat'] is None:
        out['status'] = 'format_unavailable'
    elif out['renderMixFormat']['channels'] == 1:
        out['status'] = 'mono_mix_observed'
    else:
        out['status'] = 'multichannel_mix_observed_not_proof'
    return out


def read_mix_formats(ids):
    # Only query the shared audio engine's mix format, never create a stream.
    ole = C.OleDLL('ole32')
    HRESULT, PTR = C.c_long, C.c_void_p

    class GUID(C.Structure):
        _fields_ = [('a', W.DWORD), ('b', W.WORD), ('c', W.WORD), ('d', C.c_ubyte * 8)]

    class FORMAT(C.Structure):
        _pack_ = 1
        _fields_ = [('tag', W.WORD), ('channels', W.WORD), ('rate', W.DWORD),
                    ('average', W.DWORD), ('align', W.WORD), ('bits', W.WORD),
                    ('extra', W.WORD)]

    def guid(s):
        g = GUID()
        ole.CLSIDFromString(s, C.byref(g))
        return g

    def call(obj, slot, types, *args):
        table = C.cast(obj, C.POINTER(C.POINTER(PTR))).contents
        fn = C.WINFUNCTYPE(HRESULT, PTR, *types)(table[slot])
        hr = fn(obj, *args)
        if hr < 0:
            raise OSError('COM metadata query failed')
        return hr

    def release(obj):
        if obj:
            table = C.cast(obj, C.POINTER(C.POINTER(PTR))).contents
            C.WINFUNCTYPE(W.DWORD, PTR)(table[2])(obj)

    ole.CoInitialize(None)
    enumerator = PTR()
    try:
        cls = guid('{BCDE0395-E52F-467C-8E3D-C4579291692E}')
        iid = guid('{A95664D2-9614-4F35-A746-DE8DB63617E6}')
        ole.CoCreateInstance(C.byref(cls), None, 23, C.byref(iid), C.byref(enumerator))
        result = []
        for endpoint in ids:
            device, client, fmt = PTR(), PTR(), PTR()
            try:
                call(enumerator, 5, [W.LPCWSTR, C.POINTER(PTR)], endpoint, C.byref(device))
                state = W.DWORD()
                call(device, 6, [C.POINTER(W.DWORD)], C.byref(state))
                if state.value != 1:
                    result.append(None)
                    continue
                client_iid = guid('{1CB9AD4C-DBFA-4C32-B178-C2F568A703B2}')
                call(device, 3, [C.POINTER(GUID), W.DWORD, PTR, C.POINTER(PTR)],
                     C.byref(client_iid), 23, None, C.byref(client))
                call(client, 8, [C.POINTER(PTR)], C.byref(fmt))
                if not fmt:
                    result.append(None)
                    continue
                mix = C.cast(fmt, C.POINTER(FORMAT)).contents
                result.append({'channels': int(mix.channels), 'sampleRate': int(mix.rate),
                               'bits': int(mix.bits)})
            except (OSError, ValueError):
                result.append(None)
            finally:
                if fmt:
                    ole.CoTaskMemFree(fmt)
                release(client)
                release(device)
        return result
    finally:
        release(enumerator)
        ole.CoUninitialize()


def observe(ids, session_reader=snapshot, format_reader=read_mix_formats):
    before = session_reader(ids)
    render, capture = format_reader(ids)
    after = session_reader(ids)
    return assess(before, after, render, capture)


def self_test():
    r = '{0.0.0.00000000}.{11111111-1111-1111-1111-111111111111}'
    c = '{0.0.1.00000000}.{22222222-2222-2222-2222-222222222222}'
    assert validate_pair(r, c) == [r, c]
    for a, b in ((c,r),(r,r),('bad',c)):
        try:
            validate_pair(a,b)
        except ValueError:
            pass
        else:
            raise AssertionError('wrong flow accepted')
    print('PASS exact_render_capture_pair')
    active = {'endpointState':1,'errors':[],'sessions':[{'state':'Active','stateHresult':OK,'pid':12345}]}
    idle = {'endpointState':1,'errors':[],'sessions':[]}
    error = {'endpointState':1,'errors':['private'],'sessions':[]}
    stereo={'channels':2,'sampleRate':48000,'bits':32}
    mono={'channels':1,'sampleRate':8000,'bits':16}
    result=assess([active,active],[active,active],stereo,mono)
    assert result['status']=='multichannel_mix_observed_not_proof'
    assert not result['physicalMicVerified'] and not result['audibleStereoVerified']
    assert '12345' not in json.dumps(result)
    print('PASS stereo_metadata_never_claims_physical_mic_or_hearing')
    assert assess([active,active],[active,active],mono,mono)['status']=='mono_mix_observed'
    print('PASS classic_mono_observation')
    assert assess([active,idle],[active,active],stereo,mono)['status']=='insufficient_observation'
    assert assess([active,active],[idle,active],stereo,mono)['status']=='insufficient_observation'
    print('PASS streams_must_be_active_before_and_after')
    assert assess([active,error],[active,active],stereo,mono)['status']=='insufficient_observation'
    print('PASS query_failure_is_unknown')
    assert assess([active,active],[active,active],{'channels':True,'sampleRate':48000,'bits':32},mono)['status']=='format_unavailable'
    print('PASS invalid_format_fails_closed')
    calls=[]
    def sessions(ids):
        calls.append('sessions')
        assert ids==[r,c]
        return [active,active]
    def formats(ids):
        calls.append('formats')
        return stereo,mono
    assert observe([r,c],sessions,formats)['status']=='multichannel_mix_observed_not_proof'
    assert calls==['sessions','formats','sessions']
    print('PASS observes_around_mix_query_without_stream_operations')


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--render')
    p.add_argument('--capture')
    p.add_argument('--self-test',action='store_true')
    args=p.parse_args()
    if args.self_test:
        self_test()
        return 0
    try:
        ids=validate_pair(args.render,args.capture)
        outcome=observe(ids)
        outcome['windowsBuild']=sys.getwindowsversion().build
        outcome['mixFormatCaveat']='LE Audio channel metadata may be unreliable before Windows build 26100.4484; no transport or acoustic proof'
        print(json.dumps(outcome,separators=(',',':')))
        return 0 if outcome['status'] in ('mono_mix_observed','multichannel_mix_observed_not_proof') else 3
    except (Exception,):
        # Never emit raw endpoint IDs, process/session information or exception strings.
        print(json.dumps({'status':'query_unavailable','readOnly':True,'physicalMicVerified':False,'audibleStereoVerified':False}))
        return 2


if __name__=='__main__':
    sys.exit(main())
