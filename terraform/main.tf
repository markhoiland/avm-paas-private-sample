data "azurerm_client_config" "current" {}

data "azurerm_resource_group" "existing" {
  name = var.resource_group_name
}

locals {
  location      = coalesce(var.location, data.azurerm_resource_group.existing.location)
  database_name = "sampledb"
  sql_fqdn      = "${module.sql.resource_name}.database.windows.net"
  # Authentication requires a contained database user for the app identity.
  # Create that user and grant least-privilege permissions separately as the Entra admin.
  sql_connection_string = "Server=tcp:${local.sql_fqdn},1433;Database=${local.database_name};Authentication=Active Directory Managed Identity;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"
}

module "hub" {
  source  = "Azure/avm-res-network-virtualnetwork/azurerm"
  version = "0.22.3"

  name             = "${var.name_prefix}-hub-vnet"
  parent_id        = data.azurerm_resource_group.existing.id
  location         = local.location
  address_space    = ["10.0.0.0/16"]
  enable_telemetry = false
}

module "spoke" {
  source  = "Azure/avm-res-network-virtualnetwork/azurerm"
  version = "0.22.3"

  name             = "${var.name_prefix}-spoke-vnet"
  parent_id        = data.azurerm_resource_group.existing.id
  location         = local.location
  address_space    = ["10.1.0.0/16"]
  enable_telemetry = false

  subnets = {
    integration = {
      name             = "app-integration"
      address_prefixes = ["10.1.1.0/24"]
      delegations = [{
        name = "app-service"
        service_delegation = {
          name = "Microsoft.Web/serverFarms"
        }
      }]
    }
    private_endpoints = {
      name                              = "private-endpoints"
      address_prefixes                  = ["10.1.2.0/24"]
      private_endpoint_network_policies = "Disabled"
    }
  }

  # AVM creates both directions without a cyclic hub/spoke module dependency.
  peerings = {
    hub = {
      name                                 = "spoke-to-hub"
      remote_virtual_network_resource_id   = module.hub.resource_id
      allow_virtual_network_access         = true
      create_reverse_peering               = true
      reverse_name                         = "hub-to-spoke"
      reverse_allow_virtual_network_access = true
    }
  }
}

module "private_dns" {
  source   = "Azure/avm-res-network-privatednszone/azurerm"
  version  = "0.5.0"
  for_each = toset(["privatelink.azurewebsites.net", "privatelink.database.windows.net"])

  domain_name      = each.value
  parent_id        = data.azurerm_resource_group.existing.id
  enable_telemetry = false
  virtual_network_links = {
    hub = {
      name                 = "hub-link"
      virtual_network_id   = module.hub.resource_id
      registration_enabled = false
    }
    spoke = {
      name                 = "spoke-link"
      virtual_network_id   = module.spoke.resource_id
      registration_enabled = false
    }
  }
}

module "app_service_plan" {
  source  = "Azure/avm-res-web-serverfarm/azurerm"
  version = "2.0.8"

  name             = "${var.name_prefix}-plan"
  parent_id        = data.azurerm_resource_group.existing.id
  location         = local.location
  os_type          = "Linux"
  sku_name         = "P1v3"
  worker_count     = 1
  enable_telemetry = false
}

module "sql" {
  source  = "Azure/avm-res-sql-server/azurerm"
  version = "0.2.1"

  name                                  = "${var.name_prefix}-sql"
  resource_group_name                   = data.azurerm_resource_group.existing.name
  location                              = local.location
  server_version                        = "12.0"
  public_network_access_enabled         = false
  generate_administrator_login_password = false
  enable_telemetry                      = false

  azuread_administrator = {
    azuread_authentication_only = true
    login_username              = var.sql_admin_login
    object_id                   = var.sql_admin_object_id
    tenant_id                   = data.azurerm_client_config.current.tenant_id
  }

  databases = {
    sample = {
      name        = local.database_name
      sku_name    = "Basic"
      max_size_gb = 2
      sample_name = "AdventureWorksLT"
    }
  }

  private_endpoints = {
    sql = {
      name                          = "${var.name_prefix}-sql-pe"
      subnet_resource_id            = module.spoke.subnets["private_endpoints"].resource_id
      subresource_name              = "sqlServer"
      private_dns_zone_group_name   = "sql"
      private_dns_zone_resource_ids = [module.private_dns["privatelink.database.windows.net"].resource_id]
    }
  }
}

module "app" {
  source  = "Azure/avm-res-web-site/azurerm"
  version = "0.24.1"

  name                                     = "${var.name_prefix}-app"
  parent_id                                = data.azurerm_resource_group.existing.id
  location                                 = local.location
  kind                                     = "webapp"
  os_type                                  = "Linux"
  service_plan_resource_id                 = module.app_service_plan.resource_id
  https_only                               = true
  public_network_access_enabled            = false
  virtual_network_subnet_id                = module.spoke.subnets["integration"].resource_id
  vnet_route_all_traffic                   = true
  enable_telemetry                         = false
  ftp_publish_basic_authentication_enabled = false
  scm_publish_basic_authentication_enabled = false

  managed_identities = {
    system_assigned = true
  }

  site_config = {
    always_on              = true
    ftps_state             = "Disabled"
    minimum_tls_version    = "1.2"
    vnet_route_all_enabled = true
    application_stack = {
      dotnet = {
        dotnet_version = "10.0"
      }
    }
  }

  connection_strings = {
    database = {
      name  = "DefaultConnection"
      type  = "SQLAzure"
      value = local.sql_connection_string
    }
  }

  private_endpoints = {
    app = {
      name                          = "${var.name_prefix}-app-pe"
      subnet_resource_id            = module.spoke.subnets["private_endpoints"].resource_id
      subresource_name              = "sites"
      private_dns_zone_group_name   = "app"
      private_dns_zone_resource_ids = [module.private_dns["privatelink.azurewebsites.net"].resource_id]
    }
  }
}
