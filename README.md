# totvs-infra

Infraestrutura como código do projeto da equipe.

O diretório `prod/` usa estado remoto no Azure Blob Storage. A autenticação
no GitHub Actions usa OIDC, sem senha ou chave de serviço no repositório.

`terraform-check.yml` verifica formatação e validação em `develop`, `main` e
pull requests para essas branches. `azure-oidc-check.yml` executa um
`terraform plan` na `main` e pode ser acionado manualmente. **Nenhum workflow
executa `terraform apply`**.

O código declara um Container Registry Standard e propõe a rede compartilhada
para os futuros Container Apps, com PostgreSQL B1ms em sub-rede privada. A
aplicação ainda não está implantada: faltam imagens, identidades de deploy e
ajustes no contrato entre front e API. Consulte `docs/plano-deploy.md`.

A senha de administrador do PostgreSQL será gerada por `random_password`
quando houver um `apply` e ficará no estado remoto do Terraform. Restrinja o
acesso ao container `tfstate`; não exponha o estado, arquivos de plano ou
credenciais em logs ou no repositório. Não versionar `.tfvars` com dados
privados. Versionar `.terraform.lock.hcl` quando gerado.

Antes de habilitar o `apply`: confirmar no portal as cotas e os provedores
registrados; revisar o plano para garantir somente os recursos esperados;
estimar DNS privado, IPs públicos e load balancer gerenciados pelo Container
Apps; e acompanhar os medidores gratuitos e o orçamento da assinatura. A
franquia não garante custo zero caso o uso ultrapasse seus limites.
