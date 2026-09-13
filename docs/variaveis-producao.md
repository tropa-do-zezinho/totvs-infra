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
| `WORKER_OUTPUT_DIR` | Caminho de saída **persistente e compartilhável** | Pendente: o Worker atual escreve em disco local. |
| `GROQ_API_KEY` | Chave do provedor Groq, se a etapa LLM for usada | Secret externo à Azure; sem chave o código mantém a triagem local. |
| `LLM_MODEL`, `MAX_LLM_CALLS`, `LLM_RPM`, `LLM_MAX_RETRIES` | Defaults do `.env.example`, ajustados ao limite real da conta | Configuração, sem credenciais. |

A API publica `request_id`, `file_url` e `file_name`, que correspondem ao
contrato do Worker. O Worker só confirma a mensagem depois de gravar
`_SUCCESS.json`. Um diretório efêmero no Container Apps perderia esse marcador
e os resultados entre reinícios, quebrando idempotência e acesso pelo backend.
Antes do deploy, escolher publicação dos resultados em Blob Storage ou um
volume compartilhado acessível pela API. O repositório do Worker ainda não tem
Dockerfile, CI ou branch `develop`.

## Recursos ainda necessários

- Um Storage Account de aplicação com container privado `reunioes`, separado
  do backend Terraform. A API atual gera SAS com chave de conta.
- Um namespace Azure Service Bus Standard e uma fila
  `reunioes-para-analise`, com DLQ monitorada e permissões Send/Listen separadas.
- Uma forma persistente de guardar `dashboard/insights.json` e demais saídas
  do Worker, com contrato de leitura definido com a API.

A assinatura mostrou franquias de Blob Storage Hot LRS e Service Bus Standard
ainda sem uso. Conferir o medidor e o custo efetivo da configuração antes do
`apply`. O crédito Azure não cobre eventuais cobranças da Groq.
