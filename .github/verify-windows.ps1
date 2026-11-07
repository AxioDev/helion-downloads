$ErrorActionPreference = 'Stop'
$base = 'https://github.com/AxioDev/helion-downloads/releases/latest/download'
$root = "$env:LOCALAPPDATA/HELION.Game"
$manifest = "$root/current/sq.version"
$game = "$root/current/HELION-Online.exe"
$previousJournal = "$env:LOCALAPPDATA/HELION/demarrage.txt"
$setup = "$env:RUNNER_TEMP/HELION-Setup.exe"
function InstalledVersion {
    ([xml](Get-Content $manifest -Raw)).package.metadata.version
}
function WaitUntil([scriptblock]$condition, [string]$description) {
    $limit = (Get-Date).AddSeconds(90)
    do {
        if (& $condition) { return }
        Start-Sleep -Milliseconds 500
    } while ((Get-Date) -lt $limit)
    throw "Délai dépassé pour $description"
}

$feed = Invoke-RestMethod "$base/updates-win.json"
$asset = ($feed.manifest | ConvertFrom-Json).Assets[0]
$expected = $asset.Version
if ($expected -notmatch '^\d+\.\d+\.\d+$' -or $asset.FileName -cne "HELION.Game-$expected-full.nupkg") {
    throw 'Métadonnées inattendues'
}
$cached = Join-Path "$root/packages" $asset.FileName
New-Item (Split-Path $previousJournal) -ItemType Directory -Force | Out-Null
Set-Content $previousJournal 'Journal du client portable'
Invoke-WebRequest "$base/HELION-Setup.exe" -OutFile $setup
$install = Start-Process $setup '--silent' -PassThru
if (-not $install.WaitForExit(90000) -or $install.ExitCode -ne 0) { throw "Échec de l’installation" }
if ((InstalledVersion) -ne $expected) { throw 'Version installée incorrecte' }
if ((Get-Content $previousJournal) -ne 'Journal du client portable') { throw 'Ancien journal écrasé' }
$shortcut = Join-Path ([Environment]::GetFolderPath('Programs')) 'HELION.lnk'
if (-not (Test-Path $shortcut)) { throw 'Raccourci absent' }
$sha = (Get-FileHash $game).Hash
if ((Get-FileHash $cached).Hash -ne $asset.SHA256) { throw 'Paquet intégré incorrect' }
Write-Output "Installation publique $expected, raccourci du menu Démarrer, paquet SHA-256 et migration depuis le ZIP vérifiés."

# Installer aussi la précédente version publique dans un dossier indépendant.
$releases = Invoke-RestMethod 'https://api.github.com/repos/AxioDev/helion-downloads/releases?per_page=100'
$previous = $releases | Where-Object {
    -not $_.prerelease -and -not $_.draft -and $_.tag_name -match '^v[0-9]+\.[0-9]+\.[0-9]+$' -and
    ([version]$_.tag_name.Substring(1)) -lt ([version]$expected)
} | Sort-Object { [version]$_.tag_name.Substring(1) } -Descending | Select-Object -First 1
if (-not $previous) { throw 'Version publique précédente introuvable' }
$oldVersion = $previous.tag_name.Substring(1)
$oldSetup = "$env:RUNNER_TEMP/HELION-Previous-Setup.exe"
Invoke-WebRequest "https://github.com/AxioDev/helion-downloads/releases/download/v$oldVersion/HELION-Setup.exe" -OutFile $oldSetup
$root = "$env:RUNNER_TEMP/HELION-previous"
$manifest = "$root/current/sq.version"
$game = "$root/current/HELION-Online.exe"
$cached = Join-Path "$root/packages" $asset.FileName
$prior = Start-Process $oldSetup "--silent --installto `"$root`"" -PassThru
if (-not $prior.WaitForExit(90000) -or $prior.ExitCode -ne 0 -or (InstalledVersion) -ne $oldVersion) { throw 'Installation précédente incorrecte' }
if (Test-Path $cached) { throw 'Le paquet à télécharger est déjà présent' }
$marker = "$root/current/ancienne-installation-test.txt"
Set-Content $marker 'Témoin du remplacement de la version installée'
$running = Start-Process $game '--online --auto-exit 150' -PassThru
WaitUntil { Test-Path $cached } 'le téléchargement réel du paquet'
if ($running.HasExited -or (InstalledVersion) -ne $oldVersion) { throw 'La session précédente a été interrompue' }
if ((Get-FileHash $cached).Hash -ne $asset.SHA256) { throw 'Paquet téléchargé incorrect' }
$running.Kill()
$running.WaitForExit()
Start-Process $game '--version'
WaitUntil { (Test-Path $manifest) -and (InstalledVersion) -eq $expected -and -not (Test-Path $marker) } 'le remplacement au prochain lancement'
if ((Get-FileHash $game).Hash -ne $sha) { throw 'Binaire final incorrect' }
Write-Output "Mise à jour $oldVersion → $expected téléchargée pendant la session et appliquée à la réouverture. Binaire SHA-256 $sha."
