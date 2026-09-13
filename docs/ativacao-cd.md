# Ativação da entrega contínua

Objetivo: `develop` executa CI; `main` publica o serviço após os checks. A infra
aplica mudanças Terraform não destrutivas na `main`. Este documento descreve a
ativação única; não contém credenciais e não cria recursos por si só.

## Ordem de ativação

1. Integrar os PRs de rede/PostgreSQL (#6) e Blob/Service Bus (#7) em
   `totvs-infra/develop`. Integrar `develop` em `main` **antes** de ativar o PR
   de apply automático (#8). O workflow atual da `main` gera somente um plano
   autenticado. Revisar nele SKU, região, IPs/load balancer, DNS, storage, fila,
   cotas e medidores da assinatura.
2. Só depois da revisão, integrar o PR #8 na `main`. Essa alteração executará
   `plan` e `apply` automaticamente para recursos novos ou atualizações.
   Remoções e substituições são bloqueadas pelo workflow. O orçamento Azure
   alerta, mas não impede cobranças.
3. Declarar os três Container Apps no Terraform e aplicar pela `main`: API
   `ca-totvs-api`, frontend `ca-totvs-front` e Worker `ca-totvs-worker`.
   Configurar secrets no Container App, Azure Files no Worker, escala e
   identidade de leitura do ACR. O Terraform deve ignorar somente a tag da
   imagem, que os workflows de cada aplicação atualizam.
4. Criar uma identidade OIDC de **deploy das aplicações**, separada da identidade
   `totvs-infra-main`, e atribuir `AcrPush` no registry e
   `Container Apps Contributor` em `rg-totvs-prod`. OIDC evita client secret.
5. Configurar as variáveis de Actions `AZURE_DEPLOY_CLIENT_ID`,
   `AZURE_TENANT_ID` e `AZURE_SUBSCRIPTION_ID` nos três repositórios de
   aplicação. A identidade da infra continua usando `AZURE_CLIENT_ID`.
6. Integrar os PRs de deploy da API, frontend e Worker em `develop`, depois
   seguir o fluxo normal de PR para `main`. O merge em `main` testa, constrói
   imagem com a tag do commit, envia ao ACR e atualiza somente o Container App
   correspondente. O frontend obtém o FQDN da API no momento do build;
   `NEXT_PUBLIC_API_URL` e `NEXT_PUBLIC_WS_URL` podem sobrescrever os URLs
   gerados quando o contrato do projeto for fechado.

A `main` de cada repositório deve exigir os checks `test` e `image` (API),
`build` e `image` (frontend), `validate` (Worker e infra). Aprovações humanas
obrigatórias podem permanecer em zero conforme o acordo da equipe. Uma falha
de deploy depois do merge fica visível no Actions e requer correção ou rerun;
a revisão anterior permanece disponível para rollback.

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
