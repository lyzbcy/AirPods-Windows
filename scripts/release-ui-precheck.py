"""UI-only exception authorized on 2026-10-22; never asserts hardware acceptance.

Compare every existing function and runtime dependency to the published v1.9.21.
Only resource install and feedback bridge validation/dispatch may differ in host.
"""
from pathlib import Path
import argparse, importlib.util, json, re, subprocess

ROOT=Path(__file__).resolve().parents[1]
BASE='v1.9.21'
def original(name):
    return subprocess.check_output(['git','show',f'{BASE}:{name}'],cwd=ROOT).decode('utf-8-sig').replace('\r\n','\n')
def functions(text):
    found={}
    for match in re.finditer(r'^([A-Za-z_]\w*)\([^\n]*\) \{',text,re.M):
        end=text.index('\n}',match.start())+2
        found[match[1]]=text[match.start():end]
    return found
def verify_scope():
    before=original('airpods_buddy.ahk')
    after=(ROOT/'airpods_buddy.ahk').read_text(encoding='utf-8-sig')
    old,new=functions(before),functions(after)
    assert old.keys()==new.keys(), 'Unexpected host functions added/removed'
    allowed={'EnsureResources','WebMessageHandler','ValidBridgeArgs'}
    for name in old.keys()-allowed:
        assert old[name]==new[name], f'Existing runtime function changed: {name}'
    for function in old.values():before=before.replace(function,'')
    for function in new.values():after=after.replace(function,'')
    after=after.replace('#Include lib\\AgentHelp.ahk\n','').replace('APP_VERSION   := "1.9.24"','APP_VERSION   := "1.9.21"').replace('myGui.OnEvent("Close", (*) => (AgentHide(), myGui.Hide()))','myGui.OnEvent("Close", (*) => myGui.Hide())')
    assert before==after, 'Unexpected top-level runtime change'
    protected=subprocess.check_output(['git','ls-tree','-r','--name-only',BASE,'lib','scripts','tools/noise_mode.ps1','webui/pet.html','webui/pet_built.html'],cwd=ROOT,text=True).splitlines()
    exceptions={'scripts/build-deploy.ps1','scripts/package-windows-release.py'}
    for name in protected:
        if name in exceptions:continue
        current=subprocess.check_output(['git','hash-object',f'--path={name}',name],cwd=ROOT).strip()
        baseline=subprocess.check_output(['git','rev-parse',f'{BASE}:{name}'],cwd=ROOT).strip()
        assert current==baseline,f'Runtime dependency changed: {name}'
    return len(protected)-len(exceptions), len(old)-len(allowed)
if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--build-dir',type=Path,required=True);parser.add_argument('--zip',type=Path,required=True);parser.add_argument('--output',type=Path,required=True);args=parser.parse_args()
    dependencies,unchanged=verify_scope()
    spec=importlib.util.spec_from_file_location('packager',ROOT/'scripts/package-windows-release.py');packager=importlib.util.module_from_spec(spec);spec.loader.exec_module(packager)
    package=packager.verify_build(args.build_dir,ROOT);package['zipSha256']=packager.verify_zip(args.zip,package['exeSha256'])
    receipt={k:v for k,v in package.items() if k!='inputs'}
    receipt.update(profile='ui-only-owner-authorized',baseline=BASE,protectedDependencies=dependencies,unchangedHostFunctions=unchanged,hardwareTest='not-run-no-bluetooth',hearingConfirmed=False,knownIssuesRetained=True)
    args.output.parent.mkdir(parents=True,exist_ok=True);args.output.write_text(json.dumps(receipt,indent=2),encoding='utf-8')
    print(f'UI_RELEASE_PRECHECK_PASS baseline={BASE} unchangedFunctions={unchanged} dependencies={dependencies} hardwareTest=not-run-no-bluetooth')
