# Runtime de produção dos três repositórios

Este Terraform prepara três Container Apps em `francecentral` no
`rg-totvs-prod`. O primeiro apply cria as aplicações com a imagem pública
temporária da documentação Azure; nenhuma versão do projeto é publicada até
os workflows de cada repositório enviarem a própria imagem ao ACR. O campo
`image` é ignorado pelo Terraform após a criação para evitar que uma futura
mudança de infra reverta um deploy da aplicação.

| Repositório | Container App | Porta | Escala | Estado |
| --- | --- | --- | --- | --- |
| `totvs-api` | `ca-totvs-api` | 8080, HTTPS externo | HTTP, 0–1 | PostgreSQL privado, Blob e envio à fila |
| `totvs-front` | `ca-totvs-front` | 3000, HTTPS externo | HTTP, 0–1 | URL da API embutida no build |
| `Worker-Challange-TOTVS` | `ca-totvs-worker` | sem ingress | Service Bus, 0–1 | Azure Files persistido em `/app/data/processed/requests` |

A API recebe credenciais e o JWT como secrets do Container App. API e Worker
usam regras SAS distintas na fila: Send e Listen. O escalador KEDA usa uma
terceira regra de namespace com Manage para consultar métricas da fila; essa
chave não é passada ao processo do Worker. O token de entrega de insights é
gerado uma vez pelo Terraform e passado aos dois serviços. A API ainda
precisa implementar a validação desse token no endpoint de insights.

A identidade gerenciada `id-totvs-acr-pull` recebe `AcrPull` para cada
Container App buscar imagens privadas. O service principal OIDC da infra
precisa de permissão para criar essa atribuição no resource group antes do
primeiro apply; veja `docs/ativacao-cd.md` no PR #8. O workflow das
aplicações usa outra identidade, com `AcrPush` e `Container Apps Contributor`.

Depois que o Terraform aplicar os recursos, integre os PRs de deploy em
`develop` e depois em `main` nos repositórios de aplicação. Uma execução
`workflow_dispatch` na `main` permite publicar a versão já mergeada caso
ela tenha chegado antes da criação dos Container Apps. Os merges seguintes em
`main` testam, constroem e publicam automaticamente cada serviço.

Verifique no primeiro deploy: revisão ativa de cada Container App, página do
frontend, inicialização da API e uma mensagem de teste na fila com entrega do
Worker. Um workflow verde hoje valida build/testes existentes e a atualização
da revisão; ainda não prova a jornada funcional completa. O frontend e a API
precisam alinhar rotas, resposta de upload, autenticação e WebSocket; a API
precisa receber os insights do Worker. A equipe de aplicação pode evoluir
esses contratos em paralelo sem mudar a topologia do deploy.

O Worker usa UID/GID 10001 no Dockerfile proposto para combinar com as
opções de montagem do Azure Files. Sem chave Groq, o Worker mantém a etapa
local documentada no próprio repositório. O limite de uma réplica restringe
custo, mas a rede privada, PostgreSQL, Service Bus, ACR, Storage, DNS e Azure
Files têm medidores próprios; acompanhar o orçamento e uso da assinatura.
