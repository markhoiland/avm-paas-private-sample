output "resource_group_id" {
  description = "Existing resource group used by the deployment."
  value       = data.azurerm_resource_group.existing.id
}

output "hub_vnet_id" {
  description = "Hub virtual network ID."
  value       = module.hub.resource_id
}

output "spoke_vnet_id" {
  description = "Spoke virtual network ID."
  value       = module.spoke.resource_id
}

output "app_service_plan_id" {
  description = "Linux App Service plan ID."
  value       = module.app_service_plan.resource_id
}

output "app_service_id" {
  description = "Private Linux web app ID."
  value       = module.app.resource_id
}

output "web_app_name" {
  description = "Linux web app name."
  value       = module.app.name
}

output "web_app_default_hostname" {
  description = "Web app default hostname; requires private DNS connectivity."
  value       = module.app.resource_uri
}

output "app_url" {
  description = "Web app URL; only reachable from a connected network with private DNS resolution."
  value       = "https://${module.app.resource_uri}"
}

output "web_app_principal_id" {
  description = "System identity object ID. An Entra SQL admin must separately create a contained database user for this identity and grant least-privilege database permissions."
  value       = module.app.system_assigned_mi_principal_id
}

output "sql_server_id" {
  description = "Entra-only SQL logical server ID."
  value       = module.sql.resource_id
}

output "sql_server_name" {
  description = "Entra-only SQL logical server name."
  value       = module.sql.resource_name
}

output "sql_server_fqdn" {
  description = "SQL hostname; resolves privately from the hub and spoke."
  value       = local.sql_fqdn
}

output "sql_database_id" {
  description = "AdventureWorksLT sample database ID."
  value       = "${module.sql.resource_id}/databases/${local.database_name}"
}

output "database_name" {
  description = "AdventureWorksLT sample database name."
  value       = local.database_name
}

output "sql_connection_string" {
  description = "Secret-free Microsoft.Data.SqlClient managed-identity connection string. Requires separately provisioned database permissions."
  value       = local.sql_connection_string
}

output "private_dns_zone_ids" {
  description = "Private DNS zone IDs, each linked to both virtual networks."
  value       = { for name, zone in module.private_dns : name => zone.resource_id }
}
