"""Build an owner-private runtime ZIP including synthetic test passwords.
Never public-upload or use the source-backup publisher for this archive.
No cloud calls, installs, starts or modifications of app/backend/server.
"""
import sys
sys.dont_write_bytecode = True
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
from datetime import datetime, timezone
import zipfile

ROOT=Path(__file__).resolve().parents[2]
PROJECT="mydoxxx-dev-261102"
DATABASE="mydoxxx-testing"
BUILD=ROOT/"experiments/MYDOXXX/app/build/web-lab"
APP=ROOT/"experiments/MYDOXXX/app"
TEMPLATES=ROOT/"scripts/mydoxxx/portable-runtime"
CREDS=ROOT/"private-backups"/PROJECT/"test-lab-credentials.json"
DEST=ROOT/"private-backups"/PROJECT/"portable-test-room"
ASSETS=("serve-test-lab.py","test-console.html","test-console.js","test-console-state.js")
DOCS=("start.py","START-MYDOXXX.cmd","START-HERE.md","CODEX-HANDOFF.md","AGENTS.md")

def long_path(path):
 value=str(path.absolute())
 if os.name=="nt" and not value.startswith("\\\\?\\"):
  value="\\\\?\\UNC\\"+value[2:] if value.startswith("\\\\") else "\\\\?\\"+value
 return Path(value)

def digest(data): return hashlib.sha256(data).hexdigest()
def git(*args): return subprocess.check_output(["git","-C",str(APP),*args],stderr=subprocess.PIPE).decode().strip()

def main():
 os.umask(0o077)
 if git("status","--porcelain=v1","--untracked-files=all"): raise ValueError("App source must be committed and clean before packaging.")
 commit=git("rev-parse","HEAD")
 receipt=json.loads((APP/"MYDOXXX-TEST-LAB-VALIDATION.json").read_text(encoding="utf-8"))
 if receipt.get("projectId")!=PROJECT or receipt.get("databaseId")!=DATABASE: raise ValueError("Unexpected app validation target")
 js=(BUILD/"main.dart.js").read_bytes()
 if digest(js)!=receipt["build"]["mainJsSha256"]: raise ValueError("Compiled build does not match the validated release")
 if not all(token in js for token in (PROJECT.encode(),DATABASE.encode(),b"/__mydox_test__/login-config")): raise ValueError("Expected compiled test guards are missing")
 spec=importlib.util.spec_from_file_location("mydox_portable_source_host",ROOT/"scripts/mydoxxx/serve-test-lab.py")
 host=importlib.util.module_from_spec(spec);spec.loader.exec_module(host)
 private_bytes=CREDS.read_bytes()
 credentials=host.load_credentials(CREDS)
 if str(credentials.get("projectNumber"))!="724915428929": raise ValueError("Unexpected private credential target")
 del credentials
 host.lab_flutter_bootstrap((BUILD/"flutter_bootstrap.js").read_bytes())
 files={}
 for file in sorted(BUILD.rglob("*")):
  if file.is_symlink(): raise ValueError("Do not package linked build files")
  if file.is_file(): files["build/"+file.relative_to(BUILD).as_posix()]=file.read_bytes()
 for name in ASSETS: files["server/"+name]=(ROOT/"scripts/mydoxxx"/name).read_bytes()
 for name in DOCS: files[name]=(TEMPLATES/name).read_bytes()
 files[".gitignore"]=b"# Entire generated runtime is private.\n*\n"
 files["private/test-lab-credentials.json"]=private_bytes
 # No admin exports, Firebase-owner auth or source/recovery scripts are copied.
 stamp=datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%SZ")
 name="MYDOXXX-PRIVATE-Test-Room-"+stamp
 stage_display=DEST/name
 stage=long_path(stage_display)
 if stage.exists(): raise ValueError("Destination already exists; refusing overwrite")
 stage.mkdir(parents=True)
 for relative,data in files.items():
  target=stage/relative;target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(data)
 manifest={"format":"MYDOXXX private portable runtime v1","createdAt":datetime.now(timezone.utc).isoformat(),
  "projectId":PROJECT,"databaseId":DATABASE,"appCommit":commit,"mainJsSha256":digest(js),
  "containsPrivateTestCredentials":True,"syntheticAccounts":36,"pythonMinimum":"3.10",
  "defaultConsolePort":8889,"defaultRolePorts":[8891,8926],"cloudCallsDuringPackaging":0,
  "files":[{"path":r,"bytes":len(d),"sha256":digest(d)} for r,d in sorted(files.items())]}
 files["RUNTIME-MANIFEST.json"]=(json.dumps(manifest,indent=2)+"\n").encode()
 (stage/"RUNTIME-MANIFEST.json").write_bytes(files["RUNTIME-MANIFEST.json"])
 # Verify a relocated-style root through the real launcher check function;
 # port reservation is intentionally left for --check at the chosen laptop.
 spec=importlib.util.spec_from_file_location("mydox_portable_launcher",stage/"start.py")
 launcher=importlib.util.module_from_spec(spec);spec.loader.exec_module(launcher)
 launcher.verify_files(stage.resolve())
 archive_display=DEST/(name+".zip")
 archive=long_path(archive_display)
 with zipfile.ZipFile(archive,"w",zipfile.ZIP_DEFLATED,compresslevel=6) as z:
  for relative,data in sorted(files.items()):
   info=zipfile.ZipInfo(name+"/"+relative);info.compress_type=zipfile.ZIP_DEFLATED;info.external_attr=0o600<<16
   z.writestr(info,data)
 with zipfile.ZipFile(archive) as z:
  if z.testzip() is not None: raise ValueError("Runtime ZIP integrity check failed")
  for relative,data in files.items():
   if digest(z.read(name+"/"+relative))!=digest(data): raise ValueError("Runtime ZIP file mismatch")
 if CREDS.read_bytes()!=private_bytes or git("rev-parse","HEAD")!=commit: raise ValueError("Inputs changed during packaging; use a fresh snapshot")
 sha=digest(archive.read_bytes())
 archive.with_suffix(".zip.sha256").write_text(sha+"  "+archive.name+"\n",encoding="utf-8")
 print(json.dumps({"PRIVATE_DO_NOT_PUBLISH":True,"archive":str(archive_display),"folder":str(stage_display),"bytes":archive.stat().st_size,
  "sha256":sha,"files":len(files),"appCommit":commit,"mainJsSha256":digest(js),"credentialsIncludedPrivately":True,"verified":True},indent=2))

if __name__=="__main__":
 try: main()
 except Exception as error:
  print("Private runtime packaging stopped: "+(str(error) if isinstance(error,ValueError) else type(error).__name__),file=sys.stderr)
  raise SystemExit(2)
