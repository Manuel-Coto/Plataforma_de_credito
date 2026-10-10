
# ==========================================
# CONFIGURACION DE APACHE COUCHDB
# ==========================================

$url = "http://127.0.0.1:5984"

# Solicitar credenciales
$credenciales = Get-Credential -Message "Credenciales de CouchDB"

# Crear encabezado de autenticacion Basic
$usuario = $credenciales.UserName
$clave = $credenciales.GetNetworkCredential().Password

$texto = "${usuario}:${clave}"
$bytes = [System.Text.Encoding]::UTF8.GetBytes($texto)
$token = [Convert]::ToBase64String($bytes)

$headers = @{
    Authorization = "Basic $token"
}

# ==========================================
# BASES DE DATOS
# ==========================================

$bases = @(
    "usuarios",
    "empresas",
    "facturas",
    "ofertas",
    "operaciones",
    "auditoria"
)

# ==========================================
# CREACION DE BASES DE DATOS
# ==========================================

foreach ($base in $bases) {

    try {

        $resultado = Invoke-RestMethod `
            -Uri "$url/$base" `
            -Method Put `
            -Headers $headers `
            -ErrorAction Stop

        Write-Host "Base creada: $base" -ForegroundColor Green

    }
    catch {

        $codigo = [int]$_.Exception.Response.StatusCode

        if ($codigo -eq 412) {
            Write-Host "Ya existe: $base" -ForegroundColor Yellow
        }
        else {
            Write-Host "Error al crear $base : $_" -ForegroundColor Red
            throw
        }
    }
}
