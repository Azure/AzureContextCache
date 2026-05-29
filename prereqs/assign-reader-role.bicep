targetScope = 'subscription'

@description('Object ID of the Microsoft Cognitive Services enterprise application (App ID 7d312290-28c8-473c-a0ed-8e53749b6d6d) in your tenant.')
param principalObjectId string

var readerRoleDefinitionId = 'acdd72a7-3385-48ef-bd42-f606fba81ae7'

resource readerRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, principalObjectId, readerRoleDefinitionId)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', readerRoleDefinitionId)
    principalId: principalObjectId
    principalType: 'ServicePrincipal'
  }
}

output roleAssignmentId string = readerRoleAssignment.id
