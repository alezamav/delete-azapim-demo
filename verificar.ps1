# verificar.ps1 - Cierra el teardown y confirma que el laboratorio quedo en cero.
#
# Se ejecuta en Cloud Shell CON UNA CUENTA DE USUARIO, no con el Service
# Principal: todo lo que comprueba vive fuera de rg-cardops-demo y necesita
# permisos de suscripcion. Ademas, si el RG ya se borro, el SP perdio su
# asignacion de rol y no puede ni listar Resource Groups.
#
#   ./verificar.ps1

. "$PSScriptRoot/variables.ps1"

Write-Host ""
Write-Host "Suscripcion activa:" (az account show --query name -o tsv)
Write-Host ""

$fallos = 0

# ---------------------------------------------------------------------------
# 1. El Resource Group principal
# ---------------------------------------------------------------------------
if ((az group exists --name $RG) -eq "true") {
    $estado = az group show --name $RG --query properties.provisioningState -o tsv
    Write-Host "  FALTA: '$RG' todavia existe (estado: $estado)." -ForegroundColor Red
    if ($estado -eq "Deleting") {
        Write-Host "         Sigue borrandose. Espera unos minutos y repite." -ForegroundColor Yellow
    }
    $fallos++
} else {
    Write-Host "  OK: Resource Group '$RG' borrado." -ForegroundColor Green
}

# ---------------------------------------------------------------------------
# 2. El Resource Group de nodos de AKS
# AKS crea MC_<rg>_<aks>_<region> con los nodos, los discos y la IP publica
# del ingress. Cae con el RG padre, pero si el borrado de AKS fallo queda
# huerfano y sigue facturando: es el recurso que mas cuesta de los tres.
# ---------------------------------------------------------------------------
$mc = az group list --query "[?starts_with(name,'MC_$($RG)_')].name" -o tsv
if ([string]::IsNullOrWhiteSpace($mc)) {
    Write-Host "  OK: sin Resource Groups de nodos huerfanos." -ForegroundColor Green
} else {
    foreach ($g in ($mc -split "`n" | Where-Object { $_ })) {
        Write-Host "  FALTA: RG de nodos huerfano '$($g.Trim())'. Borrando." -ForegroundColor Yellow
        az group delete --name $g.Trim() --yes
    }
    $fallos++
}

# ---------------------------------------------------------------------------
# 3. Soft delete de APIM
# APIM queda 48 h en soft delete aunque borres el RG. No factura, pero el
# nombre no se puede reutilizar hasta purgarlo: sin esto no se puede volver
# a montar el laboratorio con los mismos nombres.
# ---------------------------------------------------------------------------
$soft = az apim deletedservice list --query "[?name=='$APIM_NAME'].name" -o tsv 2>$null
if ([string]::IsNullOrWhiteSpace($soft)) {
    Write-Host "  OK: sin APIM en soft delete." -ForegroundColor Green
} else {
    Write-Host "  '$APIM_NAME' esta en soft delete. Purgando para liberar el nombre." -ForegroundColor Yellow
    az apim deletedservice purge --service-name $APIM_NAME --location $APIM_LOCATION --only-show-errors
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  OK: APIM purgado. El nombre '$APIM_NAME' queda libre." -ForegroundColor Green
    } else {
        Write-Host "  FALTA: no se pudo purgar. Tu cuenta necesita permisos a nivel de suscripcion." -ForegroundColor Red
        $fallos++
    }
}

# ---------------------------------------------------------------------------
# 4. Barrido final por si quedo algo suelto fuera del RG
# ---------------------------------------------------------------------------
$sueltos = az resource list --query "[?contains(name,'cardops')].{n:name,t:type,rg:resourceGroup}" -o tsv
if (-not [string]::IsNullOrWhiteSpace($sueltos)) {
    Write-Host ""
    Write-Host "  AVISO: quedan recursos con 'cardops' en el nombre:" -ForegroundColor Yellow
    Write-Host $sueltos
    $fallos++
}

# ---------------------------------------------------------------------------
Write-Host ""
if ($fallos -gt 0) {
    Write-Host "Quedan cosas por cerrar. Revisa los mensajes anteriores." -ForegroundColor Red
    exit 1
}
Write-Host "Laboratorio en cero: sin recursos facturables y sin nombres reservados." -ForegroundColor Green
Write-Host ""
Write-Host "Para volver a desplegar hay que recrear el RG y reasignar el rol al SP:" -ForegroundColor Cyan
Write-Host "  az group create --name $RG --location $LOC"
Write-Host "  az role assignment create --assignee <clientId> --role Contributor \"
Write-Host "    --scope /subscriptions/`$(az account show --query id -o tsv)/resourceGroups/$RG"
