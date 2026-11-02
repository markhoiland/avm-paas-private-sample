using './main.bicep'

// Deploy into an existing resource group using:
// From the bicep/ directory:
// az deployment group create --resource-group <resource-group> --parameters main.bicepparam
// Location defaults to the existing resource group's region; optionally set location.
param namePrefix = 'paaspriv'

// Replace these examples with an existing Entra group object ID and display name.
// The conspicuous GUID placeholder is an identifier, not a credential.
param sqlAdminObjectId = '00000000-0000-0000-0000-000000000001'
param sqlAdminLogin = 'REPLACE-WITH-ENTRA-SQL-ADMIN-GROUP'
param sqlAdminPrincipalType = 'Group'
// Tenant defaults to the deployment subscription's tenant; optionally set sqlAdminTenantId.

param linuxFxVersion = 'DOTNETCORE|10.0'
param databaseName = 'sampledb'
param tags = {
  environment: 'sample'
  architecture: 'private-paas'
}

// No application code, SQL database user or database grants are deployed.
// Use a client/deployment agent with connectivity and DNS resolution in either VNet
// for private app/SCM access and SQL user provisioning. No VPN or DNS forwarder is created.
// After authenticating as the Entra SQL administrator, create the app's contained user
// in sampledb and grant only the required database permissions before testing SQL access.
