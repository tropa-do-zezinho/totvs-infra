# totvs-infra

Infraestrutura como código do projeto da equipe.

O diretório `prod/` usa estado remoto no Azure Blob Storage. A autenticação
no GitHub Actions usa OIDC, sem senha ou chave de serviço no repositório.

`terraform-check.yml` verifica formatação e validação em `develop`, `main` e
pull requests para essas branches. `azure-oidc-check.yml` executa um
`terraform plan` na `main` e pode ser acionado manualmente. Por enquanto, o
plano apenas consulta o grupo de recursos existente para verificar o acesso
da identidade federada. Nenhum workflow executa `terraform apply` ou cria
serviços da aplicação.

Antes de habilitar o deploy: confirmar as franquias e custos da assinatura,
declarar os recursos necessários, revisar o plano e proteger a branch `main`
com PR obrigatório.

Não versionar arquivos de estado, planos, `.tfvars` com dados privados ou
credenciais. Manter o provedor fixado e versionar `.terraform.lock.hcl`
quando gerado.
