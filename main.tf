provider "azurerm" {
  subscription_id = "${var.subscription_id}"
  client_id       = "${var.client_id}"
  client_secret   = "${var.client_secret}"
  tenant_id       = "${var.tenant_id}"
}

# build new resources group
resource "azurerm_resource_group" "turbo-resourcegroup" {
  location = "${var.azure_region}"
  name     = "${var.rg_name}"
}

# create vNet within above SG
resource "azurerm_virtual_network" "turbo-vnet" {
  address_space       = ["10.0.0.0/16"]
  location            = "${azurerm_resource_group.turbo-resourcegroup.location}"
  name                = "turbo-vnet-tf"
  resource_group_name = "${azurerm_resource_group.turbo-resourcegroup.name}"

  tags {
    environment = "turbo-azure"
  }
}

# create subnet
resource "azurerm_subnet" "turbo-subnet" {
  name                 = "turbo-subnet-tf"
  resource_group_name  = "${azurerm_resource_group.turbo-resourcegroup.name}"
  virtual_network_name = "${azurerm_virtual_network.turbo-vnet.name}"
  address_prefix       = "10.0.1.0/24"
}

# create public IP
resource "azurerm_public_ip" "turbopubIP" {
  name                = "turbu_PubIP-tf"
  location            = "${azurerm_resource_group.turbo-resourcegroup.location}"
  resource_group_name = "${azurerm_resource_group.turbo-resourcegroup.name}"
  allocation_method   = "Dynamic"

  tags {
    environment = "turbo-azure"
  }
}

# create Security Group
resource "azurerm_network_security_group" "turbo-sg" {
  name                = "turbo-sg-tf"
  location            = "${azurerm_resource_group.turbo-resourcegroup.location}"
  resource_group_name = "${azurerm_resource_group.turbo-resourcegroup.name}"

  security_rule {
    name                       = "SSH"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "HTTPS"
    priority                   = 1002
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  tags {
    environment = "turbo-azure"
  }
}

# create Virtual NIC for VM
resource "azurerm_network_interface" "turbo-vnic" {
  name                      = "turbo-vnic-tf"
  location                  = "${azurerm_resource_group.turbo-resourcegroup.location}"
  resource_group_name       = "${azurerm_resource_group.turbo-resourcegroup.name}"
  network_security_group_id = "${azurerm_network_security_group.turbo-sg.id}"

  ip_configuration {
    name                          = "turboIPdhcp"
    subnet_id                     = "${azurerm_subnet.turbo-subnet.id}"
    private_ip_address_allocation = "dynamic"
    public_ip_address_id          = "${azurerm_public_ip.turbopubIP.id}"
  }

  tags {
    environment = "turbo-azure"
  }
}

# generate a random string needed for storage account name which must be unique
resource "random_id" "randomId" {
  keepers = {
    # This will generate a new ID only when a new resource group is defined
    resource_group = "${azurerm_resource_group.turbo-resourcegroup.name}"
  }

  byte_length = 8
}

# create Storage Account for boot diagnostics and use the random string (hex)
resource "azurerm_storage_account" "turbo_storageaccount" {
  name                     = "diag${random_id.randomId.hex}"
  resource_group_name      = "${azurerm_resource_group.turbo-resourcegroup.name}"
  location                 = "${azurerm_resource_group.turbo-resourcegroup.location}"
  account_replication_type = "LRS"
  account_tier             = "Standard"

  tags {
    environment = "turbo-azure"
  }
}

# generate Random string for SSH password
resource "random_string" "password" {
  length  = 16
  special = true
}

// provision the Turbonomic VM using the Marketplace Image

resource "azurerm_virtual_machine" "turbonomicvm" {
  name                  = "turbovm${random_id.randomId.hex}"
  location              = "${azurerm_resource_group.turbo-resourcegroup.location}"
  resource_group_name   = "${azurerm_resource_group.turbo-resourcegroup.name}"
  network_interface_ids = ["${azurerm_network_interface.turbo-vnic.id}"]
  vm_size               = "Standard_D3_v2"                                         #4 vcpus 14 GB Mem

  delete_os_disk_on_termination = true

  storage_os_disk {
    name              = "tbnOsDisk${random_id.randomId.hex}"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }

  storage_image_reference {
    publisher = "vmturbo"
    offer     = "turbonomic"
    sku       = "opsmgr"
    version   = "latest"
  }

  plan {
    name      = "opsmgr"
    publisher = "vmturbo"
    product   = "turbonomic"
  }

  os_profile {
    computer_name  = "turbonomic${random_id.randomId.hex}"
    admin_username = "azureuser"
    admin_password = "${random_string.password.result}"    #Random password
  }

  os_profile_linux_config {
    disable_password_authentication = false
  }

  boot_diagnostics {
    enabled     = "true"
    storage_uri = "${azurerm_storage_account.turbo_storageaccount.primary_blob_endpoint}"
  }

  tags {
    environment = "turbo-azure"
  }
}

#output Turbonomic Public IP

data "azurerm_public_ip" "turbo_public_ip" {
  name                = "${azurerm_public_ip.turbopubIP.name}"
  resource_group_name = "${azurerm_virtual_machine.turbonomicvm.resource_group_name}"
}

output "public_ip_address" {
  value = "${data.azurerm_public_ip.turbo_public_ip.ip_address}"
}

# output SSH password
output "ssh password" {
  value = "${random_string.password.result}"
}
