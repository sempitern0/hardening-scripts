# DEBIAN AD Assistant — GPO Operations Guide v4.4.0

This guide accompanies `debian-ad-assistant-v4.4.0-gpo-library.sh`.

## Persistent paths

The assistant keeps policy source files under:

```text
/var/lib/debian-ad-assistant/gpo/
├── builtin/
│   └── windows/
│       ├── sec-powershell-logging.json
│       ├── sec-disable-llmnr.json
│       ├── sec-smb-guest.json
│       ├── sec-rdp-nla.json
│       ├── sec-screen-lock.json
│       ├── sec-disable-alwaysinstallelevated.json
│       ├── sec-legal-notice.json
│       └── sec-workstation-starter-combined.json
├── custom/
│   └── example-custom-policy.json
└── GPO-GUIDE.md
```

`builtin/` is managed by the assistant. Copy a file to `custom/` before editing it.

## Samba JSON format

Example:

```json
[
  {
    "keyname": "SOFTWARE\\Policies\\Example\\Product",
    "valuename": "SettingName",
    "class": "MACHINE",
    "type": "REG_DWORD",
    "data": 1
  }
]
```

`class` can be `MACHINE`, `USER`, or `BOTH`.

Validate before loading:

```bash
python3 -m json.tool policy.json
```

Load by merging:

```bash
samba-tool gpo load '{GUID}' --content=policy.json
```

Replace existing Registry policies in that GPO:

```bash
samba-tool gpo load '{GUID}' --content=policy.json --replace
```

Remove values with a JSON containing `keyname`, `valuename`, and `class`:

```bash
samba-tool gpo remove '{GUID}' --content=remove.json
```

The assistant automates all three operations and backs up the selected GPO first.

## Actual GPO storage

The JSON library is only source material. The actual GPO consists of:

- LDAP: `CN={GUID},CN=Policies,CN=System,<domain DN>`
- SYSVOL: `<SYSVOL>/<domain>/Policies/{GUID}/`

Do not manually construct or delete those directories.

## Enable / disable state

AD stores GPO state in the `flags` attribute:

- `0`: enabled
- `1`: user configuration disabled
- `2`: computer configuration disabled
- `3`: all settings disabled

This is independent from GPO links. A GPO can be enabled and unlinked, or linked and disabled.

Use `ad-gpo` → **GPO status**.

## Recommended staging

Use the Windows catalog → **Stage starter pack** to create and load the core GPOs as:

```text
ALL_DISABLED + UNLINKED
```

Then:

1. inspect the GPO;
2. link it to a test OU;
3. enable the required machine/user settings;
4. test on a client;
5. expand scope.

## Ubuntu ADSys

Generate templates on an Ubuntu client with the same ADSys generation you intend to support:

```bash
mkdir -p ~/adsys-admx
cd ~/adsys-admx
adsysctl policy admx lts-only
```

or:

```bash
adsysctl policy admx all
```

This produces:

```text
Ubuntu.admx
Ubuntu.adml
```

The assistant installs them to the detected Central Store:

```text
<SYSVOL>/<domain>/Policies/PolicyDefinitions/Ubuntu.admx
<SYSVOL>/<domain>/Policies/PolicyDefinitions/en-US/Ubuntu.adml
```

Use `ad-gpo` → Platform GPO catalog → Ubuntu ADSys clients.

Do not assume a Windows Registry JSON file is meaningful to ADSys. Use Ubuntu's generated templates and documented Registry mapping for the ADSys version used on the client.

## Samba Linux

For Samba/winbind Linux clients, use Samba's native policy managers:

```bash
samba-tool gpo manage smb_conf ...
samba-tool gpo manage access ...
samba-tool gpo manage openssh ...
samba-tool gpo manage sudoers ...
samba-tool gpo manage scripts ...
samba-tool gpo manage motd ...
```

Support varies by Samba version. The assistant checks runtime capability where possible.

## Useful menu path

```text
sudo ad-gpo
  1  List GPOs + GUIDs + status
  4  Platform GPO catalog
  5  JSON policy library
  6  GPO status
  7  List linked containers
  8  Link/update
  9  Remove link
 10  Backup
 11  Readiness
 14  Paths & manual
```
