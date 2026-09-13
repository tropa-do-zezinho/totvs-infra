# Variáveis de produção — API e Worker

Leitura de `totvs-api/develop` e `Worker-Challange-TOTVS/main` em
13/09/2026. Esta lista é o contrato para os futuros Container Apps; não contém
credenciais e não cria serviços. Valores secretos devem entrar como secrets dos
Container Apps, nunca como variáveis do GitHub, arquivos versionados ou outputs
do Terraform.

## API Spring Boot

| Variável | Origem para produção | Tratamento |
| --- | --- | --- |
| `SPRING_DATASOURCE_URL` | `jdbc:postgresql://<postgres_fqdn>:5432/totvs?sslmode=require` | Configuração; substitui o `localhost` de desenvolvimento. |
| `SPRING_DATASOURCE_USERNAME` | `totvsadmin` no Terraform atual | Configuração. |
| `SPRING_DATASOURCE_PASSWORD` | Senha gerada para o PostgreSQL | Secret. A senha ficará no estado remoto do Terraform após apply. |
| `SPRING_DOCKER_COMPOSE_ENABLED` | `false` | Configuração; a CI da API já usa essa opção. |
| `JWT_SECRET` | Valor aleatório com ao menos 32 caracteres | Secret; não usar o fallback de desenvolvimento do `application.properties`. |
| `AZURE_STORAGE_CONNECTION_STRING` | Storage Account **da aplicação**, separado de `sttotvstf123456` | Secret. O código atual também aceita `AZURE_STORAGE_ACCOUNT_NAME` + `AZURE_STORAGE_ACCOUNT_KEY`; escolher somente uma forma. |
| `AZURE_STORAGE_CONTAINER_NAME` | `reunioes` | Configuração; mesmo container do upload. |
| `AZURE_STORAGE_SAS_EXPIRY_HOURS` | `24` inicialmente | Configuração; precisa cobrir o atraso até o Worker baixar o arquivo. |
| `AZURE_SERVICE_BUS_CONNECTION_STRING` | Regra SAS **Send** da fila | Secret, diferente do valor do Worker. |
| `AZURE_SERVICE_BUS_QUEUE_NAME` | `reunioes-para-analise` | Configuração. A API usa `meet-process` como default local; o override evita divergência. |

O `application.properties` ainda contém defaults locais para Postgres, Azurite
e emulador de Service Bus. O deploy deve definir todos os overrides acima; sem
isso, a aplicação pode iniciar apontando para serviços locais inexistentes.

## Worker Python

| Variável | Origem para produção | Tratamento |
| --- | --- | --- |
| `AZURE_SERVICE_BUS_CONNECTION_STRING` | Regra SAS **Listen** da mesma fila | Secret. |
| `AZURE_SERVICE_BUS_QUEUE_NAME` | `reunioes-para-analise` | Configuração; igual à API. |
| `WORKER_ALLOWED_DOWNLOAD_HOSTS` | Host exato `<storage>.blob.core.windows.net` | Configuração; restringe URLs SAS aceitas. |
| `WORKER_OUTPUT_DIR` | `/app/data/processed/requests`, com Azure Files montado nesse caminho | Configuração. O Dockerfile declara volume, mas o Container App precisa montar o share. |
| `INSIGHTS_API_URL` | URL HTTPS do endpoint de ingestão da API (contrato sugerido: `/api/v1/worker/insights`) | Configuração obrigatória no modo Worker; o endpoint ainda não existe em `totvs-api/develop`. |
| `INSIGHTS_API_TOKEN` | Token compartilhado para autenticar a entrega HTTP | Secret; a API precisa validar o Bearer token. |
| `GROQ_API_KEY` | Chave do provedor Groq, se a etapa LLM for usada | Secret externo à Azure; sem chave o código mantém a triagem local. |
| `LLM_MODEL`, `MAX_LLM_CALLS`, `LLM_RPM`, `LLM_MAX_RETRIES` | Defaults do `.env.example`, ajustados ao limite real da conta | Configuração, sem credenciais. |

A API publica `request_id`, `file_url` e `file_name`, que correspondem ao
contrato do Worker. O Worker grava `_SUCCESS.json`, entrega `dashboard/insights.json` à API por HTTP,
grava `_API_DELIVERED.json` e só então confirma a mensagem. Um diretório efêmero
perderia os marcadores entre reinícios e poderia repetir a análise. O Dockerfile
já existe; ainda faltam CI e branch `develop`. O endpoint HTTP de ingestão ainda
não aparece em `totvs-api/develop`, portanto o fluxo completo não funciona até
a API implementá-lo e validar o token.

## Recursos ainda necessários

- Um Storage Account de aplicação com container privado `reunioes`, separado
  do backend Terraform. A API atual gera SAS com chave de conta.
- Um namespace Azure Service Bus Standard e uma fila
  `reunioes-para-analise`, com DLQ monitorada e permissões Send/Listen separadas.
- Um Azure Files share pequeno montado no caminho do Worker para manter os
  marcadores e os arquivos entre tentativas. A API receberá o JSON consolidado
  por HTTP, não por leitura direta desse volume.
- O endpoint HTTP de ingestão de insights na API, com autenticação por token e
  upsert idempotente por `request_id`.

A assinatura mostrou franquias de Blob Storage Hot LRS e Service Bus Standard
ainda sem uso. Conferir o medidor e o custo efetivo da configuração antes do
`apply`. O crédito Azure não cobre eventuais cobranças da Groq.
