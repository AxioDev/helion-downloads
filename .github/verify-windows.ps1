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
if (-not $install.WaitForExit(90000) -or $install.ExitCode -ne 0) { throw 'Échec de l’installation' }
if ((InstalledVersion) -ne $expected) { throw 'Version installée incorrecte' }
if ((Get-Content $previousJournal) -ne 'Journal du client portable') { throw 'Ancien journal écrasé' }
$shortcut = Join-Path ([Environment]::GetFolderPath('Programs')) 'HELION.lnk'
if (-not (Test-Path $shortcut)) { throw 'Raccourci absent' }
$sha = (Get-FileHash $game).Hash
if ((Get-FileHash $cached).Hash -ne $asset.SHA256) { throw 'Paquet intégré incorrect' }
Write-Output "Installation publique $expected, raccourci du menu Démarrer, paquet SHA-256 et migration depuis le ZIP vérifiés."

# Fixture locale pour la première publication, qui n’a aucun installateur antérieur.
# Le binaire livré et sa source de mise à jour publique restent intacts.
$xml = [xml](Get-Content $manifest -Raw)
$xml.package.metadata.version = '0.0.1'
$xml.Save($manifest)
Remove-Item -LiteralPath $cached
$marker = "$root/current/ancienne-installation-test.txt"
Set-Content $marker 'Témoin du remplacement de la version installée'
$running = Start-Process $game '--online --auto-exit 150' -PassThru
WaitUntil { Test-Path $cached } 'le téléchargement réel du paquet'
if ($running.HasExited -or (InstalledVersion) -ne '0.0.1') { throw 'La session précédente a été interrompue' }
if ((Get-FileHash $cached).Hash -ne $asset.SHA256) { throw 'Paquet téléchargé incorrect' }
$running.Kill()
$running.WaitForExit()
Start-Process $game '--version'
WaitUntil { (Test-Path $manifest) -and (InstalledVersion) -eq $expected -and -not (Test-Path $marker) } 'le remplacement au prochain lancement'
if ((Get-FileHash $game).Hash -ne $sha) { throw 'Binaire final incorrect' }
Write-Output "Mise à jour 0.0.1 → $expected téléchargée pendant la session et appliquée à la réouverture. Binaire SHA-256 $sha."
