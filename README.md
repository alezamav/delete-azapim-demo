# delete-azapim-demo

Teardown del laboratorio **BankX Reactive Ledger** en Azure. Borra todo lo que creó
`infra-azure-apim-webapp` y deja la suscripción sin recursos facturables.

## Qué borra

| Recurso | Nombre | Región |
|---|---|---|
| Resource Group | `rg-cardops-demo` | East US |
| AKS | `aks-cardops-demo` | East US |
| Cosmos DB (API Mongo) | `cosmos-cardops-demo` | East US 2 |
| API Management | `apim-cardops-demo` | East US |
| RG de nodos de AKS | `MC_rg-cardops-demo_aks-cardops-demo_eastus` | East US |
| Soft delete de APIM | `apim-cardops-demo` | East US |

El Resource Group de nodos (`MC_…`) lo crea AKS por su cuenta: contiene los nodos,
los discos y la **IP pública del ingress**. Normalmente cae con el RG padre, pero si
el borrado de AKS falla queda huérfano y sigue facturando. El script lo comprueba.

## Cómo se ejecuta

### Desde GitHub Actions (recomendado)

El pipeline **no se dispara con push**. Se ejecuta a mano:

1. Pestaña **Actions** → workflow `destroy-infra` → **Run workflow**.
2. En el campo `confirmar`, escribir exactamente `DESTRUIR`.
3. **Run workflow**.

Tarda entre 30 y 50 minutos: APIM es el recurso lento. El job espera a que termine
de verdad, así la validación final significa algo.

### Desde Cloud Shell

```powershell
az login
az account set --subscription "<id de la suscripción>"
./destroy.ps1
```

Pide confirmación. Con `-Force` no pregunta.

## El soft delete de APIM

API Management no se borra del todo: queda **48 horas en soft delete**. No factura,
pero el nombre `apim-cardops-demo` sigue reservado y no se puede volver a montar el
laboratorio con el mismo nombre hasta purgarlo.

Purgarlo es una operación **a nivel de suscripción**, no del Resource Group. El
Service Principal del laboratorio tiene Contributor solo sobre `rg-cardops-demo`,
así que recibe **403** en este paso. El pipeline no se corta por eso: avisa y deja
el comando listo para ejecutarlo a mano.

```bash
az apim deletedservice list -o table
az apim deletedservice purge --service-name apim-cardops-demo --location eastus
```

Para automatizarlo habría que dar al Service Principal un rol a nivel de
suscripción con la acción `Microsoft.ApiManagement/locations/deletedservices/delete`.
Para un laboratorio no vale la pena: un comando manual cada vez que se resetea es
menos superficie de permisos que un rol permanente sobre toda la suscripción.

## Después del teardown

Borrar el Resource Group **también borra la asignación de rol** del Service
Principal, porque estaba al ámbito de ese RG. Para volver a desplegar hay que
recrear el RG y volver a asignar el rol:

```bash
az group create --name rg-cardops-demo --location eastus
az role assignment create \
  --assignee <clientId del SP> \
  --role Contributor \
  --scope /subscriptions/<id>/resourceGroups/rg-cardops-demo
```

El Service Principal y su secreto siguen siendo válidos; solo se perdió el permiso.

## Verificar que no queda nada

```bash
az group list --query "[?contains(name,'cardops')].name" -o tsv
az apim deletedservice list -o table
az resource list --query "[?contains(resourceGroup,'cardops')].name" -o tsv
```

Las tres salidas vacías significan laboratorio en cero.
