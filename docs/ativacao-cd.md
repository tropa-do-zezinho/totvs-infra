# Ativação da entrega contínua

Objetivo: `develop` executa CI; `main` publica o serviço após os checks. A infra
aplica mudanças Terraform não destrutivas na `main`. Este documento descreve a
ativação única; não contém credenciais e não cria recursos por si só.

## Ordem de ativação

1. Integrar #6 (rede/PostgreSQL), #7 (Blob/Service Bus) e #9 (Container
   Apps) em `totvs-infra/develop`, nessa ordem. O PR #9 é acumulado e contém
   as mesmas declarações de #6 e #7 enquanto eles não chegam a `develop`;
   a comparação encolhe após cada merge. O PR #8 continua fora da `main`.
2. Integrar `develop` em `main` **antes** de ativar #8. O workflow atual
   da `main` gera só um plano autenticado. Revisar o plano completo: SKU,
   região, IPs/load balancer, DNS, storage, fila, Container Apps, cotas,
   atribuição `AcrPull` e medidores. Nenhum recurso é aplicado nessa fase.
3. Dar à identidade OIDC da infra permissão para criar `AcrPull` no
   `rg-totvs-prod` (comando abaixo). `Contributor` sozinho não pode criar
   role assignments. Fazer isso antes da primeira execução de apply.
4. Após aceitar o plano e o custo estimado, integrar #8 em `develop` e
   depois em `main`. O push na `main` executará `plan` e `apply` do plano
   salvo automaticamente. Remoções e substituições são bloqueadas. O orçamento
   Azure alerta, mas não interrompe cobranças. Os três Container Apps
   inicialmente terão uma imagem pública temporária e escala 0–1.
5. Com ACR e Container Apps criados, criar uma identidade OIDC de **deploy
   das aplicações**, separada da identidade do Terraform, com `AcrPush` no
   registry e `Container Apps Contributor` em `rg-totvs-prod`.
6. Configurar as Actions variables `AZURE_DEPLOY_CLIENT_ID`,
   `AZURE_TENANT_ID` e `AZURE_SUBSCRIPTION_ID` nos três repositórios
   de aplicação. A identidade da infra continua usando `AZURE_CLIENT_ID`.
7. Integrar os PRs de deploy da API, frontend e Worker em `develop`, depois
   seguir o fluxo normal de PR para `main`. O merge em `main` testa,
   constrói imagem com a tag do commit, envia ao ACR e atualiza somente o
   Container App correspondente. Se o código já estava na `main`, executar
   `workflow_dispatch` uma vez em cada repositório. O frontend obtém o FQDN
   da API no build; `NEXT_PUBLIC_API_URL` e `NEXT_PUBLIC_WS_URL` podem
   sobrescrever os URLs quando o contrato do produto for fechado.

Nos rulesets atuais, `totvs-infra/main` exige `validate`, `totvs-api/main`
exige `test` e `totvs-front/main` exige `build`. Acrescentar `image` aos
checks obrigatórios da API e do frontend para impedir merge com imagem
quebrada. O repositório Worker está privado e a API de rulesets respondeu
`403` com exigência de GitHub Pro ou repositório público; sua CI roda, mas a
proteção obrigatória da `main` precisa esperar uma dessas opções. Aprovações
humanas podem permanecer em zero conforme o acordo da equipe. Uma falha de
deploy depois do merge fica visível no Actions e requer correção ou rerun;
a revisão anterior permanece disponível para rollback.

## Plano autenticado da primeira implantação

O [run Azure OIDC check #3](https://github.com/tropa-do-zezinho/totvs-infra/actions/runs/34773877392),
executado na `main` no commit `3c64f3f72fb845aef7d9cf800a4cf5bef803e664`,
concluiu o `terraform plan` com **26 criações, 0 alterações e 0 remoções**.
Inclui os três Container Apps 0–1, PostgreSQL privado B1ms/32 GiB, ACR
Standard, Service Bus Standard, Storage Hot LRS, Azure Files de 5 GiB,
VNet, DNS privado, identidade gerenciada e `AcrPull`. Não houve apply.

Este resultado vale para esse commit; mudanças posteriores exigem nova
revisão do plano. O plano Terraform não calcula custo. O ambiente Container
Apps integrado à VNet pode criar IPs públicos e load balancer gerenciados
que são cobrados separadamente, mesmo com as réplicas em zero:
[documentação Azure](https://learn.microsoft.com/en-us/azure/container-apps/custom-virtual-networks).
Confirmar a estimativa na calculadora e o uso real das franquias da
assinatura antes de ativar o PR #8.

## Conferir provedores Azure antes do apply

O provider Terraform está configurado para não registrar resource providers
automaticamente. No Azure Cloud Shell, com acesso Owner à assinatura:

```bash
az account set --subscription "Azure for Students"
for NS in Microsoft.App Microsoft.DBforPostgreSQL Microsoft.ContainerRegistry Microsoft.ServiceBus Microsoft.Storage Microsoft.Network Microsoft.ManagedIdentity Microsoft.Authorization; do
  STATE="$(az provider show --namespace "$NS" --query registrationState -o tsv)"
  printf '%s: %s\n' "$NS" "$STATE"
  if [ "$STATE" != "Registered" ]; then
    az provider register --namespace "$NS" --wait
  fi
done
```

Esse passo só habilita os tipos de recurso na assinatura, sem criá-los.
Se um registro falhar por política ou permissão, resolver isso antes de
integrar #8.

## Permissão única para o Terraform atribuir AcrPull

A identidade OIDC da infra já tem `Contributor` em `rg-totvs-prod`, mas isso
não cobre `Microsoft.Authorization/roleAssignments/write`. Antes do apply que
cria os Container Apps, um Owner da assinatura deve executar no Cloud Shell:

```bash
az account set --subscription "Azure for Students"
RG_ID="$(az group show --name rg-totvs-prod --query id -o tsv)"
az role assignment create \
  --assignee-object-id 237fb302-404e-4651-b2b8-7ca2731bbbca \
  --assignee-principal-type ServicePrincipal \
  --role "Role Based Access Control Administrator" \
  --scope "$RG_ID"
```

Esse papel permite gerenciar atribuições de acesso no resource group, então
limite o escopo ao `rg-totvs-prod` e revise as mudanças de IAM no Terraform.
Depois do bootstrap, confira o papel no IAM do grupo e nunca exponha tokens
ou senhas no repositório.

## OIDC das aplicações — preparação para Azure Cloud Shell

Executar uma vez **após o ACR existir**. Conferir os IDs do repositório se ele
for renomeado ou transferido. A credencial existente da infra usa sujeitos
OIDC vinculados ao ID estável da organização e do repositório; manter o mesmo
formato.

```bash
set -euo pipefail
az account set --subscription "Azure for Students"
SUBSCRIPTION_ID="$(az account show --query id -o tsv)"
TENANT_ID="$(az account show --query tenantId -o tsv)"
SUFFIX="${SUBSCRIPTION_ID//-/}"
ACR_NAME="acrtotvs${SUFFIX:0:12}"
RG_ID="$(az group show --name rg-totvs-prod --query id -o tsv)"
ACR_ID="$(az acr show --name "$ACR_NAME" --resource-group rg-totvs-prod --query id -o tsv)"

DEPLOY_APP_ID="$(az ad app create --display-name totvs-apps-github-actions --sign-in-audience AzureADMyOrg --query appId -o tsv)"
DEPLOY_SP_ID="$(az ad sp create --id "$DEPLOY_APP_ID" --query id -o tsv)"

az role assignment create --assignee-object-id "$DEPLOY_SP_ID" --assignee-principal-type ServicePrincipal --role "Container Apps Contributor" --scope "$RG_ID" -o none
az role assignment create --assignee-object-id "$DEPLOY_SP_ID" --assignee-principal-type ServicePrincipal --role AcrPush --scope "$ACR_ID" -o none

for pair in "totvs-api:1365133708" "totvs-front:1366672842" "Worker-Challange-TOTVS:1265430567"; do
  repo="${pair%%:*}"
  repo_id="${pair##*:}"
  credential="{\"name\":\"$repo-main\",\"issuer\":\"https://token.actions.githubusercontent.com\",\"subject\":\"repo:tropa-do-zezinho@327727459/$repo@$repo_id:ref:refs/heads/main\",\"audiences\":[\"api://AzureADTokenExchange\"]}"
  az ad app federated-credential create --id "$DEPLOY_APP_ID" --parameters "$credential" -o none
done

printf 'AZURE_DEPLOY_CLIENT_ID=%s\nAZURE_TENANT_ID=%s\nAZURE_SUBSCRIPTION_ID=%s\n' "$DEPLOY_APP_ID" "$TENANT_ID" "$SUBSCRIPTION_ID"
```

Os três valores finais são identificadores, não senhas. Salvá-los como
**Actions variables** da organização com acesso apenas aos três repositórios
de aplicação, ou repetir em cada repositório. Nunca adicionar o client secret.
Se o comando de criação for repetido, uma nova app será criada; antes de
reexecutar, consultar as identidades já existentes no Entra ID.

A identidade do Container App que **lê** imagens do ACR é distinta da
identidade de Actions que **envia** imagens. Sua permissão `AcrPull` deve ser
atribuída pela infra ao criar os Container Apps. Se o ACR estiver em modo
RBAC + ABAC, usar os papéis equivalentes de repositório em vez de
`AcrPush`/`AcrPull`.

## Limite da automação

A plataforma pode publicar cada repositório sem depender do horário ou das
entregas dos outros. Isso não torna contratos de API compatíveis por si só.
Hoje frontend e API divergem em rotas, autenticação e formato de resposta, e
a API ainda não recebe insights do Worker. Os CI atuais verificam build e
testes existentes, não uma jornada completa entre os três serviços. A equipe
deve alinhar esses contratos para o produto funcionar de ponta a ponta.
