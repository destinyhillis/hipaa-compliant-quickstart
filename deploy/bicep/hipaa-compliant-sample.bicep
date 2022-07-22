param resourcePrefix string

param resourceTags object = {}
param location string = resourceGroup().location

var simpleResourcePrefix = replace(resourcePrefix, '-', '')

var storageRoleDefinitions = [
  resourceId('microsoft.authorization/roleDefinitions', 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b') // storage blob data owner, req'd for web jobs storage
  resourceId('microsoft.authorization/roleDefinitions', '17d1049b-9a84-46fb-8f53-869881c3d3ab') // storage account contributor, req'd for web jobs storage
  resourceId('microsoft.authorization/roleDefinitions', '974c5e8b-45b9-4653-ba55-5f855dd0fb88') // storage queue data contributor, req'd for web jobs storage
  resourceId('microsoft.authorization/roleDefinitions', '19e7f393-937e-4f77-808e-94535e297925') // storage queue data reader, req'd for input trigger
  resourceId('microsoft.authorization/roleDefinitions', '8a0f0c08-91a1-4084-bc3d-661d67233fed') // storage queue data message processor, req'd for input trigger
  resourceId('microsoft.authorization/roleDefinitions', 'c6a89b2d-59bc-44d0-9896-0f6e12d7b80a') // storage queue data message sender, req'd for output
]

var vnetAddressSpace = '10.1.0.0/16'
var subnetDefaultAddressPrefix = '10.1.0.0/24'
var subnetName = 'default'

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2020-11-01' = {
  name: '${simpleResourcePrefix}vnet'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressSpace
      ]
    }
    subnets: [
      {
        name: subnetName
        properties: {
          addressPrefix: subnetDefaultAddressPrefix
          networkSecurityGroup: {
            id: networkSecurityGroup.id
          }
          serviceEndpoints: [
            {
              service: 'Microsoft.Storage'
              locations: [
                location
              ]
            }
          ]
          delegations: [
            {
              name: 'delegation'
              properties: {
                serviceName: 'Microsoft.Web/serverfarms'
              }
            }
          ]
        }
      }
    ]
  }
}

resource networkSecurityGroup 'Microsoft.Network/networkSecurityGroups@2020-11-01' = {
  name: '${simpleResourcePrefix}nsg'
  location: location
  properties: {
    securityRules: []
  }
}

resource funcFarm 'Microsoft.Web/serverfarms@2021-03-01' = {
  name: '${resourcePrefix}-funcasp'
  location: location
  properties: {
    reserved: true
  }
  sku: {
    name: 'B1'
  }
  kind: 'functionapp'
}

resource functionApp 'Microsoft.Web/sites@2020-12-01' = {
  name: '${resourcePrefix}-func'
  kind: 'functionapp'
  location: location
  properties: {
    enabled: true
    serverFarmId: funcFarm.id
    reserved: true
    siteConfig: {
      detailedErrorLoggingEnabled: false
      vnetRouteAllEnabled: true

      ftpsState: 'Disabled'
      http20Enabled: true

      minTlsVersion: '1.2'
      scmMinTlsVersion: '1.2'
      minimumElasticInstanceCount: 1
    }
    hostNamesDisabled: true
    httpsOnly: true
  }
  identity: {
    type: 'SystemAssigned'
  }
  dependsOn: [
    virtualNetwork
  ]
}

resource functionApp_virtualNetwork 'Microsoft.Web/sites/networkConfig@2021-02-01' = {
  parent: functionApp
  name: 'virtualNetwork'
  properties: {
    subnetResourceId: resourceId('Microsoft.Network/virtualNetworks/subnets', virtualNetwork.name, subnetName)
    swiftSupported: true
  }
}

resource storageRole 'Microsoft.Authorization/roleAssignments@2020-04-01-preview' = [for roleId in storageRoleDefinitions: {
  scope: storageAccount
  name: guid(storageAccount.id, functionApp.id, roleId)
  properties: {
    roleDefinitionId: roleId
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}]

resource storageAccount 'Microsoft.Storage/storageAccounts@2021-08-01' = {
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  name: simpleResourcePrefix
  location: location
  tags: resourceTags
  properties: {
    defaultToOAuthAuthentication: false
    allowCrossTenantReplication: true
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: true
    allowSharedKeyAccess: true
    networkAcls: {
      bypass: 'AzureServices'
      virtualNetworkRules: [
        {
          id: resourceId('Microsoft.Network/VirtualNetworks/subnets', virtualNetwork.name, subnetName)
          action: 'Allow'
          state: 'Succeeded'
        }
      ]
      defaultAction: 'Deny'
    }
    supportsHttpsTrafficOnly: true
    encryption: {
      requireInfrastructureEncryption: false
      services: {
        file: {
          keyType: 'Account'
          enabled: true
        }
        blob: {
          keyType: 'Account'
          enabled: true
        }
      }
      keySource: 'Microsoft.Storage'
    }
    accessTier: 'Hot'
  }
}

resource saDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: '${simpleResourcePrefix}-sa-diagnostics'
  scope: storageAccount
  properties: {
    metrics: [
      {
        category: 'Transaction'
        enabled: true
        retentionPolicy: {
          days: 7
          enabled: true
        }
        timeGrain: 'YYYY-MM-DD'
      }
    ]
    storageAccountId: storageAccount.id
  }
}

resource vnetDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: '${simpleResourcePrefix}-vnet-diagnostics'
  scope: virtualNetwork
  properties: {
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
        retentionPolicy: {
          days: 7
          enabled: true
        }
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
        retentionPolicy: {
          days: 7
          enabled: true
        }
        timeGrain: 'YYYY-MM-DD'
      }
    ]
    storageAccountId: storageAccount.id
  }
}

resource nsgDiagnostics 'microsoft.insights/diagnosticSettings@2021-05-01-preview' = {
  scope: networkSecurityGroup
  name: '${simpleResourcePrefix}-nsg-diagnostics'
  properties: {
    storageAccountId: storageAccount.id
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
        retentionPolicy: {
          days: 7
          enabled: true
        }
      }
    ]
  }
}
