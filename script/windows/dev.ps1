# Starts Kiln Queue's development server on Windows. Run it through dev.cmd in
# the app folder, which gets past PowerShell's script execution policy:
#
#   .\dev.cmd                 start on port 3000 (or %PORT%)
#   .\dev.cmd --port 4000     start on 4000
#   .\dev.cmd --help          all options
#
# Before starting it checks that the port is free. If something is already
# listening, it tells you what it is and lets you stop it, move to the next free
# port or pick one yourself. Whatever port you end up on is checked the same way.
#
# The same options as ./dev on macOS and Linux.

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')
Set-Location $script:AppRoot

$PortWanted = 3000
if ($env:PORT) { $PortWanted = $env:PORT }
$Bind = ''
$Auto = $false
$DryRun = $false
$PidFile = Join-Path $script:AppRoot 'tmp/pids/server.pid'

function Show-Usage {
  @'
Usage: .\dev.cmd [options]

  -p, --port PORT   Port to start on (default: %PORT%, or 3000)
  -b, --bind ADDR   Address to listen on (default: Rails' own, localhost).
                    Use 0.0.0.0 to reach the app from another device.
      --auto        If the port is busy, move to the next free one without
                    asking. Also what happens when there is no terminal to ask.
      --dry-run     Check the port and print the server command, but do not
                    check gems or the database and do not start the server.
  -h, --help        Show this help

If the port is in use you can:
  k  stop the program using it
  n  move to the next free port
  c  choose a port yourself (checked the same way)
  a  stop it as administrator, when it belongs to another user or to Windows
  q  quit and leave everything as it is
'@ | Write-Host
}

$i = 0
while ($i -lt $args.Count) {
  $a = [string]$args[$i]
  switch -Regex ($a) {
    '^(-p|--port)$' { if ($i + 1 -ge $args.Count) { Stop-WithError '--port needs a number' }; $PortWanted = $args[$i + 1]; $i += 2; continue }
    '^--port=' { $PortWanted = $a.Substring(7); $i++; continue }
    '^(-b|--bind)$' { if ($i + 1 -ge $args.Count) { Stop-WithError '--bind needs an address' }; $Bind = [string]$args[$i + 1]; $i += 2; continue }
    '^--bind=' { $Bind = $a.Substring(7); $i++; continue }
    '^--auto$' { $Auto = $true; $i++; continue }
    '^--dry-run$' { $DryRun = $true; $i++; continue }
    '^(-h|--help|/\?)$' { Show-Usage; exit 0 }
    default { Write-Err "Unknown option: $a"; Show-Usage; exit 2 }
  }
}

function Test-ValidPort($Value) {
  $n = 0
  if (-not [int]::TryParse([string]$Value, [ref]$n)) { return $false }
  return ($n -ge 1 -and $n -le 65535)
}
if (-not (Test-ValidPort $PortWanted)) { Stop-WithError "'$PortWanted' is not a port number (1-65535)." }
$PortWanted = [int]$PortWanted

# ---- who is using a port --------------------------------------------------

function Get-ProcessName([int]$ProcessId) {
  if ($ProcessId -eq 4) { return 'System' }
  $p = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
  if ($p) { return $p.ProcessName }
  return 'unknown'
}

function Show-ProcessInfo([int]$ProcessId) {
  $name = Get-ProcessName $ProcessId
  $command = ''
  $folder = ''
  if (Test-IsWindows) {
    try {
      $cim = Get-CimInstance Win32_Process -Filter "ProcessId = $ProcessId" -ErrorAction Stop
      if ($cim.CommandLine) { $command = $cim.CommandLine }
      elseif ($cim.ExecutablePath) { $command = $cim.ExecutablePath }
    } catch {
      $command = ''  # another user's process: Windows hides its command line
    }
  } else {
    $r = Invoke-Program 'ps' @('-o', 'args=', '-p', "$ProcessId")
    if ($r.Code -eq 0) { $command = $r.Output.Trim() }
    if (Get-Command lsof -ErrorAction SilentlyContinue) {
      $r = Invoke-Program 'lsof' @('-a', '-p', "$ProcessId", '-d', 'cwd', '-Fn')
      $line = ($r.Output -split "`r?`n" | Where-Object { $_ -like 'n*' } | Select-Object -First 1)
      if ($line) { $folder = $line.Substring(1) }
    }
  }
  if ($command.Length -gt 110) { $command = $command.Substring(0, 110) }

  Write-Host "    $name" -NoNewline -ForegroundColor White
  Write-Host "  pid $ProcessId"
  if ($ProcessId -eq 4) {
    Write-Dim 'Windows itself (http.sys): usually IIS, a Windows service or a registered URL.'
  }
  if ($command) { Write-Dim "command: $command" }
  if ($folder) { Write-Dim "folder:  $folder" }
  if ($command -match 'puma|rails' -and $command -match 'kiln_queue') {
    Write-Dim '(this looks like Kiln Queue itself, probably from another terminal)'
  }
}

# The kill program, not PowerShell's kill alias for Stop-Process. Only used
# outside Windows.
function Get-UnixKill { return (Get-Command kill -CommandType Application | Select-Object -First 1).Source }

function Test-ProcessAlive([int]$ProcessId) {
  $p = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
  if (-not $p) { return $false }
  if (-not (Test-IsWindows)) {
    $r = Invoke-Program 'ps' @('-o', 'stat=', '-p', "$ProcessId")
    if ($r.Output -match 'Z') { return $false }
  }
  return $true
}

function Stop-AsAdmin([int[]]$Ids) {
  if (-not (Test-IsWindows)) {
    & sudo kill -TERM @Ids
    return
  }
  $list = ($Ids -join ',')
  Write-Info 'Windows will ask for permission (UAC)...'
  try {
    Start-Process powershell.exe -Verb RunAs -Wait -WindowStyle Hidden -ArgumentList @('-NoProfile', '-Command', "Stop-Process -Id $list -Force")
  } catch {
    Write-Warn 'Permission was not given.'
  }
}

function Wait-PortFree([int]$Port) {
  for ($w = 0; $w -lt 25; $w++) {
    if (-not (Test-PortInUse $Port)) { return $true }
    Start-Sleep -Milliseconds 200
  }
  return (-not (Test-PortInUse $Port))
}

function Stop-Listeners([int]$Port, [int[]]$Ids) {
  if (Test-IsWindows) {
    # Windows cannot ask a console program to shut down politely from outside,
    # so this ends it at once. Say so before doing it.
    $names = ($Ids | ForEach-Object { "$(Get-ProcessName $_) (pid $_)" }) -join ', '
    if (-not (Confirm-Step "End $names now? Anything unsaved in it is lost." $true)) { return }
    $denied = @()
    foreach ($id in $Ids) {
      try { Stop-Process -Id $id -Force -ErrorAction Stop } catch { $denied += $id }
    }
    if ($denied.Count -gt 0) {
      Write-Warn "Not allowed to stop pid $($denied -join ', '): it belongs to another user or to Windows."
      if (Confirm-Step 'Stop it as administrator?' $false) { Stop-AsAdmin $denied }
    }
  } else {
    foreach ($id in $Ids) {
      Write-Info "Stopping $(Get-ProcessName $id) (pid $id)..."
      & (Get-UnixKill) -TERM $id 2>$null
      if ($LASTEXITCODE -ne 0 -and (Test-ProcessAlive $id)) {
        Write-Warn "Not allowed to stop pid ${id}: it belongs to another user."
        if (Confirm-Step 'Stop it with sudo?' $false) { Stop-AsAdmin @($id) }
      }
    }
  }

  if (-not (Wait-PortFree $Port)) {
    $still = @(Get-ListenerPids $Port)
    if ($still.Count -gt 0 -and -not (Test-IsWindows)) {
      if (Confirm-Step 'Still running after 5 seconds. Force it to stop (no chance to clean up)?' $false) {
        foreach ($id in $still) { & (Get-UnixKill) -KILL $id 2>$null }
        Start-Sleep -Milliseconds 500
      }
    }
  }
  if (Test-PortInUse $Port) { Write-Warn "Port $Port is still busy." } else { Write-Ok "Port $Port is free now." }
}

function Get-NextFreePort([int]$Port) {
  for ($p = $Port + 1; $p -le [Math]::Min($Port + 100, 65535); $p++) {
    if (-not (Test-PortInUse $p)) { return $p }
  }
  return $null
}

# ---- a server this app already started -----------------------------------

function Test-PidFile {
  if (-not (Test-Path $PidFile)) { return }
  $raw = (Get-Content $PidFile -Raw) -replace '[^0-9]', ''
  $id = 0
  if (-not [int]::TryParse($raw, [ref]$id) -or -not (Test-ProcessAlive $id)) {
    Remove-Item $PidFile -Force
    Write-Ok 'Removed a stale tmp/pids/server.pid left by a server that did not shut down cleanly.'
    return
  }
  Write-Step 'Kiln Queue is already running'
  Show-ProcessInfo $id
  Write-Info 'Rails will not start a second server from the same folder while it runs.'
  if (Confirm-Step 'Stop it and start a fresh one?' $true) {
    Stop-Process -Id $id -Force -ErrorAction SilentlyContinue
    for ($w = 0; $w -lt 25 -and (Test-ProcessAlive $id); $w++) { Start-Sleep -Milliseconds 200 }
    if (Test-ProcessAlive $id) { Stop-WithError "It did not stop. Try: Stop-Process -Id $id -Force" }
    Remove-Item $PidFile -Force -ErrorAction SilentlyContinue
    Write-Ok 'Stopped.'
  } else {
    Write-Info 'Leaving it running.'
    exit 0
  }
}

# ---- choosing the port ----------------------------------------------------

function Select-Port([int]$Port) {
  while (Test-PortInUse $Port) {
    Write-Step "Port $Port is already in use"
    $ids = @(Get-ListenerPids $Port)
    if ($ids.Count -gt 0) {
      foreach ($id in $ids) { Show-ProcessInfo $id }
    } elseif (Test-IsWindows) {
      Write-Warn 'Nothing visible is listening, but Windows will not let the app use this port.'
      Write-Dim 'It is probably reserved for Hyper-V, WSL or Docker. To see the reserved ranges:'
      Write-Dim 'netsh interface ipv4 show excludedportrange protocol=tcp'
    } else {
      Write-Warn 'Something is listening, but it belongs to another user, so its name is hidden.'
    }

    $next = Get-NextFreePort $Port

    if ($Auto -or -not (Test-Interactive)) {
      if (-not $Auto) { Stop-WithError "No terminal to ask in. Free port $Port, pass --port, or use --auto to take the next free one." }
      if (-not $next) { Stop-WithError "No free port found between $($Port + 1) and $($Port + 100)." }
      Write-Info "--auto: moving to port $next."
      $Port = $next
      continue
    }

    Write-Host ''
    if ($ids.Count -gt 0) { Write-Info "[k] Stop $(Get-ProcessName $ids[0]) (pid $($ids -join ', '))" }
    if ($ids.Count -gt 0 -and (Test-IsWindows)) { Write-Info '[a] Stop it as administrator' }
    if ($next) { Write-Info "[n] Use the next free port ($next)" }
    Write-Info '[c] Choose another port'
    Write-Info '[q] Quit and leave it running'
    $choice = Read-Answer 'Your choice:'
    if ($null -eq $choice) { $choice = 'q' }

    switch -Regex ($choice) {
      '^[kK]$' {
        if ($ids.Count -gt 0) { Stop-Listeners $Port $ids } else { Write-Info 'Nothing visible to stop.' }
      }
      '^[aA]$' {
        if ($ids.Count -gt 0) { Stop-AsAdmin $ids; [void](Wait-PortFree $Port) } else { Write-Info 'Nothing visible to stop.' }
      }
      '^[nN]$' {
        if ($next) { $Port = $next } else { Write-Warn 'No free port nearby. Choose one with [c].' }
      }
      '^[cC]$' {
        while ($true) {
          $custom = Read-Answer 'Port (1024-65535):'
          if ($null -eq $custom) { Stop-WithError 'No port given.' }
          if (-not (Test-ValidPort $custom)) { Write-Warn "'$custom' is not a port number."; continue }
          if ([int]$custom -lt 1024 -and -not (Confirm-Step "Ports below 1024 often need administrator rights. Use $custom anyway?" $false)) { continue }
          $Port = [int]$custom
          break
        }
      }
      '^([qQ]|)$' {
        Write-Info 'Quitting. Nothing was changed.'
        exit 1
      }
      default { Write-Warn 'Please type one of the letters in brackets.' }
    }
  }
  return $Port
}

# ---- app checks -----------------------------------------------------------

$script:Ruby = $null

function Test-App {
  Write-Step 'Checking the app'
  $script:Ruby = Get-SavedRuby
  if (-not $script:Ruby) {
    Write-Warn 'Setup has not been run on this machine yet.'
    if (-not (Confirm-Step 'Run setup now?' $true)) { Stop-WithError 'Run .\setup.cmd first.' }
    & (Join-Path $PSScriptRoot 'setup.ps1')
    if ($LASTEXITCODE -ne 0) { Stop-WithError 'Setup failed. Fix what it reported and run .\dev.cmd again.' }
    $script:Ruby = Get-SavedRuby
    if (-not $script:Ruby) { Stop-WithError 'Setup did not record a Ruby. Run .\setup.cmd again and check its output.' }
  }
  Write-Ok "Ruby $(Get-RubyVersion $script:Ruby) ($script:Ruby)"

  if ((Invoke-Program $script:Ruby @('-S', 'bundle', 'check')).Code -ne 0) {
    Write-Warn 'Some gems are missing (the Gemfile probably changed).'
    if (-not (Confirm-Step 'Run bundle install now?' $true)) { Stop-WithError 'Run bundle install, then .\dev.cmd again.' }
    if ((Invoke-Logged 'bundle-install' $script:Ruby @('-S', 'bundle', 'install')) -ne 0) { Stop-WithError 'bundle install failed.' }
  }
  Write-Ok 'Gems installed'

  if ((Invoke-Logged 'db-prepare' $script:Ruby @('bin/rails', 'db:prepare')) -ne 0) {
    Stop-WithError 'Could not prepare the database. See the error above.'
  }
  Write-Ok 'Database ready'
}

# ---- go ---------------------------------------------------------------------

if (-not $DryRun) { Test-App }
Test-PidFile
$ChosenPort = Select-Port $PortWanted

$serverArgs = @('bin/rails', 'server', '-p', "$ChosenPort")
if ($Bind) { $serverArgs += @('-b', $Bind) }

Write-Step "Starting Kiln Queue on port $ChosenPort"
Write-Info "Open http://localhost:$ChosenPort"
Write-Info "Live Share: in the Live Share panel, Shared Servers > Share server > $ChosenPort,"
Write-Info 'so your guest can open the app too.'
Write-Info 'Stop the server with Ctrl-C.'

if ($DryRun) {
  Write-Info "Dry run, would now run: $($serverArgs -join ' ')"
  exit 0
}

& $script:Ruby @serverArgs
exit $LASTEXITCODE
