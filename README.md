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

Tarda entre 10 y 50 minutos según la carga de la región: APIM es el recurso lento.
El job espera a que Azure termine de verdad, no solo a que acepte la petición.

Cuando acabe, el resumen del job indica los comandos de verificación pendientes.

### Cerrar el teardown (obligatorio)

El pipeline solo puede borrar el Resource Group. **Lo que queda fuera de ese RG hay
que comprobarlo con una cuenta de usuario** — ver la sección siguiente. En Cloud Shell:

```powershell
./verificar.ps1
```

Comprueba el RG, borra el `MC_` si quedó huérfano, purga el soft delete de APIM y
hace un barrido final por nombre.

### Todo a mano, sin pipeline

```powershell
az login
az account set --subscription "<id de la suscripción>"
./destroy.ps1      # borra el RG; -Force para no preguntar
./verificar.ps1    # cierra y confirma
```

## Por qué hacen falta dos pasos

El Service Principal tiene Contributor **solo sobre `rg-cardops-demo`**. En cuanto
el pipeline borra ese Resource Group, desaparece también su asignación de rol,
porque estaba al ámbito de ese RG. A partir de ese instante el SP no tiene **ningún**
permiso en la suscripción: ni siquiera `Microsoft.Resources/subscriptions/resourceGroups/read`.

Todo lo que queda por comprobar vive fuera del RG borrado:

| Qué | Dónde vive | Quién puede |
|---|---|---|
| `rg-cardops-demo` | Resource Group | el SP (hasta borrarlo) |
| `MC_rg-cardops-demo_…` | **otro** Resource Group | cuenta con lectura de suscripción |
| Soft delete de APIM | ámbito de **suscripción** | cuenta con permisos de suscripción |

Por eso el pipeline borra y `verificar.ps1` cierra. La alternativa sería dar Reader
al SP sobre toda la suscripción: para un laboratorio, un comando manual al resetear
es menos superficie de permisos que un rol permanente sobre todo.

## El soft delete de APIM

API Management no se borra del todo: queda **48 horas en soft delete**. No factura,
pero el nombre `apim-cardops-demo` sigue reservado y no se puede volver a montar el
laboratorio con el mismo nombre hasta purgarlo.

Purgarlo es una operación **a nivel de suscripción**, no del Resource Group, así que
el Service Principal recibe 403. Lo hace `verificar.ps1`, o a mano:

```bash
az apim deletedservice list -o table
az apim deletedservice purge --service-name apim-cardops-demo --location eastus
```

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
