#Requires -Version 5.1
[CmdletBinding()]
param(
    [PSCredential] $Credencial,
    [switch] $CouchDbLocal,
    [switch] $ConservarBases
)

$ErrorActionPreference = 'Stop'
if (!$Credencial) {
    $Credencial = Get-Credential -Message 'Administrador de CouchDB del laboratorio local'
}
if (!$Credencial) { throw 'No se proporciono una credencial.' }

$origenHost = 'http://127.0.0.1:15984'
$replicaHost = 'http://127.0.0.1:25984'
$origenInterno = 'http://origen:5984'
$replicaInterna = 'http://replica:5984'
if ($CouchDbLocal) {
    $origenHost = $replicaHost = $origenInterno = $replicaInterna = 'http://127.0.0.1:5984'
}

$auth = @{
    username = $Credencial.UserName
    password = $Credencial.GetNetworkCredential().Password
}
$basic = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(
    ('{0}:{1}' -f $auth.username, $auth.password)
))
$headers = @{ Authorization = "Basic $basic" }

function Invoke-Couch {
    param([string] $Method, [string] $Uri, [int[]] $Expected, [hashtable] $Body)

    $options = @{
        Uri = $Uri
        Method = $Method
        Headers = $headers
        TimeoutSec = 30
        MaximumRedirection = 0
        UseBasicParsing = $true
        ErrorAction = 'Stop'
    }
    if ($null -ne $Body) {
        $options.ContentType = 'application/json'
        $options.Body = [Text.Encoding]::UTF8.GetBytes(
            ($Body | ConvertTo-Json -Depth 8 -Compress)
        )
    }

    $response = $null
    try {
        $response = Invoke-WebRequest @options
        $status = [int] $response.StatusCode
    } catch {
        if (!$_.Exception.Response) {
            throw "No se pudo conectar con CouchDB para $Method; detalles omitidos."
        }
        $status = [int] $_.Exception.Response.StatusCode
    }
    if ($status -notin $Expected) {
        throw "CouchDB devolvio HTTP $status para $Method; se esperaba $($Expected -join '/')."
    }
    if ($response -and $response.Content) {
        try { $response.Content | ConvertFrom-Json }
        catch { throw "CouchDB devolvio JSON invalido para $Method." }
    }
}

function Assert-Replica {
    param($Document, [string] $Revision, [int] $Version)
    if ($Document._id -cne 'demo' -or $Document._rev -cne $Revision -or
        $Document.version -ne $Version -or $Document.tipo -cne 'ficticio') {
        throw "La replica no coincide con la revision o el contenido de la version $Version."
    }
}

$id = [Guid]::NewGuid().ToString('N')
$origen = "credito_repl_demo_${id}_origen"
$replica = "credito_repl_demo_${id}_replica"
$created = @()
$passed = $false
try {
    foreach ($hostUrl in @($origenHost, $replicaHost) | Select-Object -Unique) {
        $session = Invoke-Couch GET "$hostUrl/_session" @(200)
        if ($session.userCtx.roles -notcontains '_admin') {
            throw 'La cuenta debe tener permiso de administrador en el laboratorio.'
        }
    }
    if (!$CouchDbLocal) {
        $origenInfo = Invoke-Couch GET "$origenHost/" @(200)
        $replicaInfo = Invoke-Couch GET "$replicaHost/" @(200)
        if (!$origenInfo.uuid -or !$replicaInfo.uuid -or $origenInfo.uuid -eq $replicaInfo.uuid) {
            throw 'El origen y la replica deben ser dos instancias CouchDB distintas.'
        }
        Write-Host 'OK: origen y replica son dos instancias distintas.'
    }

    Invoke-Couch PUT "$origenHost/$origen" @(201) | Out-Null
    $created += "$origenHost/$origen"
    Invoke-Couch PUT "$replicaHost/$replica" @(201) | Out-Null
    $created += "$replicaHost/$replica"
    $job = @{
        source = @{ url = "$origenInterno/$origen"; auth = @{ basic = $auth } }
        target = @{ url = "$replicaInterna/$replica"; auth = @{ basic = $auth } }
        create_target = $false
    }

    $first = Invoke-Couch PUT "$origenHost/$origen/demo" @(201) @{
        tipo = 'ficticio'; version = 1
    }
    Invoke-Couch GET "$replicaHost/$replica/demo" @(404) | Out-Null
    $result = Invoke-Couch POST "$origenHost/_replicate" @(200) $job
    if (!$result.ok) { throw 'CouchDB no confirmo la copia inicial.' }
    $copied = Invoke-Couch GET "$replicaHost/$replica/demo" @(200)
    Assert-Replica $copied $first.rev 1
    Write-Host 'OK: copia inicial (404 antes, 200 despues; revision identica).'

    $second = Invoke-Couch PUT "$origenHost/$origen/demo" @(201) @{
        _rev = $first.rev; tipo = 'ficticio'; version = 2
    }
    if ($second.rev -ceq $first.rev) { throw 'No se genero una revision nueva.' }
    $old = Invoke-Couch GET "$replicaHost/$replica/demo" @(200)
    Assert-Replica $old $first.rev 1
    $result = Invoke-Couch POST "$origenHost/_replicate" @(200) $job
    if (!$result.ok) { throw 'CouchDB no confirmo la segunda copia.' }
    $updated = Invoke-Couch GET "$replicaHost/$replica/demo" @(200)
    Assert-Replica $updated $second.rev 2
    Write-Host 'OK: replicacion incremental (version 2 y nueva revision en la replica).'
    $passed = $true
} finally {
    $remaining = @()
    foreach ($databaseUrl in $created) {
        if ($ConservarBases -and $passed) {
            $remaining += $databaseUrl
            continue
        }
        try { Invoke-Couch DELETE $databaseUrl @(200, 202) | Out-Null }
        catch { $remaining += $databaseUrl }
    }
    if ($remaining.Count -gt 0) {
        foreach ($databaseUrl in $remaining) { Write-Host "Base de prueba: $databaseUrl" }
        if (!$ConservarBases -or !$passed) {
            throw 'No se pudo limpiar alguna base creada por la prueba.'
        }
    } elseif ($created.Count -gt 0) {
        Write-Host "Limpieza: $($created.Count) base(s) de esta prueba eliminada(s)."
    }
}
