# Plano inicial de deploy — TOTVS

Este plano usa o que existe em `totvs-front`, `totvs-api` e `totvs-infra` em 12/09/2026. Ele pode evoluir quando os outros serviços e a integração entre front e API estiverem prontos. Nenhum recurso de aplicação é criado por este documento.

## O que já está pronto

- `main` dos três repositórios protegida por PR e pelo respectivo check de CI (`build`, `test` ou `validate`). As aprovações obrigatórias estão em zero.
- `totvs-infra` autentica no Azure por OIDC, usa estado remoto no container `tfstate` e executa `terraform plan` na `main`. Ainda não há `terraform apply` automático.
- A assinatura Azure for Students permite, por política, `francecentral` entre outras regiões. O backend Terraform já está nessa região. Disponibilidade e cotas de cada serviço ainda precisam ser confirmadas na assinatura antes da criação.

## Primeira arquitetura proposta

| Componente | Serviço inicial | Motivo |
| --- | --- | --- |
| Front Next.js | Azure Container Apps, Consumption, 0–1 réplica | O projeto usa `proxy.js` e rotas dinâmicas; precisa do servidor Next.js. Scale to zero reduz custo de computação sem tráfego, mas causa partida fria. |
| API Spring Boot | Azure Container Apps, Consumption, 0–1 réplica | Executa Java e expõe HTTP. A partida fria também vale para a API. |
| Banco | Azure Database for PostgreSQL Flexible Server, Burstable B1ms, sem HA | A API já usa JPA/PostgreSQL. É o principal custo contínuo: scale to zero dos containers não para o banco. Confirmar preço regional, cota e armazenamento mínimo antes do merge que o criar. |
| Imagens | Azure Container Registry Standard | Guarda as imagens privadas dos dois serviços. A assinatura mostra franquia Standard Registry Unit de 31 unidades de dia no medidor exibido; monitorar o consumo mensal e evitar um segundo registry. |
| Logs | Log Analytics / logs do Container Apps, retenção e volume mínimos | Diagnóstico de falhas de deploy e da aplicação; acompanhar ingestão para controlar custo. |

Usar `rg-totvs-prod` e, inicialmente, `francecentral` para os recursos da aplicação. A comparação abaixo mostra que ela não é a região de menor preço de tabela, mas a economia nominal de mudar para `mexicocentral` é pequena no cenário atual. Manter `rg-totvs-tfstate` e seu Storage Account exclusivamente para o estado Terraform: arquivos enviados pelos usuários devem usar outra conta/container, quando o upload de fato existir. Não criar RabbitMQ neste primeiro lote: há dependência e serviço no `compose.yaml`, mas não há uso implementado no código atual.

Antes de codificar a rede, confirmar a opção de acesso privado do PostgreSQL com o Container Apps na assinatura. Não abrir o banco à internet apenas para acelerar o primeiro deploy. Uma rede virtual customizada para Container Apps pode adicionar cobranças de IP público e load balancer; essas parcelas não entram na estimativa regional abaixo.

## Comparação de regiões e franquias

Consultado em 12/09/2026 na [API oficial de preços de varejo da Azure](https://learn.microsoft.com/en-us/rest/api/cost-management/retail-prices/azure-retail-prices), em USD e sem descontos. Hipótese ilustrativa: **um** PostgreSQL Flexible Server B1ms ligado por 730 horas, 32 GB provisionados e **um** Container Registry Basic por 30 dias. Não inclui rede, logs, tráfego, backup excedente nem uso de Container Apps fora da franquia.

| Região permitida | B1ms por hora | PostgreSQL por GB/mês | ACR Basic por dia | Base ilustrativa por mês |
| --- | ---: | ---: | ---: | ---: |
| Mexico Central | US$ 0,0187 | US$ 0,1265 | US$ 0,1666 | **US$ 22,70** |
| France Central | US$ 0,0190 | US$ 0,1330 | US$ 0,1666 | **US$ 23,12** |
| Italy North | US$ 0,0199 | US$ 0,1369 | US$ 0,1666 | **US$ 23,91** |
| Spain Central | US$ 0,0199 | US$ 0,1369 | US$ 0,1666 | **US$ 23,91** |
| Brazil South | US$ 0,0350 | US$ 0,2185 | US$ 0,1666 | **US$ 37,54** |

Sem franquias, Mexico Central economizaria cerca de **US$ 0,42/mês** frente a France Central nesse conjunto fixo. Isso não decide sozinho o custo total: Container Apps tem preço por uso ligeiramente maior no México, e a rede privada ainda não foi desenhada. Para o tráfego baixo previsto, a franquia mensal do Container Apps tende a cobrir o consumo, desde que outras aplicações da assinatura não a usem.

Mais importante: o [Azure for Students](https://azure.microsoft.com/en-us/free/students) lista **750 horas/mês de PostgreSQL B1ms com 32 GB de armazenamento e backup por 12 meses**, **um ACR Standard com 100 GB por 12 meses** e a franquia permanente do **Container Apps**. Em 12/09/2026, o portal da assinatura do projeto mostrou os quatro medidores relevantes disponíveis e ainda sem uso: PostgreSQL B1MS 0/750 horas, armazenamento 0/32 GB-mês, backup 0/32 GB-mês e ACR Standard 0/31 dias. Portanto, planejar **um PostgreSQL B1MS de 32 GB e um ACR Standard**, com custo de tabela coberto por essas franquias enquanto permanecerem ativas e dentro dos limites. A [página de uso gratuito](https://learn.microsoft.com/en-us/azure/cost-management-billing/manage/check-free-service-usage) explica o monitoramento. Não alterar a região do backend Terraform por causa da diferença pequena de preço de tabela.

## Fluxo de entrega desejado

1. PR para `main` roda o check obrigatório. `develop` continua sem deploy.
2. Merge de código da aplicação em `main` constrói uma imagem com tag imutável do commit, envia ao registry e atualiza a revisão do Container App correspondente.
3. Merge de Terraform em `main` executa `plan` e, quando o primeiro lote estiver revisado e habilitado, `apply`. A identidade OIDC atual só confia no `totvs-infra/main`; front e API precisarão de credenciais federadas próprias para os respectivos workflows de deploy, com permissões limitadas.
4. Os workflows devem falhar visivelmente se build, push ou atualização da revisão falharem. Não registrar segredos em logs, arquivos versionados ou parâmetros públicos de build.

Ainda não habilitar `apply` ou deploy de aplicações: falta declarar a infraestrutura, verificar custo/cota e preparar as imagens. Isso preserva o acordo de que, **quando o pipeline estiver pronto**, merge em `main` publica automaticamente.

## Trabalho que pode começar agora, sem esperar novos repositórios

- Criar Dockerfiles e testar localmente as imagens de front e API, sem alterar a lógica de negócio.
- Declarar a primeira infraestrutura em Terraform num PR para `develop`; o check valida a sintaxe e um `plan` separado mostra recursos e custo esperado antes de qualquer `apply`.
- Preparar workflows de build/push/deploy para `main`, condicionados à existência dos recursos e das identidades OIDC correspondentes.
- Conferir na Azure: disponibilidade do SKU B1MS e cota dos serviços em `francecentral`, preço da configuração completa com rede por 2,5 meses e alertas do orçamento de US$ 80. Monitorar mensalmente as franquias já identificadas; o orçamento alerta, mas não funciona como desligamento automático.

## Contrato que a equipe precisa fechar antes do deploy funcional

- **Autenticação:** o front chama `/auth/login` e espera sessão em cookie `ct_session`; a API expõe `/api/auth/login` e devolve JWT no corpo. Decidir um contrato único para URL, cookie/token e CORS.
- **2FA e WebSocket:** o front chama rotas de 2FA e `/ws/jobs/{id}`; essas rotas ainda não aparecem na API atual. Definir se farão parte da entrega inicial.
- **Upload:** `BlobController` e `BlobService` estão vazios. Definir se o upload será implementado e, então, provisionar Storage de aplicação separado do `tfstate`.
- **Mensageria:** confirmar se RabbitMQ será usado de fato. Se não houver consumidor/produtor, não provisionar broker.
- **Configuração de produção:** parametrizar URL/usuário/senha do PostgreSQL e um `JWT_SECRET` forte na API; decidir os nomes dos domínios/URLs públicos. Os valores de produção não devem ficar em `application.properties` nem no repositório.

## Referências

- [Next.js: Proxy requer servidor e não funciona em exportação estática](https://nextjs.org/docs/app/guides/self-hosting#proxy).
- [Container Apps: scale to zero e cobrança](https://learn.microsoft.com/en-us/azure/container-apps/scale-app) e [preços do plano Consumption](https://azure.microsoft.com/en-us/pricing/details/container-apps/).
- [PostgreSQL Flexible Server: regiões e opções de computação](https://learn.microsoft.com/en-us/azure/postgresql/flexible-server/overview) e [preços](https://azure.microsoft.com/en-us/pricing/details/postgresql/flexible-server/).
- [Azure Container Registry: SKUs](https://learn.microsoft.com/en-us/azure/container-registry/container-registry-skus).
- [Custos adicionais de VNet customizada no Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/custom-virtual-networks).

