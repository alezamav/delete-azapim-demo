# destroy.ps1 - Borra el laboratorio de Azure y deja la suscripcion en cero.
# Ejecucion manual desde Cloud Shell (PowerShell) o desde una maquina con az cli.
#
#   .\destroy.ps1            -> pide confirmacion
#   .\destroy.ps1 -Force     -> sin preguntar (para automatizacion)

param(
    [switch]$Force
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot/variables.ps1"

# ---------------------------------------------------------------------------
# Confirmacion
# ---------------------------------------------------------------------------
if (-not $Force) {
    Write-Host ""
    Write-Host "Esto borra el Resource Group '$RG' y todo lo que contiene:" -ForegroundColor Yellow
    Write-Host "  - AKS    $AKS_NAME"
    Write-Host "  - APIM   $APIM_NAME"
    Write-Host "  - Cosmos $COSMOS_ACCOUNT"
    Write-Host ""
    $r = Read-Host "Escribe DESTRUIR para continuar"
    if ($r -ne "DESTRUIR") {
        Write-Host "Cancelado." -ForegroundColor Green
        exit 0
    }
}

# ---------------------------------------------------------------------------
# Suscripcion en uso: dejar constancia de donde estamos borrando
# ---------------------------------------------------------------------------
$sub = az account show --query "{nombre:name, id:id}" -o tsv
Write-Host "Suscripcion activa: $sub"

# ---------------------------------------------------------------------------
# Inventario previo
# ---------------------------------------------------------------------------
if ((az group exists --name $RG) -eq "false") {
    Write-Host "El Resource Group '$RG' no existe." -ForegroundColor Green
} else {
    Write-Host ""
    Write-Host "Recursos que se van a borrar:"
    az resource list --resource-group $RG `
        --query "[].{nombre:name, tipo:type, region:location}" -o table

    # -----------------------------------------------------------------------
    # Borrado. Sin --no-wait: hay que esperar a que APIM pase a soft delete
    # antes de intentar purgarlo, o el purge no encuentra nada.
    # Tarda entre 30 y 50 min.
    # -----------------------------------------------------------------------
    Write-Host ""
    Write-Host "Borrando '$RG'. Tarda entre 30 y 50 min por APIM. No cierres la sesion." -ForegroundColor Yellow
    az group delete --name $RG --yes
    Write-Host "Resource Group borrado." -ForegroundColor Green
}

# ---------------------------------------------------------------------------
# Resource Group de nodos de AKS (MC_...)
# AKS crea su propio RG con los nodos, los discos y la IP publica del
# ingress. Cae con el RG padre, pero si el borrado de AKS fallo queda
# huerfano y sigue facturando.
# ---------------------------------------------------------------------------
$mc = az group list --query "[?starts_with(name,'MC_$($RG)_')].name" -o tsv
if ([string]::IsNullOrWhiteSpace($mc)) {
    Write-Host "Sin Resource Groups de nodos huerfanos." -ForegroundColor Green
} else {
    foreach ($g in ($mc -split "`n" | Where-Object { $_ })) {
        Write-Host "RG de nodos huerfano: $g. Borrando." -ForegroundColor Yellow
        az group delete --name $g.Trim() --yes
    }
}

# ---------------------------------------------------------------------------
# Soft delete de APIM
# APIM queda 48 h en soft delete aunque borres el RG. No factura, pero el
# nombre '$APIM_NAME' no se puede reutilizar hasta purgarlo.
# El purge actua a nivel de suscripcion: un Service Principal con
# Contributor solo en el RG recibe 403 aqui.
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "Comprobando soft delete de APIM..."
try {
    az apim deletedservice purge `
        --service-name $APIM_NAME `
        --location $APIM_LOCATION `
        --only-show-errors
    Write-Host "APIM purgado. El nombre '$APIM_NAME' queda libre." -ForegroundColor Green
}
catch {
    Write-Host "No se pudo purgar APIM automaticamente." -ForegroundColor Yellow
    Write-Host "Si es falta de permisos, ejecutalo con una cuenta con acceso a la suscripcion:"
    Write-Host "  az apim deletedservice purge --service-name $APIM_NAME --location $APIM_LOCATION"
}

# ---------------------------------------------------------------------------
# Validacion final
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "Validacion final:"
$fallos = 0

if ((az group exists --name $RG) -eq "true") {
    Write-Host "  FALTA: el Resource Group '$RG' todavia existe." -ForegroundColor Red
    $fallos++
} else {
    Write-Host "  OK: Resource Group borrado." -ForegroundColor Green
}

$mc2 = az group list --query "[?starts_with(name,'MC_$($RG)_')].name" -o tsv
if (-not [string]::IsNullOrWhiteSpace($mc2)) {
    Write-Host "  FALTA: quedan Resource Groups de nodos: $mc2" -ForegroundColor Red
    $fallos++
} else {
    Write-Host "  OK: sin Resource Groups de nodos." -ForegroundColor Green
}

$soft = az apim deletedservice list --query "[?name=='$APIM_NAME'].name" -o tsv 2>$null
if (-not [string]::IsNullOrWhiteSpace($soft)) {
    Write-Host "  AVISO: '$APIM_NAME' sigue en soft delete. No factura, el nombre esta reservado." -ForegroundColor Yellow
} else {
    Write-Host "  OK: sin APIM en soft delete." -ForegroundColor Green
}

Write-Host ""
if ($fallos -gt 0) {
    Write-Host "Quedan recursos sin borrar. Revisa los mensajes anteriores." -ForegroundColor Red
    exit 1
}
Write-Host "Laboratorio en cero: no quedan recursos facturables." -ForegroundColor Green
