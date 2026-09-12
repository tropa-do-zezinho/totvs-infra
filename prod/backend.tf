terraform {
  backend "azurerm" {
    resource_group_name  = "rg-totvs-tfstate"
    storage_account_name = "sttotvstf123456"
    container_name       = "tfstate"
    key                  = "prod.terraform.tfstate"
    use_azuread_auth     = true
  }
}

