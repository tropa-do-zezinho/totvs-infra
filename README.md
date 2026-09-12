# totvs-infra

Infraestrutura como código do projeto da equipe.

O diretório `prod/` contém a configuração do backend remoto do Terraform.
As credenciais não ficam no repositório: no Cloud Shell, o Terraform usa a
sessão do Azure CLI; no GitHub Actions, a autenticação será feita por OIDC.

O workflow atual verifica formatação e validação em `develop`, `main` e pull
requests para `main`. Ele não executa `terraform apply` e ainda não cria os
serviços da aplicação.

Próximos passos: conectar uma identidade federada ao GitHub Actions, conferir
custos e disponibilidade dos serviços, declarar os recursos em Terraform e
revisar o plano antes de habilitar o deploy na `main`.

Não versionar arquivos de estado, planos, `.tfvars` com dados privados ou
credenciais. O arquivo `.terraform.lock.hcl` deve ser versionado quando houver
provedores.

