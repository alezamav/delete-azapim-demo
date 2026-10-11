# Nombres del laboratorio BankX Reactive Ledger en Azure.
# Deben coincidir con los de infra-azure-apim-webapp/variables.ps1,
# o el teardown apuntara a recursos que no existen.

$RG             = "rg-cardops-demo"
$LOC            = "eastus"       # region del Resource Group
$APIM_NAME      = "apim-cardops-demo"
$APIM_LOCATION  = "eastus"       # region de APIM: la necesita el purge del soft delete
$AKS_NAME       = "aks-cardops-demo"
$COSMOS_ACCOUNT = "cosmos-cardops-demo"
$COSMOS_LOC     = "eastus2"      # Cosmos se creo en East US 2 por capacidad en East US
$COSMOS_DB_NAME = "bankx"
