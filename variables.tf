# variables for Azure access using service principle and client secret
variable subscription_id {}
variable client_id {}
variable client_secret {}
variable tenant_id {}

# Azure Region to create all resources into
variable "azure_region" {
  description = "Azure Region in which all resources will be deployed to"
  type    = "string"
  default = "Canada East"
}

variable "rg_name" {
  default = "turbonomic-rg-tf"
}
