# Private App Service and Azure SQL with Azure Verified Modules

Separate [Bicep](./bicep/) and [Terraform](./terraform/) implementations of the same
hub/spoke sample. All Azure resources are deployed through pinned
[Azure Verified Modules (AVM)](https://azure.github.io/Azure-Verified-Modules/).
Deploy **one** implementation, not both into the same resource group.

## Architecture

```text
Hub VNet (10.0.0.0/16)
    |
    | bidirectional VNet peering
    |
Spoke VNet (10.1.0.0/16)
    |-- App Service integration subnet (delegated to Microsoft.Web/serverFarms)
    |       `-- Linux web app outbound VNet integration
    `-- Private endpoint subnet
            |-- Web app private endpoint (inbound HTTPS)
            `-- Azure SQL private endpoint

Private DNS zones linked to BOTH VNets:
    privatelink.azurewebsites.net
    privatelink.database.windows.net
```

The web app and SQL server have public network access disabled. Private endpoint
DNS zone groups register private addresses; clients continue to use the normal
`<app>.azurewebsites.net` and `<server>.database.windows.net` hostnames. App
Service outbound VNet integration is separate from its inbound private endpoint.
SQL uses Microsoft Entra-only authentication, and the web app has a system-assigned
managed identity. No SQL administrator password is required.

Both implementations use a Linux .NET 10/P1v3 App Service plan and a Basic, 2-GB SQL
database named `sampledb`, initialized with AdventureWorksLT sample data.

This is a networking foundation, not a deployed application. It creates a paid
App Service plan and a sample SQL database but does not deploy application code,
create SQL users, or provide a jump host, VPN, gateway, firewall, or on-premises DNS
forwarder. Peering is not transitive. The hub is a connectivity attachment point,
not an egress inspection appliance. Add routing and connectivity appropriate to
your environment before using this as a production architecture.

## Prerequisites

- An Azure subscription and an **existing resource group**.
- Azure CLI, signed in to the intended subscription.
- A current Bicep CLI for Bicep, or Terraform satisfying the version constraint in
  `terraform/versions.tf` for Terraform.
- Permission to deploy networking, App Service, SQL, and private DNS resources.
  Register `Microsoft.Network`, `Microsoft.Web`, and `Microsoft.Sql` resource
  providers in the subscription if necessary.
- The object ID and display/login name of a Microsoft Entra SQL administrator
  (preferably a group) in the subscription's tenant.
- A short lowercase alphanumeric name prefix that makes web app and SQL server
  names globally unique. Use nonoverlapping address spaces if connecting to an
  existing network.
- A connected client or runner inside the hub/spoke, or reachable through your
  own VPN/ExpressRoute connectivity, to access the private services.

Module downloads and provider installation require internet access. Deployments
incur Azure charges, including App Service, SQL, and private endpoints.

## Deploy with Bicep

From the repository root:

```sh
az login
az account set --subscription '<subscription-id>'
cd bicep
```

Edit `main.bicepparam` with your unique name prefix and Entra administrator
details. The resource group's location is used unless overridden.
Bicep adds a deterministic resource-group-derived suffix to the web app and SQL
server names. Terraform uses your prefix directly, so it must be globally unique.

```sh
az bicep build --file main.bicep --stdout > /dev/null
az deployment group what-if \
  --resource-group '<existing-resource-group>' \
  --template-file main.bicep --parameters main.bicepparam
az deployment group create \
  --resource-group '<existing-resource-group>' \
  --template-file main.bicep --parameters main.bicepparam
```

## Deploy with Terraform

From the repository root:

```sh
az login
az account set --subscription '<subscription-id>'
cd terraform
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your subscription, existing resource group, unique
name prefix, and Entra administrator details.

```sh
terraform init
terraform fmt -check
terraform validate
terraform plan -out=tfplan
terraform apply tfplan
```

Terraform state and saved plans can contain sensitive deployment information.
They are ignored by Git; use a secured remote backend for shared environments.

## Application and database setup

Use the deployment outputs to identify the web app's managed identity and SQL
database. Before deploying your application, connect to the database **as the
configured Entra administrator from a connected private client**, and grant the
web app identity only the database permissions it needs. For example, replace
the name below with the actual web app name:

```sql
CREATE USER [<web-app-name>] FROM EXTERNAL PROVIDER;
ALTER ROLE db_datareader ADD MEMBER [<web-app-name>];
ALTER ROLE db_datawriter ADD MEMBER [<web-app-name>];
```

External-provider user resolution can require additional Microsoft Graph
permissions for the SQL server identity, depending on the administrator and
principal type. Follow
[Azure SQL managed identity guidance](https://learn.microsoft.com/azure/azure-sql/database/authentication-aad-service-principal).
Do not grant broad directory permissions or database-owner access by default.
The supplied connection string uses `Authentication=Active Directory Managed
Identity` and is named `DefaultConnection`; application code must use a compatible
SQL driver, such as a current
`Microsoft.Data.SqlClient`. The infrastructure does not grant SQL data-plane
access automatically.

Deploy application code from a runner with private connectivity: disabling public
access also makes the App Service SCM/deployment endpoint private. The App
Service private DNS zone includes the SCM record through its private endpoint
zone group. Local `terraform validate` and Bicep compilation do not require
private connectivity, but accessing the app and running SQL commands do.

## Verify private connectivity

After deployment, from a client using Azure-provided DNS in either VNet:

```sh
nslookup <app>.azurewebsites.net
nslookup <app>.scm.azurewebsites.net
nslookup <server>.database.windows.net
curl -I https://<app>.azurewebsites.net
```

DNS should resolve through the private-link aliases to private endpoint addresses
in the spoke. An empty web app may return a default page or an application error;
this is not an application readiness test. Test SQL using an Entra-capable SQL
client against `<server>.database.windows.net`, port 1433, with encryption enabled.
Repeat from a public-only client to confirm neither service permits public
data-plane access. ARM management endpoints remain public and use Azure RBAC.

For custom or on-premises DNS, configure conditional forwarding via your own Azure
DNS Private Resolver or DNS forwarder; VNet links alone do not configure external
DNS servers. Review public-network-access settings and approved private endpoint
connections in Azure as well as testing DNS.

## Validation and cleanup

There is no application test suite in this repository. Bicep compilation and
Terraform formatting/validation check local syntax and module/provider contracts;
`what-if`/`plan` and the private-client checks above are required for your target
subscription. Local checks do not prove a successful Azure deployment or runtime
connectivity.

Implementation validation: Terraform initialization, formatting, and validation
passed. This environment could not resolve the MCR artifact-download host for
Bicep module restoration; compilation and linting were instead checked against
the corresponding official tagged AVM sources. Run the native Bicep commands
above in an environment with MCR access before deploying. No live Azure
deployment was performed.

For Terraform, run `terraform destroy` using the same configuration and state.
For Bicep, remove the deployed resources, or delete the resource group **only if
it is dedicated to this sample**. Incremental Bicep deployments do not delete
resources when files are removed. Neither deployment owns the existing resource
group.