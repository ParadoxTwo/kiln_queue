# Tests for the Windows scripts: setup.cmd / dev.cmd and the PowerShell behind
# them in script/windows. Runs on Windows PowerShell 5.1, PowerShell 7 on
# Windows, and PowerShell 7 on Linux or macOS (where the port lookups use lsof
# instead of the Windows APIs):
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File script\test_windows_scripts.ps1
#   pwsh -NoProfile -File script/test_windows_scripts.ps1
#
# The scenario tests occupy ports with a throwaway TcpListener in a child
# PowerShell, then drive dev.ps1 with scripted answers on stdin. dev.ps1
# --dry-run prints the server command instead of starting Rails.

$ErrorActionPreference = 'Stop'
$AppRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $AppRoot
. (Join-Path $AppRoot 'script/windows/common.ps1')

$HostExe = (Get-Process -Id $PID).Path
$DevScript = Join-Path $AppRoot 'script/windows/dev.ps1'
$SetupScript = Join-Path $AppRoot 'script/windows/setup.ps1'
$script:Pass = 0
$script:Fail = 0
$script:Out = ''
$script:Status = 0
$script:Listeners = @()

function Check([string]$Name, [bool]$Condition) {
  if ($Condition) {
    $script:Pass++
    Write-Host "  ok   $Name" -ForegroundColor Green
  } else {
    $script:Fail++
    Write-Host "  FAIL $Name" -ForegroundColor Red
    ($script:Out -split "`n" | Select-Object -First 40) | ForEach-Object { Write-Host "       | $_" }
  }
}

function Contains([string]$Text) { return $script:Out.Contains($Text) }

function Invoke-Script([string]$Script, [string[]]$Arguments, [string]$Answers = '') {
  $env:KILN_FORCE_INTERACTIVE = '1'
  $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $Script) + $Arguments
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $HostExe
  $psi.Arguments = ConvertTo-ArgumentString $argList
  $psi.UseShellExecute = $false
  $psi.RedirectStandardInput = $true
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.WorkingDirectory = $AppRoot
  $p = [System.Diagnostics.Process]::Start($psi)
  $stdout = $p.StandardOutput.ReadToEndAsync()
  $stderr = $p.StandardError.ReadToEndAsync()
  if ($Answers) { $p.StandardInput.Write($Answers.Replace('|', "`n") + "`n") }
  $p.StandardInput.Close()
  $p.WaitForExit()
  $script:Out = $stdout.Result + $stderr.Result
  $script:Status = $p.ExitCode
  Remove-Item Env:KILN_FORCE_INTERACTIVE -ErrorAction SilentlyContinue
}

function Start-Occupier([int]$Port) {
  $code = "`$l = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, $Port); `$l.Start(); Start-Sleep 600"
  $startArgs = @{ FilePath = $HostExe; ArgumentList = @('-NoProfile', '-Command', $code); PassThru = $true }
  if (Test-IsWindows) { $startArgs.WindowStyle = 'Hidden' }
  $p = Start-Process @startArgs
  $script:Listeners += $p
  for ($i = 0; $i -lt 50; $i++) {
    if (-not (Test-PortBindable $Port)) { break }
    Start-Sleep -Milliseconds 200
  }
  return $p.Id
}

function Test-Alive([int]$ProcessId) { return [bool](Get-Process -Id $ProcessId -ErrorAction SilentlyContinue) }

try {
  Write-Host 'common.ps1'

  $quoted = ConvertTo-ArgumentString @('plain', 'two words', 'say "hi"', '', 'C:\dir with space\')
  Check 'arguments are quoted the way Windows programs parse them' ($quoted -eq 'plain "two words" "say \"hi\"" "" "C:\dir with space\\"')

  $netstat = @'

Active Connections

  Proto  Local Address          Foreign Address        State           PID
  TCP    0.0.0.0:135            0.0.0.0:0              LISTENING       1044
  TCP    0.0.0.0:3000           0.0.0.0:0              LISTENING       7312
  TCP    127.0.0.1:30000        0.0.0.0:0              LISTENING       9001
  TCP    192.168.1.5:51234      52.1.2.3:3000          ESTABLISHED     5555
  TCP    [::]:3000              [::]:0                 ABHOEREN        7312
  TCP    [::1]:3001             [::]:0                 ESCUCHANDO      8120
  UDP    0.0.0.0:3000           *:*                                    4444
'@
  $pids = @(Get-ListenerPidsFromNetstat $netstat 3000)
  Check 'netstat: finds the listener on the port' ($pids -contains 7312)
  Check 'netstat: lists it once across IPv4 and IPv6' ($pids.Count -eq 1)
  Check 'netstat: ignores longer ports, outgoing connections and UDP' (-not ($pids -contains 9001 -or $pids -contains 5555 -or $pids -contains 4444))
  Check 'netstat: works whatever language the state column is in' (@(Get-ListenerPidsFromNetstat $netstat 3001) -contains 8120)

  Check 'versions: 3.3.6 is new enough' (Test-RubyAtLeast '3.3.6' '3.2')
  Check 'versions: 3.1.4 is not' (-not (Test-RubyAtLeast '3.1.4' '3.2'))

  Write-Host 'dev.ps1'

  Invoke-Script $DevScript @('--help')
  Check '--help exits 0 and explains the port option' ($script:Status -eq 0 -and (Contains '--port'))

  Invoke-Script $DevScript @('--dry-run', '--port', '3561')
  Check 'a free port starts straight away' (Contains 'bin/rails server -p 3561')

  $p = Start-Occupier 3562
  Invoke-Script $DevScript @('--dry-run', '--port', '3562') 'q'
  Check 'a busy port shows the pid' (Contains "$p")
  Check 'a busy port names the process using it' ((Contains 'pwsh') -or (Contains 'powershell'))
  Check 'quitting exits non-zero' ($script:Status -ne 0)
  Check 'quitting leaves the process alone' (Test-Alive $p)
  Check 'quitting does not start a server' (-not (Contains 'bin/rails server'))

  Invoke-Script $DevScript @('--dry-run', '--port', '3562') 'n'
  Check 'moving on picks the next free port' (Contains 'bin/rails server -p 3563')

  $p2 = Start-Occupier 3564
  Invoke-Script $DevScript @('--dry-run', '--port', '3562') 'c|3564|c|3566'
  Check 'a chosen port is checked again, and named when busy' (Contains "$p2")
  Check 'then the next choice is used' (Contains 'bin/rails server -p 3566')

  Invoke-Script $DevScript @('--dry-run', '--port', '3562') 'c|abc|3567'
  Check 'a port that is not a number is refused and asked again' (Contains 'bin/rails server -p 3567')

  Invoke-Script $DevScript @('--dry-run', '--port', '3562') 'k|y'
  Start-Sleep -Milliseconds 500
  Check 'stopping frees the port and starts on it' (Contains 'bin/rails server -p 3562')
  Check 'stopping really ended the process' (-not (Test-Alive $p))

  $null = Start-Occupier 3568
  $null = Start-Occupier 3569
  Invoke-Script $DevScript @('--dry-run', '--auto', '--port', '3568')
  Check '--auto skips busy ports without asking' (Contains 'bin/rails server -p 3570')

  $env:KILN_FORCE_NONINTERACTIVE = '1'
  Invoke-Script $DevScript @('--dry-run', '--port', '3568')
  Remove-Item Env:KILN_FORCE_NONINTERACTIVE
  Check 'without a terminal and without --auto it stops and explains' ($script:Status -ne 0 -and (Contains '--auto'))

  New-Item -ItemType Directory -Force (Join-Path $AppRoot 'tmp/pids') | Out-Null
  Set-Content -Path (Join-Path $AppRoot 'tmp/pids/server.pid') -Value '999999'
  Invoke-Script $DevScript @('--dry-run', '--port', '3571')
  Check 'a stale server.pid is cleared' (-not (Test-Path (Join-Path $AppRoot 'tmp/pids/server.pid')))
  Check 'and the server starts' (Contains 'bin/rails server -p 3571')

  Write-Host 'setup.ps1'

  Invoke-Script $SetupScript @('--help')
  Check '--help exits 0' ($script:Status -eq 0)

  Remove-Item (Join-Path $AppRoot 'tmp/.kiln-ruby-exe') -ErrorAction SilentlyContinue
  Invoke-Script $SetupScript @('--yes', '--no-editor')
  Check 'a full run succeeds' ($script:Status -eq 0)
  Check 'a full run finishes with the specs passing' (Contains ' 0 failures')
  Invoke-Script $SetupScript @('--yes', '--no-editor', '--skip-tests')
  Check 'a second run succeeds' ($script:Status -eq 0)
  Check 'a second run skips the Ruby install' (Contains 'already installed')
  Check 'a second run does not import the sample twice' (Contains 'already imported')
}
finally {
  foreach ($l in $script:Listeners) { Stop-Process -Id $l.Id -Force -ErrorAction SilentlyContinue }
}

Write-Host ''
Write-Host "$($script:Pass) passed, $($script:Fail) failed"
if ($script:Fail -gt 0) { exit 1 }
