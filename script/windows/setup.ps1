# One-shot setup for Kiln Queue on Windows. Run it through setup.cmd in the app
# folder, which gets past PowerShell's script execution policy:
#
#   .\setup.cmd            ask before anything big (installing Ruby, admin rights)
#   .\setup.cmd --yes      take the recommended answer everywhere
#   .\setup.cmd --help     all options
#
# Installs what is missing and skips what is already done, so it is safe to run
# again at any time. The same steps and options as ./setup on macOS and Linux:
#
#   1. basics      Windows and PowerShell versions, winget, network
#   2. Ruby        Ruby 3.3 with the RubyInstaller DevKit (via winget, or
#                  straight from RubyInstaller's GitHub releases), or any Ruby
#                  3.2+ already on the machine
#   3. DevKit      the MSYS2 compiler some gems need (ridk install)
#   4. Bundler     the version Gemfile.lock was made with
#   5. gems        bundle install
#   6. database    create, migrate and seed development; prepare test
#   7. sample      import last Saturday's class (once)
#   8. tests       run the spec suite
#   9. editor      VS Code Live Share extension, if VS Code is installed

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')
Set-Location $script:AppRoot

$SkipTests = $false
$NoSample = $false
$NoEditor = $false
$ResetDb = $false
$MinRuby = '3.2'
$RequiredRuby = Get-RequiredRuby
$RubySeries = ($RequiredRuby -split '\.')[0..1] -join '.'
$script:Summary = @()
$script:Step = 'starting'

function Show-Usage {
  @'
Usage: .\setup.cmd [options]

  -y, --yes          Take the recommended answer to every question
      --skip-tests   Do not run the spec suite at the end
      --no-sample    Do not import the sample Saturday class
      --no-editor    Do not check VS Code or the Live Share extension
      --reset-db     Drop and rebuild the development database from seeds
  -h, --help         Show this help

Safe to run as many times as you like. Logs go to log\setup\.
'@ | Write-Host
}

foreach ($a in $args) {
  switch -Regex ([string]$a) {
    '^(-y|--yes)$' { $script:AssumeYes = $true }
    '^--skip-tests$' { $SkipTests = $true }
    '^--no-sample$' { $NoSample = $true }
    '^--no-editor$' { $NoEditor = $true }
    '^--reset-db$' { $ResetDb = $true }
    '^(-h|--help|/\?)$' { Show-Usage; exit 0 }
    default { Write-Err "Unknown option: $a"; Show-Usage; exit 2 }
  }
}

function Add-Summary([string]$Text) { $script:Summary += $Text }

function Fail([string]$Text) {
  Write-Err $Text
  Write-Info "Setup stopped while: $script:Step."
  Write-Info 'Fix what the output above points at, then run .\setup.cmd again. It skips everything already done.'
  exit 1
}

# ---- 1. basics ------------------------------------------------------------

function Invoke-Basics {
  $script:Step = 'checking the basics'
  Write-Step '1/9 Basics'
  if (Test-IsWindows) {
    $os = [Environment]::OSVersion.Version
    Write-Ok "Windows $($os.Major).$($os.Minor) build $($os.Build), PowerShell $($PSVersionTable.PSVersion)"
    if (-not [Environment]::Is64BitOperatingSystem) { Fail 'This needs 64-bit Windows.' }
    # Windows PowerShell 5.1 still defaults to old TLS versions that GitHub refuses.
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    if (Get-Command winget -ErrorAction SilentlyContinue) { Write-Ok 'winget' }
    else { Write-Info 'winget not found. Ruby, if needed, will be downloaded from RubyInstaller directly.' }
  } else {
    Write-Warn 'This is the Windows setup. On macOS and Linux, ./setup does more (it can install Ruby).'
    Write-Info 'Carrying on with the Ruby already on your PATH.'
  }
}

# ---- 2. Ruby --------------------------------------------------------------

function Update-SessionPath {
  if (-not (Test-IsWindows)) { return }
  $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
  $user = [Environment]::GetEnvironmentVariable('Path', 'User')
  $env:Path = "$machine;$user"
}

# Every ruby.exe new enough, best first: the series .ruby-version asks for,
# then newest.
function Find-Rubies {
  $candidates = @()
  foreach ($cmd in @(Get-Command ruby -All -ErrorAction SilentlyContinue)) {
    if ($cmd.CommandType -eq 'Application') { $candidates += $cmd.Source }
  }
  if (Test-IsWindows) {
    $roots = @('C:\', $env:SystemDrive + '\', (Join-Path $env:LOCALAPPDATA 'Programs'), $env:ProgramFiles)
    foreach ($root in $roots) {
      if ($root -and (Test-Path $root)) {
        Get-ChildItem -Path $root -Directory -Filter 'Ruby3*' -ErrorAction SilentlyContinue | ForEach-Object {
          $exe = Join-Path $_.FullName 'bin\ruby.exe'
          if (Test-Path $exe) { $candidates += $exe }
        }
      }
    }
    $scoop = Join-Path $env:USERPROFILE 'scoop\apps\ruby\current\bin\ruby.exe'
    if (Test-Path $scoop) { $candidates += $scoop }
  }

  $found = @()
  foreach ($exe in ($candidates | Select-Object -Unique)) {
    $v = Get-RubyVersion $exe
    if ($v -and (Test-RubyAtLeast $v $MinRuby)) {
      $series = (($v -split '\.')[0..1] -join '.')
      $found += New-Object PSObject -Property @{ Exe = $exe; Version = $v; Preferred = ($series -eq $RubySeries) }
    }
  }
  return @($found | Sort-Object -Property @{ Expression = 'Preferred'; Descending = $true }, @{ Expression = { [version](($_.Version -replace '[^0-9.].*$', '')) }; Descending = $true })
}

function Install-RubyWithWinget {
  if (-not (Get-Command winget -ErrorAction SilentlyContinue)) { return $false }
  $id = "RubyInstallerTeam.RubyWithDevKit.$RubySeries"
  Write-Info "Installing $id with winget (a few minutes; Windows may ask for permission)..."
  $old = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  & winget install --id $id --exact --silent --accept-package-agreements --accept-source-agreements | Out-Host
  $code = $LASTEXITCODE
  $ErrorActionPreference = $old
  if ($code -ne 0) { Write-Warn "winget finished with code $code."; return $false }
  Add-Summary "installed Ruby $RubySeries with DevKit (winget)"
  return $true
}

function Install-RubyFromGitHub {
  Write-Info "Looking up the latest RubyInstaller $RubySeries release on GitHub..."
  try {
    $releases = Invoke-RestMethod -Uri 'https://api.github.com/repos/oneclick/rubyinstaller2/releases?per_page=40' -Headers @{ 'User-Agent' = 'kiln-queue-setup' }
  } catch {
    Write-Warn "Could not reach GitHub: $($_.Exception.Message)"
    return $false
  }
  $pattern = '^rubyinstaller-devkit-' + [regex]::Escape($RubySeries) + '\.\d+-\d+-x64\.exe$'
  $asset = $null
  foreach ($r in $releases) {
    if ($r.prerelease) { continue }
    $asset = $r.assets | Where-Object { $_.name -match $pattern } | Select-Object -First 1
    if ($asset) { break }
  }
  if (-not $asset) { Write-Warn "No RubyInstaller $RubySeries download found."; return $false }

  $file = Join-Path $env:TEMP $asset.name
  Write-Info "Downloading $($asset.name) ($([math]::Round($asset.size / 1MB)) MB)..."
  try {
    $ProgressPreference = 'SilentlyContinue'
    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $file -UseBasicParsing
  } catch {
    Write-Warn "Download failed: $($_.Exception.Message)"
    return $false
  }
  Write-Info 'Installing (Windows may ask for permission)...'
  $p = Start-Process -FilePath $file -ArgumentList @('/verysilent', '/norestart', '/tasks=assocfiles,modpath') -Wait -PassThru
  if ($p.ExitCode -ne 0) { Write-Warn "The installer finished with code $($p.ExitCode)."; return $false }
  Add-Summary "installed $($asset.name -replace '\.exe$', '')"
  return $true
}

function Invoke-Ruby {
  $script:Step = 'setting up Ruby'
  Write-Step "2/9 Ruby $RubySeries"

  $saved = Get-SavedRuby
  if ($saved) {
    Write-Ok "Ruby $(Get-RubyVersion $saved) already installed ($saved, chosen on an earlier run)"
    $script:Ruby = $saved
    return
  }

  $rubies = @(Find-Rubies)
  if ($rubies.Count -eq 0 -and (Test-IsWindows)) {
    Write-Info "No Ruby $MinRuby or newer found. This app wants $RubySeries (it has $RequiredRuby in .ruby-version; any $RubySeries.x is fine)."
    if (-not (Confirm-Step "Install Ruby $RubySeries with the RubyInstaller DevKit (about 150 MB)?" $true)) {
      Fail 'Install Ruby 3.2 or newer from https://rubyinstaller.org/downloads/ (the WITH DEVKIT one), then run .\setup.cmd again.'
    }
    $ok = Install-RubyWithWinget
    if (-not $ok) { $ok = Install-RubyFromGitHub }
    Update-SessionPath
    $rubies = @(Find-Rubies)
    if ($rubies.Count -eq 0) {
      Write-Warn 'Ruby still is not showing up.'
      Write-Info 'Two ways forward:'
      Write-Info '  1. Install "Ruby+Devkit 3.3.x (x64)" from https://rubyinstaller.org/downloads/ by hand, then run .\setup.cmd again.'
      Write-Info '  2. Use WSL instead: run  wsl --install  in an admin terminal, restart, then run ./setup inside Ubuntu.'
      Fail 'No Ruby.'
    }
  }
  if ($rubies.Count -eq 0) { Fail "No Ruby $MinRuby or newer on your PATH. Use ./setup on macOS and Linux." }

  $pick = $rubies[0]
  if ($rubies.Count -gt 1) {
    Write-Info 'Rubies found:'
    for ($n = 0; $n -lt $rubies.Count; $n++) { Write-Info "  $($n + 1)) Ruby $($rubies[$n].Version)  $($rubies[$n].Exe)" }
    if ((Test-Interactive) -and -not $script:AssumeYes) {
      $answer = Read-Answer "Which one? [1]"
      $idx = 0
      if ($answer -and [int]::TryParse($answer, [ref]$idx) -and $idx -ge 1 -and $idx -le $rubies.Count) { $pick = $rubies[$idx - 1] }
    }
  }
  $script:Ruby = $pick.Exe
  if ($rubies.Count -eq 1 -and -not ($script:Summary -match 'installed Ruby|installed rubyinstaller')) {
    Write-Ok "Ruby $($pick.Version) already installed ($($pick.Exe))"
  } else {
    Write-Ok "Using Ruby $($pick.Version) ($($pick.Exe))"
  }
  if (-not $pick.Preferred) {
    Write-Info "The app was built on $RubySeries, but $($pick.Version) is new enough."
  }
  Save-RubyChoice $script:Ruby
}

# ---- 3. DevKit ------------------------------------------------------------

function Invoke-DevKit {
  $script:Step = 'checking the DevKit'
  Write-Step '3/9 DevKit (compiler for gems with C extensions)'
  if (-not (Test-IsWindows)) { Write-Info 'Not needed outside Windows.'; return }

  $ridk = Join-Path (Split-Path -Parent $script:Ruby) 'ridk.cmd'
  if (-not (Test-Path $ridk)) {
    Write-Warn 'This Ruby has no ridk (it is not a RubyInstaller DevKit build). Gems like puma and bootsnap may fail to build.'
    return
  }
  $check = Invoke-Program $env:ComSpec @('/d', '/c', $ridk, 'exec', 'gcc', '--version')
  if ($check.Code -eq 0) { Write-Ok 'MSYS2 and the MINGW toolchain already installed'; return }

  Write-Info 'The MSYS2 compiler toolchain is missing. It downloads a few hundred MB.'
  if (-not (Confirm-Step 'Install it now (ridk install 3)?' $true)) {
    Write-Warn 'Skipped. bundle install will fail on gems that need compiling.'
    return
  }
  $old = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  & $ridk install 3 | Out-Host
  $ErrorActionPreference = $old
  $check = Invoke-Program $env:ComSpec @('/d', '/c', $ridk, 'exec', 'gcc', '--version')
  if ($check.Code -ne 0) { Fail 'The toolchain still is not working. Run  ridk install  by hand and pick option 3.' }
  Write-Ok 'MSYS2 toolchain installed'
  Add-Summary 'installed the MSYS2 toolchain (ridk install 3)'
}

# ---- 4. Bundler -----------------------------------------------------------

function Invoke-Bundler {
  $script:Step = 'installing Bundler'
  Write-Step '4/9 Bundler'
  $lock = Get-Content (Join-Path $script:AppRoot 'Gemfile.lock')
  $locked = $null
  for ($n = 0; $n -lt $lock.Count - 1; $n++) {
    if ($lock[$n] -eq 'BUNDLED WITH') { $locked = $lock[$n + 1].Trim() }
  }
  if (-not $locked) { Write-Ok 'Gemfile.lock does not pin a Bundler version'; return }
  if ((Invoke-Program $script:Ruby @('-S', 'gem', 'list', 'bundler', '-i', '-v', $locked)).Code -eq 0) {
    Write-Ok "Bundler $locked already installed"
    return
  }
  if ((Invoke-Logged 'bundler' $script:Ruby @('-S', 'gem', 'install', 'bundler', '-v', $locked, '--no-document')) -eq 0) {
    Write-Ok "Bundler $locked installed"
    Add-Summary "installed Bundler $locked"
  } else {
    Write-Warn "Could not install Bundler $locked. Carrying on: RubyGems switches to the locked version by itself when it can."
  }
}

# ---- 5. gems --------------------------------------------------------------

function Invoke-Gems {
  $script:Step = 'installing gems'
  Write-Step '5/9 Gems'
  if ((Invoke-Program $script:Ruby @('-S', 'bundle', 'check')).Code -eq 0) {
    Write-Ok 'All gems already installed'
    return
  }
  Write-Info 'Running bundle install (a few minutes the first time; Windows compiles some gems)...'
  if ((Invoke-Logged 'bundle-install' $script:Ruby @('-S', 'bundle', 'install', '--jobs', '4', '--retry', '3')) -eq 0) {
    Write-Ok 'Gems installed'
    Add-Summary 'installed gems'
    return
  }
  Write-Warn 'bundle install failed. On Windows that is nearly always the DevKit toolchain or antivirus locking files.'
  if (Confirm-Step 'Try bundle install once more?' $true) {
    $script:Step = 'installing gems (second try)'
    if ((Invoke-Logged 'bundle-install-retry' $script:Ruby @('-S', 'bundle', 'install', '--jobs', '1', '--retry', '3')) -eq 0) {
      Write-Ok 'Gems installed'
      Add-Summary 'installed gems (second try)'
      return
    }
  }
  Fail 'See log\setup\bundle-install.log.'
}

# ---- 6. database ----------------------------------------------------------

function Invoke-Rails([string]$Name, [string[]]$RailsArgs, [hashtable]$Environment = @{}) {
  return (Invoke-Logged $Name $script:Ruby (@('bin/rails') + $RailsArgs) $Environment)
}

function Invoke-Database {
  $script:Step = 'preparing the databases'
  Write-Step '6/9 Database'
  if ($ResetDb -and (Confirm-Step 'Drop the development database and rebuild it from seeds?' $false)) {
    if ((Invoke-Rails 'db-reset' @('db:reset')) -ne 0) { Fail 'db:reset failed.' }
    Write-Ok 'Development database rebuilt'
    Add-Summary 'rebuilt the development database'
  }
  if ((Invoke-Rails 'db-prepare' @('db:prepare')) -ne 0) { Fail 'db:prepare failed.' }
  Write-Ok 'Development database created and migrated'

  if ((Invoke-Program $script:Ruby @('bin/rails', 'runner', 'exit(Kiln.exists? ? 0 : 1)')).Code -eq 0) {
    Write-Ok 'Demo data already there'
  } else {
    if ((Invoke-Rails 'db-seed' @('db:seed')) -ne 0) { Fail 'db:seed failed.' }
    Write-Ok 'Demo data seeded'
    Add-Summary 'seeded demo data'
  }

  if ((Invoke-Rails 'db-prepare-test' @('db:prepare') @{ RAILS_ENV = 'test' }) -ne 0) { Fail 'Preparing the test database failed.' }
  Write-Ok 'Test database ready'
}

# ---- 7. sample --------------------------------------------------------------

function Invoke-Sample {
  $script:Step = 'importing the sample class'
  Write-Step '7/9 Sample Saturday class'
  if ($NoSample) { Write-Info 'Skipped (--no-sample).'; return }
  # The importer is not idempotent (that is one of the practice questions), so
  # check before running it.
  if ((Invoke-Program $script:Ruby @('bin/rails', 'runner', 'exit(Piece.exists?(title: "Pinch pot") ? 0 : 1)')).Code -eq 0) {
    Write-Ok 'Sample class already imported'
    return
  }
  if (Confirm-Step 'Import db/sample/saturday_class.csv (four pieces and a new member)?' $true) {
    if ((Invoke-Rails 'sample-import' @('kiln:import[db/sample/saturday_class.csv]')) -ne 0) { Fail 'The import failed.' }
    $last = (Get-Content (Join-Path $script:AppRoot 'log/setup/sample-import.log') | Where-Object { $_ } | Select-Object -Last 1)
    Write-Ok $last
    Add-Summary 'imported the sample Saturday class'
  }
}

# ---- 8. tests -------------------------------------------------------------

function Invoke-Tests {
  $script:Step = 'running the specs'
  Write-Step '8/9 Tests'
  if ($SkipTests) { Write-Info 'Skipped (--skip-tests).'; return }
  if ((Invoke-Logged 'rspec' $script:Ruby @('-S', 'bundle', 'exec', 'rspec')) -eq 0) {
    $line = (Get-Content (Join-Path $script:AppRoot 'log/setup/rspec.log') | Where-Object { $_ -match '\d+ examples?' } | Select-Object -Last 1)
    Write-Ok $line
  } else {
    Write-Warn 'Some specs failed. On a fresh setup they should all pass, so this points at the environment.'
    Write-Warn 'Details: log\setup\rspec.log'
  }
}

# ---- 9. editor ------------------------------------------------------------

function Invoke-Editor {
  $script:Step = 'checking VS Code'
  Write-Step '9/9 VS Code and Live Share'
  if ($NoEditor) { Write-Info 'Skipped (--no-editor).'; return }
  $code = Get-Command code -ErrorAction SilentlyContinue
  if (-not $code -and (Test-IsWindows)) {
    $guess = Join-Path $env:LOCALAPPDATA 'Programs\Microsoft VS Code\bin\code.cmd'
    if (Test-Path $guess) { $code = Get-Command $guess }
  }
  if (-not $code) {
    Write-Info 'VS Code was not found. Install it from https://code.visualstudio.com, then add the Live Share extension.'
    return
  }
  $list = Invoke-Program $env:ComSpec @('/d', '/c', $code.Source, '--list-extensions')
  if (-not (Test-IsWindows)) { $list = Invoke-Program $code.Source @('--list-extensions') }
  if ($list.Output -match '(?im)^ms-vsliveshare\.vsliveshare\s*$') {
    Write-Ok 'Live Share extension already installed'
  } elseif (Confirm-Step 'Install the Live Share extension in VS Code?' $true) {
    if (Test-IsWindows) { $r = Invoke-Program $env:ComSpec @('/d', '/c', $code.Source, '--install-extension', 'ms-vsliveshare.vsliveshare') }
    else { $r = Invoke-Program $code.Source @('--install-extension', 'ms-vsliveshare.vsliveshare') }
    if ($r.Code -eq 0) { Write-Ok 'Live Share installed'; Add-Summary 'installed the Live Share extension' }
    else { Write-Warn 'Could not install it. Install "Live Share" from the Extensions view instead.' }
  }
}

# ---- go ---------------------------------------------------------------------

Write-Host "Kiln Queue setup for Windows (wants Ruby $RubySeries)" -ForegroundColor White

try {
  Invoke-Basics
  Invoke-Ruby
  Invoke-DevKit
  Invoke-Bundler
  Invoke-Gems
  Invoke-Database
  Invoke-Sample
  Invoke-Tests
  Invoke-Editor
} catch {
  Write-Host ''
  Write-Err $_.Exception.Message
  Fail 'Unexpected error.'
}

Write-Step 'Done'
if ($script:Summary.Count -gt 0) {
  Write-Info 'This run:'
  foreach ($s in $script:Summary) { Write-Info "  - $s" }
} else {
  Write-Info 'Everything was already in place. Nothing changed.'
}
Write-Host ''
Write-Info 'Start the app:   .\dev.cmd'
Write-Info 'Run the specs:   bundle exec rspec'
Write-Info 'If ruby or bundle is not found in an already-open terminal, open a new one.'
exit 0
