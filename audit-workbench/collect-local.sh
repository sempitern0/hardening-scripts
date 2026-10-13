#!/usr/bin/env bash
# Audit Workbench local collector. Explicit local execution, read-only, no network connections.
set -Eeuo pipefail
umask 077
OUT=""
while (($#)); do case "$1" in --output) [[ $# -ge 2 ]] || exit 2; OUT="$2";shift 2;; --help|-h) echo "Usage: bash collect-local.sh --output inventory.json";exit 0;; *) echo "Unsupported argument" >&2;exit 2;; esac;done
[[ -n "$OUT" ]] || { echo "Specify --output" >&2; exit 2; }
command -v python3 >/dev/null || { echo "Python 3 is required for safe JSON serialization" >&2;exit 1; }
export AW_HOST="$(hostname 2>/dev/null || true)"
export AW_OS="$(uname -s 2>/dev/null || true)"
export AW_ARCH="$(uname -m 2>/dev/null || true)"
export AW_CPU="$(uname -p 2>/dev/null || true)"
export AW_RAM=""
if [[ -r /proc/meminfo ]]; then AW_RAM="$(awk '/^MemTotal:/{printf "%.1f GiB",$2/1048576;exit}' /proc/meminfo)";elif command -v sysctl >/dev/null;then AW_RAM="$(sysctl -n hw.memsize 2>/dev/null | awk '{if($1~/^[0-9]+$/)printf "%.1f GiB",$1/1073741824}')";fi
export AW_RAM
if [[ -r /etc/os-release ]]; then . /etc/os-release; export AW_OS="${PRETTY_NAME:-$AW_OS}";elif [[ "$(uname -s)" == "Darwin" ]] && command -v sw_vers >/dev/null;then AW_OS="macOS $(sw_vers -productVersion)";export AW_OS;fi
export AW_IP=""
if command -v ip >/dev/null;then AW_IP="$(ip -o -4 addr show scope global 2>/dev/null | awk 'NR==1{split($4,a,"/");print a[1]}')";elif command -v ipconfig >/dev/null;then AW_IP="$(ipconfig getifaddr en0 2>/dev/null || true)";fi
export AW_IP
python3 - "$OUT" <<'PY'
import datetime,json,os,sys,subprocess,re,platform
out=sys.argv[1]
def run(*args):
 try:
  r=subprocess.run(args,stdout=subprocess.PIPE,stderr=subprocess.DEVNULL,text=True,timeout=4,check=False)
  return r.stdout[:30000] if r.returncode==0 else ''
 except (OSError,subprocess.TimeoutExpired):return ''
host=os.environ.get('AW_HOST','')
asset={'name':host,'os':os.environ.get('AW_OS',''),'cpu':os.environ.get('AW_ARCH',''),'ram':os.environ.get('AW_RAM',''),'ip':os.environ.get('AW_IP',''),'notes':'Captura local declarativa; verificar datos antes de incorporar.'}
disks=run('lsblk','-dn','-o','NAME,SIZE,TYPE') if sys.platform.startswith('linux') else run('diskutil','list')
if disks:asset['storage']='; '.join(disks.splitlines()[:8])[:500]
networks=[]
if sys.platform.startswith('linux'):
 for line in run('ip','-o','-4','addr','show','scope','global').splitlines()[:24]:
  match=re.match(r'^\d+:\s+([^ ]+)\s+inet\s+([^ ]+)',line)
  if match:networks.append({'name':match.group(1),'cidr':match.group(2),'notes':'Interfaz local detectada; no demuestra segmentación ni ACL.'})
else:
 for line in run('ifconfig').splitlines():
  if line and not line[0].isspace():interface=line.split(':',1)[0]
  match=re.search(r'\binet\s+([0-9.]+)',line)
  if match and match.group(1)!='127.0.0.1':networks.append({'name':interface,'cidr':match.group(1),'notes':'Dirección detectada localmente, prefijo por verificar.'})
networks=networks[:24]
services=[]
if sys.platform.startswith('linux'):
 for line in run('systemctl','list-units','--type=service','--state=running','--no-legend','--no-pager').splitlines()[:35]:
  name=line.split()
  if name and name[0].endswith('.service'):services.append({'name':name[0], 'asset':host,'notes':'Servicio activo detectado; versión y exposición no verificadas.'})
elif sys.platform=='darwin':
 for line in run('launchctl','list').splitlines()[1:31]:
  parts=line.split(None,2)
  if len(parts)==3:services.append({'name':parts[2], 'asset':host,'notes':'Servicio launchd inventariado; revisar estado y exposición.'})
software=services[:35]
data={'kind':'audit-workbench-discovery-v1','schemaVersion':1,'capturedAt':datetime.datetime.now(datetime.timezone.utc).isoformat(),'source':{'platform':platform.system(),'collector':'collect-local.sh','scope':'local','mode':'read-only'},'items':{'assets':[asset],'networks':networks,'software':software}}
with open(out,'x',encoding='utf-8') as f:json.dump(data,f,indent=2,ensure_ascii=False)
print('Saved',out)
PY
