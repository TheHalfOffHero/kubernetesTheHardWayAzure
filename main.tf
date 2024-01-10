terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~>3.82.0"
    }
  }
}

provider "azurerm" {
  features {
  }
}

resource "azurerm_resource_group" "kubernetes" {
  name = "kubernetes"
  location = var.location
}

resource "azurerm_network_security_group" "kubernetes-nsg" {
  name = "kubernetes-nsg"
  location = var.location
  resource_group_name = azurerm_resource_group.kubernetes.name
  

  # Allow SSH
  security_rule {
    name = "kubernetes-allow-ssh"
    priority = 1000
    direction = "Inbound"
    access = "Allow"
    protocol = "Tcp"
    source_port_range = "*"
    destination_port_range = "22"
    source_address_prefix = "*"
    destination_address_prefix = "*"
  }
  # Allow HTTPS
  security_rule {
    name = "kubernetes-allow-api-server"
    priority = 1001
    direction = "Inbound"
    access = "Allow"
    protocol = "Tcp"
    source_port_range = "*"
    destination_port_range = "6443"
    source_address_prefix = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "kubernetes-subnet-nsg-assosiation" {
  subnet_id = azurerm_subnet.kubernetes-subnet.id
  network_security_group_id = azurerm_network_security_group.kubernetes-nsg.id
}

resource "azurerm_virtual_network" "kubernetes-vnet" {
  name = "kubernetes"
  location = var.location
  resource_group_name = azurerm_resource_group.kubernetes.name
  address_space = [ "10.240.0.0/24" ]
}

resource "azurerm_subnet" "kubernetes-subnet" {
  name = "kubernetes-subnet"
  address_prefixes = [ "10.240.0.0/24" ]
  virtual_network_name = azurerm_virtual_network.kubernetes-vnet.name
  resource_group_name = azurerm_resource_group.kubernetes.name
}

resource "azurerm_public_ip" "kubernetes-pip" {
  name = "kubernetes-pip"
  location = var.location
  resource_group_name = azurerm_resource_group.kubernetes.name
  allocation_method = "Static"
  sku = "Standard"
}

resource "azurerm_lb" "kubernetes-lb" {
  name = "kubernetes-lb"
  location = var.location
  resource_group_name = azurerm_resource_group.kubernetes.name
  sku = "Standard"
  sku_tier = "Regional"

  frontend_ip_configuration {
    name = "kubernetes-lb-ip"
    public_ip_address_id = azurerm_public_ip.kubernetes-pip.id
  }
}

resource "azurerm_lb_backend_address_pool" "kubernetes-lb-pool" {
  name = "kubernetes-lb-pool"
  loadbalancer_id = azurerm_lb.kubernetes-lb.id
}

resource "azurerm_availability_set" "controller-as" {
  name = "controller-as"
  location = var.location
  resource_group_name = azurerm_resource_group.kubernetes.name
}

resource "azurerm_public_ip" "controller-pip" {
  count = var.controller_count

  name = "controller-${count.index}-pip"
  location = var.location
  resource_group_name = azurerm_resource_group.kubernetes.name
  allocation_method = "Static"
  sku = "Standard"
  zones = [ "1" ]
}

resource "azurerm_network_interface" "controller-nic" {
  count = var.controller_count

  name = "controller-${count.index}-nic"
  location = var.location
  resource_group_name = azurerm_resource_group.kubernetes.name
  enable_ip_forwarding = true

  ip_configuration {
      name = "controller-${count.index}-nic-ip"
      subnet_id = azurerm_subnet.kubernetes-subnet.id
      private_ip_address_allocation = "Static"
      private_ip_address = "10.240.0.1${count.index}"
      public_ip_address_id = azurerm_public_ip.controller-pip[count.index].id
      
    }
}

resource "azurerm_network_interface_backend_address_pool_association" "controller-nic-assosiation" {
  count = var.controller_count

  network_interface_id    = azurerm_network_interface.controller-nic[count.index].id
  ip_configuration_name   = azurerm_network_interface.controller-nic[count.index].ip_configuration[0].name
  backend_address_pool_id = azurerm_lb_backend_address_pool.kubernetes-lb-pool.id
}

resource "azurerm_virtual_machine" "controller-vm" {
  count = var.controller_count

  name = "controller-${count.index}"
  resource_group_name = azurerm_resource_group.kubernetes.name
  location = var.location
  network_interface_ids = [ azurerm_network_interface.controller-nic[count.index].id ]
  vm_size = "Standard_B1s"
  availability_set_id = azurerm_availability_set.controller-as.id

  delete_os_disk_on_termination = true
  delete_data_disks_on_termination = true

  storage_image_reference {
    offer = "0001-com-ubuntu-server-focal"
    publisher = "Canonical"
    sku       = "20_04-lts-gen2"
    version   = "latest"
  }
  os_profile {
    computer_name = "controller-${count.index}"
    admin_username = "kuberoot"
    admin_password = "P@ssw0rd123"
  }
  os_profile_linux_config {
    disable_password_authentication = false
    ssh_keys {
      path = "/home/kuberoot/.ssh/authorized_keys"
      key_data = file("~/.ssh/id_rsa.pub")
    }
  }
  storage_os_disk {
    name              = "controller-${count.index}-osdisk"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }
  tags = {
    environment = "dev"
    role = "controller"
    owner = "Matt Ruiz"
  }
}

resource "azurerm_availability_set" "worker-as" {
  name = "worker-as"
  location = var.location
  resource_group_name = azurerm_resource_group.kubernetes.name
}

resource "azurerm_public_ip" "worker-pip" {
  count = var.worker_count

  name = "worker-${count.index}-pip"
  location = var.location
  resource_group_name = azurerm_resource_group.kubernetes.name
  allocation_method = "Static"
  sku = "Standard"
  zones = [ "1" ]
}

resource "azurerm_network_interface" "worker-nic" {
  count = var.worker_count

  name = "worker-${count.index}-nic"
  location = var.location
  resource_group_name = azurerm_resource_group.kubernetes.name
  enable_ip_forwarding = true

  ip_configuration {
      name = "worker-${count.index}-nic-ip"
      subnet_id = azurerm_subnet.kubernetes-subnet.id
      private_ip_address_allocation = "Static"
      private_ip_address = "10.240.0.2${count.index}"
      public_ip_address_id = azurerm_public_ip.worker-pip[count.index].id
      
    }
}

resource "azurerm_network_interface_backend_address_pool_association" "worker-nic-assosiation" {
  count = var.worker_count

  network_interface_id    = azurerm_network_interface.worker-nic[count.index].id
  ip_configuration_name   = azurerm_network_interface.worker-nic[count.index].ip_configuration[0].name
  backend_address_pool_id = azurerm_lb_backend_address_pool.kubernetes-lb-pool.id
}

resource "azurerm_virtual_machine" "worker-vm" {
  count = var.worker_count

  name = "worker-${count.index}"
  resource_group_name = azurerm_resource_group.kubernetes.name
  location = var.location
  network_interface_ids = [ azurerm_network_interface.worker-nic[count.index].id ]
  vm_size = "Standard_B1s"
  availability_set_id = azurerm_availability_set.worker-as.id

  delete_os_disk_on_termination = true
  delete_data_disks_on_termination = true

  storage_image_reference {
    offer = "0001-com-ubuntu-server-focal"
    publisher = "Canonical"
    sku       = "20_04-lts-gen2"
    version   = "latest"
  }
  os_profile {
    computer_name = "worker-${count.index}"
    admin_username = "kuberoot"
    admin_password = "P@ssw0rd123"
  }
  os_profile_linux_config {
    disable_password_authentication = false
    ssh_keys {
      path = "/home/kuberoot/.ssh/authorized_keys"
      key_data = file("~/.ssh/id_rsa.pub")
    }
  }
  storage_os_disk {
    name              = "worker-${count.index}-osdisk"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }
  tags = {
    environment = "dev"
    role = "worker"
    owner = "Matt Ruiz"
  }
}