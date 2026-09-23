# Shared helpers for script/windows/setup.ps1 and dev.ps1. Dot-sourced, not run.
#
# Written for Windows PowerShell 5.1, which every Windows 10 and 11 machine has,
# so: no ?? or ?: operators, no && between commands, and ASCII only (5.1 reads a
# file without a byte order mark as the local code page). Also runs under
# PowerShell 7 on any platform, which is how the tests run outside Windows.

$script:AppRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$script:AssumeYes = $false
$script:RubyChoiceFile = Join-Path $script:AppRoot 'tmp/.kiln-ruby-exe'

# ---- platform -------------------------------------------------------------

function Test-IsWindows { return ($env:OS -eq 'Windows_NT') }

# ---- output ---------------------------------------------------------------

function Write-Step([string]$Text) { Write-Host ''; Write-Host "==> $Text" -ForegroundColor Cyan }
function Write-Info([string]$Text) { Write-Host "    $Text" }
function Write-Ok([string]$Text) { Write-Host '    ok ' -ForegroundColor Green -NoNewline; Write-Host $Text }
function Write-Warn([string]$Text) { Write-Host '    !  ' -ForegroundColor Yellow -NoNewline; Write-Host $Text }
function Write-Err([string]$Text) { Write-Host "    x  $Text" -ForegroundColor Red }
function Write-Dim([string]$Text) { Write-Host "    $Text" -ForegroundColor DarkGray }

function Stop-WithError([string]$Text) {
  Write-Err $Text
  exit 1
}

# ---- prompts --------------------------------------------------------------

# True when there is a person at the keyboard to ask. The two environment
# variables let the tests force either answer.
function Test-Interactive {
  if ($env:KILN_FORCE_NONINTERACTIVE) { return $false }
  if ($env:KILN_FORCE_INTERACTIVE) { return $true }
  return (-not [Console]::IsInputRedirected)
}

# Reads one line. [Console]::ReadLine rather than Read-Host, so answers can be
# piped in by the tests.
function Read-Answer([string]$Prompt) {
  Write-Host "    ? $Prompt " -NoNewline
  $line = [Console]::ReadLine()
  Write-Host ''
  if ($null -eq $line) { return $null }
  return $line.Trim()
}

function Confirm-Step([string]$Question, [bool]$Default = $true) {
  if ($Default) { $hint = '[Y/n]' } else { $hint = '[y/N]' }
  if ($script:AssumeYes -or -not (Test-Interactive)) {
    if ($Default) { $d = 'y' } else { $d = 'n' }
    Write-Info "$Question $hint $d (automatic)"
    return $Default
  }
  while ($true) {
    $answer = Read-Answer "$Question $hint"
    if ($null -eq $answer -or $answer -eq '') { return $Default }
    switch -Regex ($answer) {
      '^(y|yes)$' { return $true }
      '^(n|no)$' { return $false }
      default { Write-Info 'Please answer y or n.' }
    }
  }
}

# ---- running programs -----------------------------------------------------

# Builds a command line that Windows programs (and .NET on other platforms)
# split back into exactly these arguments.
function ConvertTo-ArgumentString([string[]]$Arguments) {
  $parts = foreach ($a in $Arguments) {
    if ($a -eq '') { '""'; continue }
    if ($a -notmatch '[\s"]') { $a; continue }
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('"')
    $backslashes = 0
    foreach ($ch in $a.ToCharArray()) {
      if ($ch -eq '\') { $backslashes++; continue }
      if ($ch -eq '"') {
        [void]$sb.Append('\' * ($backslashes * 2 + 1))
      } elseif ($backslashes -gt 0) {
        [void]$sb.Append('\' * $backslashes)
      }
      $backslashes = 0
      [void]$sb.Append($ch)
    }
    [void]$sb.Append('\' * ($backslashes * 2))
    [void]$sb.Append('"')
    $sb.ToString()
  }
  return ($parts -join ' ')
}

# Runs a program without a shell in between, and returns its exit code and
# everything it printed. Bypasses PowerShell 5.1's habit of turning a native
# program's stderr into errors.
function Invoke-Program([string]$Exe, [string[]]$Arguments, [hashtable]$Environment = @{}) {
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $Exe
  $psi.Arguments = ConvertTo-ArgumentString $Arguments
  $psi.UseShellExecute = $false
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.WorkingDirectory = $script:AppRoot
  foreach ($key in $Environment.Keys) { $psi.EnvironmentVariables[$key] = $Environment[$key] }
  $p = [System.Diagnostics.Process]::Start($psi)
  $out = $p.StandardOutput.ReadToEndAsync()
  $err = $p.StandardError.ReadToEndAsync()
  $p.WaitForExit()
  return New-Object PSObject -Property @{ Code = $p.ExitCode; Output = ($out.Result + $err.Result) }
}

# Same, but keeps the output in log/setup/NAME.log and shows its tail on failure.
function Invoke-Logged([string]$Name, [string]$Exe, [string[]]$Arguments, [hashtable]$Environment = @{}) {
  $logDir = Join-Path $script:AppRoot 'log/setup'
  New-Item -ItemType Directory -Force $logDir | Out-Null
  $log = Join-Path $logDir "$Name.log"
  $result = Invoke-Program $Exe $Arguments $Environment
  [System.IO.File]::WriteAllText($log, $result.Output)
  if ($result.Code -ne 0) {
    Write-Host ''
    ($result.Output -split "`r?`n" | Select-Object -Last 25) | ForEach-Object { Write-Host "    | $_" }
    Write-Err "'$(Split-Path -Leaf $Exe) $($Arguments -join ' ')' failed. Full log: log/setup/$Name.log"
  }
  return $result.Code
}

# ---- ruby -----------------------------------------------------------------

function Get-RequiredRuby {
  $raw = (Get-Content (Join-Path $script:AppRoot '.ruby-version') -Raw).Trim()
  return ($raw -replace '^ruby-', '')
}

function Test-RubyAtLeast([string]$Version, [string]$Minimum) {
  $clean = ($Version -replace '[^0-9.].*$', '')
  try { return ([version]$clean -ge [version]$Minimum) } catch { return $false }
}

function Get-RubyVersion([string]$Exe) {
  if (-not $Exe -or -not (Test-Path $Exe)) { return $null }
  try {
    $r = Invoke-Program $Exe @('-e', 'print RUBY_VERSION')
    if ($r.Code -eq 0) { return $r.Output.Trim() }
  } catch {
    return $null  # not a program we can run
  }
  return $null
}

function Save-RubyChoice([string]$Exe) {
  New-Item -ItemType Directory -Force (Split-Path -Parent $script:RubyChoiceFile) | Out-Null
  Set-Content -Path $script:RubyChoiceFile -Value $Exe
}

# The ruby.exe setup chose last time, if it still works.
function Get-SavedRuby {
  if (-not (Test-Path $script:RubyChoiceFile)) { return $null }
  $exe = (Get-Content $script:RubyChoiceFile -Raw).Trim()
  if (Get-RubyVersion $exe) { return $exe }
  return $null
}

# ---- ports ----------------------------------------------------------------

# Parses `netstat -ano` output. Matches on the foreign address rather than the
# State column, because Windows translates LISTENING into the display language.
function Get-ListenerPidsFromNetstat([string]$Text, [int]$Port) {
  $found = @()
  foreach ($line in ($Text -split "`r?`n")) {
    if ($line -match '^\s*TCP\s+\S+:(\d+)\s+(0\.0\.0\.0:0|\[::\]:0)\s+\S+\s+(\d+)\s*$') {
      if ([int]$Matches[1] -eq $Port -and $found -notcontains [int]$Matches[3]) { $found += [int]$Matches[3] }
    }
  }
  return $found
}

# Process ids listening on a TCP port. Empty when none are visible.
function Get-ListenerPids([int]$Port) {
  if (Test-IsWindows) {
    if (Get-Command Get-NetTCPConnection -ErrorAction SilentlyContinue) {
      $conns = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
      return @($conns | ForEach-Object { [int]$_.OwningProcess } | Sort-Object -Unique)
    }
    $netstat = (& netstat.exe -ano -p TCP) -join "`n"
    $netstat6 = (& netstat.exe -ano -p TCPv6) -join "`n"
    return @(Get-ListenerPidsFromNetstat ($netstat + "`n" + $netstat6) $Port | Sort-Object -Unique)
  }
  if (Get-Command lsof -ErrorAction SilentlyContinue) {
    $r = Invoke-Program 'lsof' @('-nP', "-iTCP:$Port", '-sTCP:LISTEN', '-t')
    return @($r.Output -split "`r?`n" | Where-Object { $_ -match '^\d+$' } | ForEach-Object { [int]$_ } | Sort-Object -Unique)
  }
  return @()
}

# True if nothing stops us listening on 127.0.0.1:PORT. Catches ports Windows
# reserves for Hyper-V, WSL or Docker, where nothing is listening but binding
# still fails.
function Test-PortBindable([int]$Port) {
  $listener = $null
  try {
    $listener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, $Port)
    if (Test-IsWindows) { $listener.ExclusiveAddressUse = $true }
    $listener.Start()
    return $true
  } catch {
    return $false
  } finally {
    if ($listener) { try { $listener.Stop() } catch { $listener = $null } }
  }
}

# True if something accepts connections on 127.0.0.1:PORT. On Windows a second
# program can bind a specific address under someone else's wildcard listener,
# so binding alone is not proof the port is free.
function Test-PortAnswers([int]$Port) {
  $client = New-Object System.Net.Sockets.TcpClient
  try {
    $task = $client.ConnectAsync('127.0.0.1', $Port)
    if ($task.Wait(300)) { return $client.Connected }
    return $false
  } catch {
    return $false
  } finally {
    $client.Close()
  }
}

function Test-PortInUse([int]$Port) {
  if (@(Get-ListenerPids $Port).Count -gt 0) { return $true }
  if (Test-PortAnswers $Port) { return $true }
  return (-not (Test-PortBindable $Port))
}
