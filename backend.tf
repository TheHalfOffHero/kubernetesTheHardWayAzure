terraform {
  backend "azurerm" {
    source  = "hashicorp/azurerm"
    version = "~>3.82.0"
  }
}