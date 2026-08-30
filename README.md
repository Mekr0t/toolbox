# Toolbox

A personal, WinUtil-style installer for Windows, served from your own Linux box.

```powershell
irm https://tools.romansafranko.com | iex
```

That downloads one PowerShell file, relaunches itself elevated, pulls your
catalog as JSON, and opens a GUI. Tick things, press a button, walk away.

> **Always include `https://` in the one-liner.** PowerShell 5.1 -- the one on a
> fresh Windows box -- is built on .NET's `HttpWebRequest`, which refuses to
> follow a redirect that changes scheme. A bare `irm tools.example.com` resolves
> to `http://`, hits Caddy's HTTP-to-HTTPS redirect, and dies with
> "(308) Permanent Redirect". PowerShell 7 follows it fine, which is exactly why
> it is easy to miss.


Nothing is compiled and nothing is installed on the Windows side -- the GUI is
WPF, which ships with Windows. The only thing on the server is a static file
directory behind Caddy.

## Layout

```
catalog/            the part you actually edit -- one JSON file per category
  apps/             *.json, each an array of app entries
  tweaks/           *.json, registry / service / scheduled-task changes
  scripts/          *.json, one-off things to run
  presets.json      named bundles ("Dev machine", "Gaming rig", ...)
payloads/           .ps1 files that catalog entries pull in for anything complex
src/                the GUI itself, concatenated in filename order at build time
dist/               generated -- this is what gets uploaded
server/             Caddy + docker compose for the Linux side
tools/              build helpers, smoke test, offline preview
```

## Setup

```powershell
git clone <this repo> toolbox
cd toolbox
copy toolbox.config.example.json toolbox.config.json   # then set baseUrl
.\build.ps1
powershell -NoProfile -STA -File .\tools\preview.ps1   # look at it, no deploy
.\deploy.ps1                                           # build + scp to the server
```

Two files are yours and are gitignored, each with an `.example` beside it:
`toolbox.config.json` (your domain and deploy target) and `server/.env` (the
domain Caddy serves).

Before using it as your own, edit `payloads/my-dev-setup.ps1` -- it ships with a
placeholder git identity and refuses to configure git until you change it.

Your host goes in `toolbox.config.json`:

```json
{
  "baseUrl": "https://tools.example.com",
  "version": "1.0.0",
  "deploy": { "host": "you@your-server", "path": "/srv/toolbox" }
}
```

`baseUrl` is baked into the built script, so the GUI knows where to fetch the
catalog and payloads from. Change it, rebuild, redeploy.

## Server setup

On the Linux box:

```bash
git clone <this repo> /srv/toolbox && cd /srv/toolbox
cp server/.env.example server/.env      # set TOOLBOX_DOMAIN
cd server && docker compose up -d
```

The compose file mounts `../dist`, so the repo root on the server must be the
same folder your `dist/` lands in -- that is why `deploy.path` is
`/srv/toolbox/dist`. Either push it from Windows with `.\deploy.ps1`, or build
in place on the server with `./build.sh` (needs `jq`).

Point an A record at the box. Caddy gets the certificate itself. The Caddyfile
maps `/` to `toolbox.ps1` and forces `text/plain`, which is what makes the bare
`irm https://tools.example.com | iex` work.

### Keeping it private

It is your catalog on the public internet, so pick one:

- **Secret path** -- set `baseUrl` to `https://tools.example.com/s/8f3a...` and
  deploy into `/srv/toolbox/s/8f3a...`. The try_files rule already handles
  subdirectories, and the one-liner stays short. Simplest option that keeps the
  `irm | iex` UX.
- **Tailscale / WireGuard** -- bind Caddy to the tailnet address only. Most
  private, but the target machine has to be on your VPN before it can bootstrap.
- **IP allowlist** -- add a `@home remote_ip 1.2.3.4` matcher in the Caddyfile.

Basic auth technically works but breaks the one-liner, since `irm` would need
credentials passed in.

## Headless mode

`iex` cannot take parameters, so the one-liner is configured with environment
variables instead:

| variable | effect |
|---|---|
| `TOOLBOX_PRESET` | run a preset by id or name, no GUI (`dev`, or `dev,gaming`) |
| `TOOLBOX_APPS` | comma-separated app ids, on top of any preset |
| `TOOLBOX_TWEAKS` | comma-separated tweak ids |
| `TOOLBOX_SCRIPTS` | comma-separated script ids |
| `TOOLBOX_ACTION` | `install` (default) or `uninstall` -- reverses apps and tweaks |
| `TOOLBOX_DRYRUN` | `1` logs what would happen and changes nothing |
| `TOOLBOX_LIST` | `1` prints every id and install state; `short` prints just the names |
| `TOOLBOX_BASE` | override the catalog location -- a URL, or a folder |

```powershell
# what is in here? (names only, instant - skips the install scan)
$env:TOOLBOX_LIST='short'; irm https://tools.you.dev | iex

# the same with ids and install state
$env:TOOLBOX_LIST='1'; irm https://tools.you.dev | iex

# set up a fresh machine and walk away
$env:TOOLBOX_PRESET='dev'; irm https://tools.you.dev | iex

# a couple of things, without touching the machine
$env:TOOLBOX_APPS='vscode,git'; $env:TOOLBOX_DRYRUN='1'; irm https://tools.you.dev | iex

# undo what a preset did
$env:TOOLBOX_PRESET='gaming'; $env:TOOLBOX_ACTION='uninstall'; irm https://tools.you.dev | iex
```

Setting any selection variable skips the window entirely -- the same worker runs
the same plan and logs to the console instead. Order is always apps, then
tweaks, then scripts, so a personal script can rely on the thing it configures
already being there.

Exit codes: `0` everything worked, `1` at least one task failed, `2` an id
matched nothing.

Three details worth knowing:

- **Listing and dry runs never ask for elevation**, since neither changes
  anything. Everything else relaunches elevated first.
- **The elevated relaunch re-emits your variables.** `Start-Process -Verb RunAs`
  goes through ShellExecute and the elevated child gets a fresh environment
  block, so nothing set in your shell would otherwise survive. Preflight rebuilds
  every `TOOLBOX_*` variable into the command the new process runs.
- **A relaunched headless run waits for a keypress** before closing -- otherwise
  the new console window would vanish and take the log with it. Already-elevated
  runs (an unattended `SetupComplete.cmd`, say) exit silently with a code.

### Testing on a clean VM

The server does not have to be up. `TOOLBOX_BASE` takes a folder as well as a
URL, so copying `dist\` into the VM is enough:

```powershell
$env:TOOLBOX_BASE='C:\toolbox-dist'
$env:TOOLBOX_PRESET='minimal'
powershell -NoProfile -ExecutionPolicy Bypass -File C:\toolbox-dist\toolbox.ps1
```

Once the server is live, test the real thing:

```powershell
$env:TOOLBOX_PRESET='dev'; irm https://tools.you.dev | iex
```

Take a VM snapshot first and roll back between runs -- that is the Home-edition
equivalent of Windows Sandbox, which needs Pro.

## Adding things

### An app

Drop it into any file under `catalog/apps/` (or make a new file -- every `.json`
in the folder is merged):

```json
{
  "id": "obsidian",
  "name": "Obsidian",
  "category": "Notes",
  "description": "Markdown notes",
  "install": [
    { "type": "winget", "id": "Obsidian.Obsidian" },
    { "type": "choco",  "id": "obsidian" }
  ]
}
```

`install` is a fallback chain, tried top to bottom until one works, so the choco
line only runs if winget failed. `uninstall` is optional -- without it the same
ids are reused for removal. A new `category` string creates a new group in the
GUI by itself.

Install step types:

| type | fields | notes |
|---|---|---|
| `winget` | `id`, `args` | bootstraps App Installer if winget is missing |
| `choco` | `id`, `args` | installs Chocolatey on first use |
| `scoop` | `id`, `args` | per-user; installed with `-RunAsAdmin` |
| `download` | `url`, `args`, `file` | .msi/.exe/.msix/.zip, silent switches applied |
| `script` | `path` | runs a payload, for anything the above cannot express |
| `appx` | `id` | **uninstall only** - preinstalled Store apps, wildcards allowed |

Deleting an app is deleting its JSON object. Nothing else references it except
presets, and the build warns about presets pointing at ids that no longer exist.

### Already-installed detection

The Apps tab marks what you already have — a green `installed 1.134.0` beside
the name — and a **Hide installed** toggle in the header filters them out. The
headless listing marks them with `*`.

It is one pass over Add/Remove Programs (both HKLM hives plus HKCU) taken after
the window is up, so startup stays instant, and repeated after every install so
the markers never go stale.

Matching is on the **whole** catalog name, which is why `Git` does not report
itself installed just because `GitHub Desktop` is there. When that is not enough,
add a `detect` block:

```json
"detect": { "name": "^Node" }
"detect": { "command": "wt" }
"detect": { "path": "%ProgramFiles%/Foo/foo.exe" }
"detect": { "appx": "Microsoft.WindowsTerminal" }
```

| key | use it when |
|---|---|
| `name` | the ARP display name differs from your catalog name (`Node.js LTS` vs `Node.js`) |
| `command` | the app is only identifiable by something on `PATH` |
| `path` | a known install location is the only reliable signal |
| `appx` | MSIX/Store packages, which never appear in Add/Remove Programs |

`appx` costs roughly 300 ms per entry because it queries the Appx stack, so use
it only where nothing else works. The other three are free.

Detection is advisory — nothing is skipped or blocked because an app is already
installed. Reinstalling is harmless anyway: winget's "already installed" exit
codes count as success.

### Debloat entries

Preinstalled Store apps never appear in Add/Remove Programs, so they need the
`appx` type. They live in the `Debloat` category as removal-only entries -- an
`uninstall` chain and a `detect` block, no `install`:

```json
{
  "id": "bloat-bing",
  "name": "Bing News, Weather and Search",
  "category": "Debloat",
  "detect": { "appx": "Microsoft.BingNews" },
  "uninstall": [ { "type": "appx", "id": "Microsoft.Bing*" } ]
}
```

The wildcard matters: `uninstall` is a fallback chain that stops at the first
success, so one step with `Microsoft.Bing*` removes News, Weather and Search,
whereas three separate steps would remove only the first. Removal also drops the
*provisioned* copy, so a new user profile does not get the app back.

Reinstalling means the Microsoft Store -- selecting a debloat entry and pressing
Install logs a message saying so rather than failing silently.

**Not included on purpose:** OEM software. On an ASUS machine, Armoury Crate and
the AURA services drive fan curves, RGB and hotkeys; removing them wholesale
breaks hardware behaviour. Uninstall those by hand once you know what each does.

### A tweak

```json
{
  "id": "disable-startup-sound",
  "name": "Disable the startup sound",
  "category": "Appearance",
  "registry": [
    { "path": "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System",
      "name": "DisableStartupSound", "type": "DWord", "value": 1 }
  ]
}
```

Also available on a tweak: `services`
(`[{ "name": "DiagTrack", "startup": "Disabled" }]`), `tasks` (scheduled task
paths to disable), and `apply` / `undo` payload paths for anything else.

**Undo works without you writing it.** Before a tweak touches anything, the
previous value of every key and service is written to
`C:\ProgramData\Toolbox\backups\<id>.json`. "Undo selected" restores from that
file and deletes values that did not exist before. Only the first apply is
recorded, so re-applying never overwrites the pristine original.

Backslashes in JSON must be doubled. If an editor eats them, run
`.\tools\normalize-catalog.ps1` -- it fixes every file and is safe to re-run.

### A script

```json
{
  "id": "my-dev-setup",
  "name": "My dev environment bootstrap",
  "category": "Personal",
  "run": "payloads/my-dev-setup.ps1"
}
```

Payloads run inside the worker runspace, so `Write-Log`, `Invoke-Cli`,
`Get-WingetPath` and friends are available:

```powershell
Write-Log '  doing the thing' 'dim'
Invoke-Cli -FilePath 'git' -Arguments 'clone https://github.com/me/dotfiles' | Out-Null
Write-Log '  done' 'ok'
```

`payloads/my-dev-setup.ps1` is already stubbed with git identity, an SSH key and
folder creation -- edit that rather than starting from scratch.

### A preset

`catalog/presets.json` maps a name to lists of ids. Picking one in the header and
pressing **Select** ticks those boxes; nothing installs until you press Install,
so you can adjust the selection first.

## Editing the GUI

`src/*.ps1` is concatenated in filename order into one file, so the numbering is
the load order:

| file | what it does |
|---|---|
| `00-Preflight.ps1` | run mode, elevation + STA relaunch, global paths |
| `10-Log.ps1` | the synchronized state shared with the worker |
| `20-Util.ps1` | http fetch, process runner, JSON helpers |
| `30-Manifest.ps1` | catalog fetch and category grouping |
| `40-Providers.ps1` | winget / choco / scoop / direct download |
| `50-Actions.ps1` | app install + uninstall |
| `55-Tweaks.ps1` | registry, services, tasks, backup and restore |
| `60-Worker.ps1` | the background runspace |
| `70-Xaml.ps1` | window layout |
| `80-Gui.ps1` | rendering the catalog, wiring buttons |
| `90-Headless.ps1` | the no-window renderer and id resolution |
| `99-Main.ps1` | entry point |

Installing happens in a second STA runspace, so the window never goes white. The
worker never touches a WPF object -- it pushes log lines into a concurrent queue
and a 150 ms `DispatcherTimer` on the UI thread drains it.

Adding a package manager means writing `Install-ViaX` / `Uninstall-ViaX` in
`40-Providers.ps1`, adding the type to the switch in `50-Actions.ps1`, and
listing the new function names in `$WorkerFunctions` in `60-Worker.ps1` -- that
array is what gets injected into the worker runspace.

## Testing before you deploy

```powershell
.\build.ps1
powershell -NoProfile -STA -File .\tools\smoke-test.ps1
```

Twenty-one checks: every module loads, the XAML parses, every catalog entry
renders, presets resolve to real ids, referenced payloads exist, a plan runs end
to end in the worker, and the built artifact is driven headlessly in a child
process (list mode, preset ordering, unknown ids, uninstall). It touches nothing
on the machine -- the headless checks all run with `TOOLBOX_DRYRUN`.

To see the whole catalog without touching the server at all:

```powershell
.\tools\catalog.ps1          # names only, grouped - about 25 lines
.\tools\catalog.ps1 -Full    # ids, categories and install state
```

To exercise the true one-liner path, serve `dist\` locally from an **elevated**
prompt:

```powershell
.\build.ps1 -BaseUrl http://localhost:8080
.\tools\serve.ps1
irm http://localhost:8080 | iex
```

## Notes

- Run the "Create a system restore point" script before applying tweaks on a
  machine you care about.
- Logs land in `C:\ProgramData\Toolbox\toolbox-<date>.log`.
- winget's "already installed" exit codes count as success, so re-running an
  install is harmless.
- Cancel finishes the task in flight and then stops -- it does not kill an
  installer mid-write.

## Troubleshooting

| symptom | cause |
|---|---|
| `(308) Permanent Redirect` | the one-liner is missing `https://` -- see the note at the top |
| `Unexpected token '187'` | the served `toolbox.ps1` has a UTF-8 BOM; rebuild, `build.ps1` strips it |
| `Invalid JSON primitive: i` | same BOM, on `manifest.json` |
| `curl : A parameter cannot be found that matches 'sSI'` | in PowerShell `curl` is an alias for `Invoke-WebRequest`; use `curl.exe` |
| 404 from a working Caddy | `dist/` is empty on the server -- run `.\deploy.ps1` |
| no `Content-Type` on `/` | the Caddyfile `header` lines must sit inside the `route` block, after `try_files` |
