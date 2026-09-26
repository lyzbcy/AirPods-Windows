"""Explicit-endpoint WASAPI probe. Default is read-only; --play submits a
low-amplitude, bounded stream to the exact endpoint ID supplied by the operator.
Never changes endpoint volume, mute, defaults, visibility, or radio state.
"""
import ctypes as C,sys,json,time,math
from datetime import datetime
from ctypes import wintypes as W
sys.stdout.reconfigure(encoding='utf-8')
ole=C.OleDLL('ole32'); HRESULT=C.c_long; PTR=C.c_void_p
class GUID(C.Structure):
    _fields_=[('a',W.DWORD),('b',W.WORD),('c',W.WORD),('d',C.c_ubyte*8)]
def guid(s):
    g=GUID();ole.CLSIDFromString(s,C.byref(g));return g
def call(obj,slot,types,*args):
    table=C.cast(obj,C.POINTER(C.POINTER(PTR))).contents
    fn=C.WINFUNCTYPE(HRESULT,PTR,*types)(table[slot])
    hr=fn(obj,*args)
    if hr<0: raise OSError(f'COM slot={slot} HRESULT=0x{hr&0xffffffff:08X}')
    return hr
def release(obj):
    if obj: call(obj,2,[])
ole.CoInitialize(None)
objects=[]
def own(p):objects.append(p);return p
try:
    enum=PTR();cls=guid('{BCDE0395-E52F-467C-8E3D-C4579291692E}');iid=guid('{A95664D2-9614-4F35-A746-DE8DB63617E6}')
    ole.CoCreateInstance(C.byref(cls),None,23,C.byref(iid),C.byref(enum));own(enum)
    device=PTR()
    if sys.argv[1]=='--default':
        call(enum,4,[C.c_int,C.c_int,C.POINTER(PTR)],0,1,C.byref(device))
    else:
        call(enum,5,[W.LPCWSTR,C.POINTER(PTR)],sys.argv[1],C.byref(device))
    own(device)
    raw_id=PTR();call(device,5,[C.POINTER(PTR)],C.byref(raw_id));endpoint_id=C.wstring_at(raw_id);ole.CoTaskMemFree(raw_id)
    def activate(iid):
        p=PTR();g=guid(iid);call(device,3,[C.POINTER(GUID),W.DWORD,PTR,C.POINTER(PTR)],C.byref(g),23,None,C.byref(p));return own(p)
    volume=activate('{5CDF2C82-841E-4546-9722-0CF74078229A}')
    scalar=C.c_float();mute=W.BOOL()
    call(volume,9,[C.POINTER(C.c_float)],C.byref(scalar));call(volume,15,[C.POINTER(W.BOOL)],C.byref(mute))
    print(json.dumps({'time':datetime.now().isoformat(),'endpoint':endpoint_id,'selection':sys.argv[1],'volume':round(scalar.value,3),'mute':bool(mute.value)},ensure_ascii=False),flush=True)
    if '--play' in sys.argv:
        client=activate('{1CB9AD4C-DBFA-4C32-B178-C2F568A703B2}')
        fmt=PTR();call(client,8,[C.POINTER(PTR)],C.byref(fmt))
        class FORMAT(C.Structure):
            _pack_=1
            _fields_=[('tag',W.WORD),('channels',W.WORD),('rate',W.DWORD),('bytes',W.DWORD),('align',W.WORD),('bits',W.WORD),('extra',W.WORD)]
        mix=C.cast(fmt,C.POINTER(FORMAT)).contents
        tag=mix.tag
        if tag==65534:tag=C.c_ushort.from_address(fmt.value+24).value
        if not (tag==3 and mix.bits==32):raise RuntimeError(f'unsupported mix format tag={tag}, bits={mix.bits}; no stream submitted')
        rate,channels=int(mix.rate),int(mix.channels)
        print(json.dumps({'format':'float32','rate':rate,'channels':channels}),flush=True)
        call(client,3,[C.c_int,W.DWORD,C.c_longlong,C.c_longlong,PTR,PTR],0,0,10000000,0,fmt,None)
        ole.CoTaskMemFree(fmt)
        capacity=W.UINT();call(client,4,[C.POINTER(W.UINT)],C.byref(capacity))
        render=PTR();iid=guid('{F294ACFC-3146-4483-A7BF-ADDCA7C260E2}')
        call(client,14,[C.POINTER(GUID),C.POINTER(PTR)],C.byref(iid),C.byref(render));own(render)
        sent=0;total=rate*3
        def fill(frames):
            global sent
            buffer=PTR();call(render,3,[W.UINT,C.POINTER(PTR)],frames,C.byref(buffer))
            samples=C.cast(buffer,C.POINTER(C.c_float))
            for n in range(frames):
                t=(sent+n)/rate;phase=t%0.5
                envelope=max(0,min(1,phase/0.02,(0.35-phase)/0.02))
                val=0.1*envelope*math.sin(2*math.pi*(440 if t<1.5 else 660)*t)
                for ch in range(channels):samples[n*channels+ch]=val
            call(render,4,[W.UINT,W.DWORD],frames,0);sent+=frames
        fill(min(capacity.value,total));call(client,10,[])
        try:
            deadline=time.monotonic()+8
            while time.monotonic()<deadline:
                padding=W.UINT();call(client,6,[C.POINTER(W.UINT)],C.byref(padding))
                available=min(capacity.value-padding.value,total-sent)
                if available>0:fill(available)
                if sent==total and padding.value==0:break
                time.sleep(0.01)
            print(json.dumps({'frames_submitted':sent,'frames_expected':total,'remaining_padding':padding.value,'audible_confirmation':'pending'}),flush=True)
            end_state=W.DWORD();call(device,6,[C.POINTER(W.DWORD)],C.byref(end_state))
            current=PTR();call(enum,4,[C.c_int,C.c_int,C.POINTER(PTR)],0,1,C.byref(current));own(current)
            current_id=PTR();call(current,5,[C.POINTER(PTR)],C.byref(current_id));current_text=C.wstring_at(current_id);ole.CoTaskMemFree(current_id)
            print(json.dumps({'time':datetime.now().isoformat(),'end_endpoint_state':end_state.value,'end_default':current_text,'default_unchanged':current_text==endpoint_id}),flush=True)
            if sent!=total or padding.value or end_state.value!=1 or (sys.argv[1]=='--default' and current_text!=endpoint_id):raise RuntimeError('stream drain or final route validation failed')
        finally:call(client,11,[])
finally:
    for p in reversed(objects):release(p)
    ole.CoUninitialize()
