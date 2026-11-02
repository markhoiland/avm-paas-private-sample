targetScope = 'resourceGroup'

@description('Azure region for the networks, App Service and SQL server.')
param location string = resourceGroup().location

@description('Short lowercase alphanumeric naming prefix. Globally unique service names also include a resource-group-derived suffix.')
@minLength(3)
@maxLength(12)
param namePrefix string = 'paaspriv'

@description('Object ID of the existing Microsoft Entra SQL administrator. Not the application/client ID.')
@minLength(36)
@maxLength(36)
param sqlAdminObjectId string

@description('Display name or login of the existing Microsoft Entra SQL administrator.')
@minLength(1)
param sqlAdminLogin string

@description('Tenant containing the Microsoft Entra SQL administrator.')
param sqlAdminTenantId string = subscription().tenantId

@description('Principal type of the existing Microsoft Entra SQL administrator.')
@allowed([
  'Application'
  'Group'
  'User'
])
param sqlAdminPrincipalType string = 'Group'

@description('Supported Linux App Service runtime. Deploy application code separately.')
param linuxFxVersion string = 'DOTNETCORE|10.0'

@description('Name of the sample Azure SQL database.')
param databaseName string = 'sampledb'

@description('Tags applied to the deployed resources.')
param tags object = {}

var suffix = uniqueString(subscription().subscriptionId, resourceGroup().id)
var integrationSubnetName = 'app-integration'
var privateEndpointSubnetName = 'private-endpoints'

module hub 'br/public:avm/res/network/virtual-network:0.7.2' = {
  name: 'hub-network'
  params: {
    name: '${namePrefix}-hub-vnet'
    location: location
    addressPrefixes: [
      '10.0.0.0/16'
    ]
    tags: tags
    enableTelemetry: false
  }
}

// The spoke module creates both peerings after the hub exists, avoiding a dependency cycle.
module spoke 'br/public:avm/res/network/virtual-network:0.7.2' = {
  name: 'spoke-network'
  params: {
    name: '${namePrefix}-spoke-vnet'
    location: location
    addressPrefixes: [
      '10.1.0.0/16'
    ]
    subnets: [
      {
        name: integrationSubnetName
        addressPrefix: '10.1.1.0/24'
        delegation: 'Microsoft.Web/serverFarms'
      }
      {
        name: privateEndpointSubnetName
        addressPrefix: '10.1.2.0/24'
        privateEndpointNetworkPolicies: 'Disabled'
      }
    ]
    peerings: [
      {
        name: 'spoke-to-hub'
        remoteVirtualNetworkResourceId: hub.outputs.resourceId
        allowVirtualNetworkAccess: true
        allowForwardedTraffic: false
        allowGatewayTransit: false
        useRemoteGateways: false
        remotePeeringEnabled: true
        remotePeeringName: 'hub-to-spoke'
        remotePeeringAllowVirtualNetworkAccess: true
        remotePeeringAllowForwardedTraffic: false
        remotePeeringAllowGatewayTransit: false
        remotePeeringUseRemoteGateways: false
      }
    ]
    tags: tags
    enableTelemetry: false
  }
}

var integrationSubnetResourceId = '${spoke.outputs.resourceId}/subnets/${integrationSubnetName}'
var privateEndpointSubnetResourceId = '${spoke.outputs.resourceId}/subnets/${privateEndpointSubnetName}'
var dnsLinks = [
  {
    name: 'hub-link'
    virtualNetworkResourceId: hub.outputs.resourceId
    registrationEnabled: false
  }
  {
    name: 'spoke-link'
    virtualNetworkResourceId: spoke.outputs.resourceId
    registrationEnabled: false
  }
]

module appPrivateDns 'br/public:avm/res/network/private-dns-zone:0.8.0' = {
  name: 'app-private-dns'
  params: {
    name: 'privatelink.azurewebsites.net'
    virtualNetworkLinks: dnsLinks
    tags: tags
    enableTelemetry: false
  }
}

module sqlPrivateDns 'br/public:avm/res/network/private-dns-zone:0.8.0' = {
  name: 'sql-private-dns'
  params: {
    name: 'privatelink.${environment().suffixes.sqlServerHostname}'
    virtualNetworkLinks: dnsLinks
    tags: tags
    enableTelemetry: false
  }
}

module servicePlan 'br/public:avm/res/web/serverfarm:0.7.0' = {
  name: 'linux-service-plan'
  params: {
    name: '${namePrefix}-plan'
    location: location
    kind: 'linux'
    reserved: true
    skuName: 'P1v3'
    skuCapacity: 1
    zoneRedundant: false
    tags: tags
    enableTelemetry: false
  }
}

module sql 'br/public:avm/res/sql/server:0.20.0' = {
  name: 'private-sql'
  params: {
    name: '${namePrefix}-sql-${suffix}'
    location: location
    publicNetworkAccess: 'Disabled'
    minimalTlsVersion: '1.2'
    administrators: {
      administratorType: 'ActiveDirectory'
      azureADOnlyAuthentication: true
      login: sqlAdminLogin
      principalType: sqlAdminPrincipalType
      sid: sqlAdminObjectId
      tenantId: sqlAdminTenantId
    }
    databases: [
      {
        name: databaseName
        availabilityZone: -1
        sku: {
          name: 'Basic'
          tier: 'Basic'
          capacity: 5
        }
        maxSizeBytes: 2147483648
        sampleName: 'AdventureWorksLT'
        requestedBackupStorageRedundancy: 'Local'
        zoneRedundant: false
        tags: tags
      }
    ]
    privateEndpoints: [
      {
        name: '${namePrefix}-sql-pe'
        location: location
        service: 'sqlServer'
        subnetResourceId: privateEndpointSubnetResourceId
        privateDnsZoneGroup: {
          name: 'default'
          privateDnsZoneGroupConfigs: [
            {
              name: 'sql'
              privateDnsZoneResourceId: sqlPrivateDns.outputs.resourceId
            }
          ]
        }
      }
    ]
    tags: tags
    enableTelemetry: false
  }
}

// Microsoft.Data.SqlClient uses the system-assigned identity; this contains no password.
// An Entra administrator must separately CREATE USER ... FROM EXTERNAL PROVIDER in
// sampledb and grant least-privilege permissions. Infrastructure does not create that user.
var sqlConnectionString = 'Server=tcp:${sql.outputs.fullyQualifiedDomainName},1433;Database=${databaseName};Authentication=Active Directory Managed Identity;Encrypt=True;TrustServerCertificate=False;'

module app 'br/public:avm/res/web/site:0.19.0' = {
  name: 'private-web-app'
  params: {
    name: '${namePrefix}-app-${suffix}'
    location: location
    kind: 'app,linux'
    serverFarmResourceId: servicePlan.outputs.resourceId
    managedIdentities: {
      systemAssigned: true
    }
    httpsOnly: true
    publicNetworkAccess: 'Disabled'
    virtualNetworkSubnetResourceId: integrationSubnetResourceId
    outboundVnetRouting: {
      allTraffic: true
    }
    siteConfig: {
      linuxFxVersion: linuxFxVersion
      alwaysOn: true
      minTlsVersion: '1.2'
      scmMinTlsVersion: '1.2'
      ftpsState: 'Disabled'
      vnetRouteAllEnabled: true
      connectionStrings: [
        {
          name: 'DefaultConnection'
          type: 'SQLAzure'
          connectionString: sqlConnectionString
        }
      ]
    }
    basicPublishingCredentialsPolicies: [
      {
        name: 'ftp'
        allow: false
      }
      {
        name: 'scm'
        allow: false
      }
    ]
    privateEndpoints: [
      {
        name: '${namePrefix}-app-pe'
        location: location
        service: 'sites'
        subnetResourceId: privateEndpointSubnetResourceId
        privateDnsZoneGroup: {
          name: 'default'
          privateDnsZoneGroupConfigs: [
            {
              name: 'app'
              privateDnsZoneResourceId: appPrivateDns.outputs.resourceId
            }
          ]
        }
      }
    ]
    tags: tags
    enableTelemetry: false
  }
}

output hubVirtualNetworkResourceId string = hub.outputs.resourceId
output spokeVirtualNetworkResourceId string = spoke.outputs.resourceId
output appIntegrationSubnetResourceId string = integrationSubnetResourceId
output privateEndpointSubnetId string = privateEndpointSubnetResourceId
output appResourceId string = app.outputs.resourceId
output webAppName string = app.outputs.name
output webAppDefaultHostName string = app.outputs.defaultHostname
output appUrl string = 'https://${app.outputs.defaultHostname}'
@description('Use this object ID when provisioning the database user; no database permissions have been granted by this deployment.')
output webAppPrincipalId string = app.outputs.systemAssignedMIPrincipalId!
output sqlServerResourceId string = sql.outputs.resourceId
output sqlServerName string = sql.outputs.name
output sqlServerFqdn string = sql.outputs.fullyQualifiedDomainName
output databaseName string = databaseName
output sqlDatabaseResourceId string = '${sql.outputs.resourceId}/databases/${databaseName}'
output privateDnsZoneResourceIds object = {
  app: appPrivateDns.outputs.resourceId
  sql: sqlPrivateDns.outputs.resourceId
}
output appPrivateEndpoints array = app.outputs.privateEndpoints
output sqlPrivateEndpoints array = sql.outputs.privateEndpoints
