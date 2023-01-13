/* 
Copyright 2022 Dynatrace LLC

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    https://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

// Parameters
// Azure Region
param location string = resourceGroup().location
// Dynatrace AccessToken with events.ingest permission
@secure()
param dynatraceAccessToken string 
// Dynatrace Environment URL
param dynatraceEnvironmentUrl string

// Load entity mappings from external file - https://docs.microsoft.com/en-us/azure/service-health/resource-health-checks-resource-types
var entityMappings = json(loadTextContent('entity-mappings.json'))
var dynatraceConectionName = 'dynatrace'

resource dynatraceConnection 'Microsoft.Web/connections@2016-06-01' = {
  name: dynatraceConectionName
  location: location
  kind: 'V1'
  properties: {
    displayName: dynatraceConectionName
    parameterValues: {

    }
    nonSecretParameterValues: {
      tenantUrl: dynatraceEnvironmentUrl
    }
    api: {
      id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location,'dynatrace')
    }
  }
}

// Azure ServiceHealth Logic App
resource serviceHealthLogicApp 'Microsoft.Logic/workflows@2019-05-01' = {
  name: 'dt-forward-servicehealth'
  location: location
  properties: {
    state: 'Enabled'
    definition: {
      '$schema': 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#'
      contentVersion: '1.0.0.0'
      parameters: {
        '$connections': {
          defaultValue: {}
          type: 'Object'
        }
      }
      triggers: {
        manual: {
          type: 'Request'
          kind: 'Http'
          inputs: {
            schema: {
              properties: {
                data: {
                  properties: {
                    context: {
                      properties: {
                        activityLog: {
                          properties: {
                            channels: {
                              type: 'string'
                            }
                            correlationId: {
                              type: 'string'
                            }
                            description: {
                              type: 'string'
                            }
                            eventDataId: {
                              type: 'string'
                            }
                            eventSource: {
                              type: 'string'
                            }
                            eventTimestamp: {
                              type: 'string'
                            }
                            level: {
                              type: 'string'
                            }
                            operationId: {
                              type: 'string'
                            }
                            operationName: {
                              type: 'string'
                            }
                            properties: {
                              properties: {
                                communication: {
                                  type: 'string'
                                }
                                communicationId: {
                                  type: 'string'
                                }
                                defaultLanguageContent: {
                                  type: 'string'
                                }
                                defaultLanguageTitle: {
                                  type: 'string'
                                }
                                impactStartTime: {
                                  type: 'string'
                                }
                                impactedServices: {
                                  type: 'string'
                                }
                                incidentType: {
                                  type: 'string'
                                }
                                region: {
                                  type: 'string'
                                }
                                service: {
                                  type: 'string'
                                }
                                stage: {
                                  type: 'string'
                                }
                                title: {
                                  type: 'string'
                                }
                                trackingId: {
                                  type: 'string'
                                }
                                version: {
                                  type: 'string'
                                }
                              }
                              type: 'object'
                            }
                            status: {
                              type: 'string'
                            }
                            submissionTimestamp: {
                              type: 'string'
                            }
                            subscriptionId: {
                              type: 'string'
                            }
                          }
                          type: 'object'
                        }
                      }
                      type: 'object'
                    }
                    properties: {
                      properties: {
                      }
                      type: 'object'
                    }
                    status: {
                      type: 'string'
                    }
                  }
                  type: 'object'
                }
                schemaId: {
                  type: 'string'
                }
              }
              type: 'object'
            }
          }
          conditions: [
            {
              expression: '@not(empty(triggerBody())) '
            }
            {
              expression: '@and(equals(triggerBody()?[\'schemaId\'],\'Microsoft.Insights/activityLogs\'),equals(triggerBody()?[\'data\']?[\'context\']?[\'activityLog\']?[\'eventSource\'],\'ServiceHealth\'),equals(triggerBody()?[\'data\']?[\'context\']?[\'activityLog\']?[\'properties\']?[\'version\'],string(\'0.1.1\')))'
            }
          ]
        }
      }
      actions: {
        Compose_Properties: {
          runAfter: {
            Set_Subscription_Entity_Selector: [
              'Succeeded'
            ]
          }
          type: 'Compose'
          inputs: {
            impactStartTime: '@triggerBody()?[\'data\']?[\'context\']?[\'activityLog\']?[\'properties\']?[\'impactStartTime\']'
            incidentType: '@triggerBody()?[\'data\']?[\'context\']?[\'activityLog\']?[\'properties\']?[\'incidentType\']'
            region: '@triggerBody()?[\'data\']?[\'context\']?[\'activityLog\']?[\'properties\']?[\'region\']'
            service: '@triggerBody()?[\'data\']?[\'context\']?[\'activityLog\']?[\'properties\']?[\'service\']'
          }
        }
        Compose_Resource_Mapping_JSON: {
          runAfter: {
            Parse_Impacted_Services: [
              'Succeeded'
            ]
          }
          type: 'Compose'
          inputs: entityMappings
        }
        Filter_failed_subscription_events: {
          runAfter: {
            Ingest_Subscription_Health_Alert: [
              'Succeeded'
            ]
          }
          type: 'Query'
          inputs: {
            from: '@body(\'Ingest_Subscription_Health_Alert\')?[\'eventIngestResults\']'
            where: '@not(equals(item()?[\'status\'], \'OK\'))'
          }
        }
        For_each_Impacted_Service: {
          foreach: '@body(\'Parse_Impacted_Services\')'
          actions: {
            Condition_Exists_Mapped_Entity: {
              actions: {
                For_each_Impacted_Region: {
                  foreach: '@items(\'For_each_Impacted_Service\')[\'ImpactedRegions\']'
                  actions: {
                    Filter_failed_service_events: {
                      runAfter: {
                        Ingest_Service_Health_Alert: [
                          'Succeeded'
                        ]
                      }
                      type: 'Query'
                      inputs: {
                        from: '@body(\'Ingest_Service_Health_Alert\')?[\'eventIngestResults\']'
                        where: '@not(equals(item()?[\'status\'], \'OK\'))'
                      }
                    }
                    Has_Ingest_Service_Health_Alert_Failed: {
                      actions: {
                        Set_Ingest_Service_Health_Alert_failed: {
                          runAfter: {
                          }
                          type: 'SetVariable'
                          inputs: {
                            name: 'succeeded'
                            value: false
                          }
                        }
                      }
                      runAfter: {
                        Filter_failed_service_events: [
                          'Succeeded'
                        ]
                      }
                      expression: {
                        or: [
                          {
                            greater: [
                              '@length(body(\'Filter_failed_service_events\'))'
                              0
                            ]
                          }
                        ]
                      }
                      type: 'If'
                    }
                    Ingest_Service_Health_Alert: {
                      runAfter: {
                        Set_Service_Entity_Selector: [
                          'Succeeded'
                        ]
                      }
                      type: 'ApiConnection'
                      inputs: {
                        body: {
                          entitySelector: '@variables(\'entitySelector\')'
                          eventType: '@variables(\'eventType\')'
                          properties: '@triggerBody()?[\'data\']?[\'context\']?[\'activityLog\']?[\'properties\']'
                          startTime: '@{variables(\'startTimeInMs\')}'
                          timeout: 1440
                          title: '@triggerBody()?[\'data\']?[\'context\']?[\'activityLog\']?[\'properties\']?[\'title\']'
                        }
                        headers: {
                          'Content-Type': 'application/json;charset=utf-8'
                        }
                        host: {
                          connection: {
                            name: '@parameters(\'$connections\')[\'dynatrace\'][\'connectionId\']'
                          }
                        }
                        method: 'post'
                        path: '/api/v2/events/ingest'
                        uri: '@{parameters(\'EnvironmentUrl\')}/api/v2/events/ingest'
                      }
                    }
                    Set_Service_Entity_Selector: {
                      runAfter: {
                      }
                      type: 'SetVariable'
                      inputs: {
                        name: 'entitySelector'
                        value: 'type("@{first(body(\'Map_Resource_to_Entity\'))[\'entityType\']}"), fromRelationships.isAccessibleBy(type("AZURE_SUBSCRIPTION"), azureSubscriptionUuid("@{triggerBody()?[\'data\']?[\'context\']?[\'activityLog\']?[\'subscriptionId\']}")), toRelationships.isSiteOf(type("AZURE_REGION"),detectedName("@{replace(toLower(items(\'For_each_Impacted_Region\')[\'RegionName\']),\' \',\'\')}"))'
                      }
                    }
                  }
                  runAfter: {
                  }
                  type: 'Foreach'
                }
              }
              runAfter: {
                Map_Resource_to_Entity: [
                  'Succeeded'
                ]
              }
              expression: {
                and: [
                  {
                    greater: [
                      '@length(body(\'Map_Resource_to_Entity\'))'
                      0
                    ]
                  }
                ]
              }
              type: 'If'
            }
            Map_Resource_to_Entity: {
              runAfter: {
              }
              type: 'Query'
              inputs: {
                from: '@body(\'Parse_Resource_Mapping_Array\')?[\'EntityMappings\']'
                where: '@equals(item()?[\'ServiceName\'], items(\'For_each_Impacted_Service\')[\'ServiceName\'])'
              }
            }
          }
          runAfter: {
            Parse_Resource_Mapping_Array: [
              'Succeeded'
            ]
          }
          type: 'Foreach'
        }
        Has_Ingest_Subscription_Health_Alert_Failed: {
          actions: {
            Set_Ingest_Subscription_Health_Alert_failed: {
              runAfter: {
              }
              type: 'SetVariable'
              inputs: {
                name: 'succeeded'
                value: false
              }
            }
          }
          runAfter: {
            Filter_failed_subscription_events: [
              'Succeeded'
            ]
          }
          expression: {
            or: [
              {
                greater: [
                  '@length(body(\'Filter_failed_subscription_events\'))'
                  0
                ]
              }
            ]
          }
          type: 'If'
        }
        Have_one_or_more_ingested_events_failed: {
          actions: {
            One_or_more_events_were_not_successfully_ingested: {
              runAfter: {
              }
              type: 'Terminate'
              inputs: {
                runStatus: 'Failed'
              }
            }
          }
          runAfter: {
            For_each_Impacted_Service: [
              'Succeeded'
            ]
          }
          expression: {
            and: [
              {
                not: {
                  equals: [
                    '@variables(\'succeeded\')'
                    true
                  ]
                }
              }
            ]
          }
          type: 'If'
        }
        Ingest_Subscription_Health_Alert: {
          runAfter: {
            Compose_Properties: [
              'Succeeded'
            ]
          }
          type: 'ApiConnection'
          inputs: {
            body: {
              entitySelector: '@variables(\'entitySelector\')'
              eventType: '@variables(\'eventType\')'
              properties: '@outputs(\'Compose_Properties\')'
              startTime: '@{variables(\'startTimeInMs\')}'
              timeout: 1440
              title: '@triggerBody()?[\'data\']?[\'context\']?[\'activityLog\']?[\'properties\']?[\'title\']'
            }
            headers: {
              'Content-Type': 'application/json;charset=utf-8'
            }
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'dynatrace\'][\'connectionId\']'
              }
            }
            method: 'post'
            path: '/api/v2/events/ingest'
          }
        }
        Initialize_Succeeded: {
          runAfter: {
            Initialize_eventType: [
              'Succeeded'
            ]
          }
          type: 'InitializeVariable'
          inputs: {
            variables: [
              {
                name: 'succeeded'
                type: 'boolean'
                value: true
              }
            ]
          }
        }
        Initialize_entitySelector: {
          runAfter: {
            Initialize_startTimeInMs: [
              'Succeeded'
            ]
          }
          type: 'InitializeVariable'
          inputs: {
            variables: [
              {
                name: 'entitySelector'
                type: 'string'
              }
            ]
          }
        }
        Initialize_eventType: {
          runAfter: {
            Initialize_entitySelector: [
              'Succeeded'
            ]
          }
          type: 'InitializeVariable'
          inputs: {
            variables: [
              {
                name: 'eventType'
                type: 'string'
              }
            ]
          }
        }
        Initialize_startTimeInMs: {
          runAfter: {
          }
          type: 'InitializeVariable'
          inputs: {
            variables: [
              {
                name: 'startTimeInMs'
                type: 'integer'
                value: '@div(sub(ticks(triggerBody()?[\'data\']?[\'context\']?[\'activityLog\']?[\'properties\']?[\'impactStartTime\']),ticks(\'1970-01-01\')),10000)'
              }
            ]
          }
        }
        Parse_Impacted_Services: {
          runAfter: {
            Has_Ingest_Subscription_Health_Alert_Failed: [
              'Succeeded'
            ]
          }
          type: 'ParseJson'
          inputs: {
            content: '@triggerBody()?[\'data\']?[\'context\']?[\'activityLog\']?[\'properties\']?[\'impactedServices\']'
            schema: {
              items: {
                properties: {
                  ImpactedRegions: {
                    items: {
                      properties: {
                        RegionName: {
                          type: 'string'
                        }
                      }
                      required: [
                        'RegionName'
                      ]
                      type: 'object'
                    }
                    type: 'array'
                  }
                  ServiceName: {
                    type: 'string'
                  }
                }
                required: [
                  'ImpactedRegions'
                  'ServiceName'
                ]
                type: 'object'
              }
              type: 'array'
            }
          }
        }
        Parse_Resource_Mapping_Array: {
          runAfter: {
            Compose_Resource_Mapping_JSON: [
              'Succeeded'
            ]
          }
          type: 'ParseJson'
          inputs: {
            content: '@outputs(\'Compose_Resource_Mapping_JSON\')'
            schema: {
              properties: {
                EntityMappings: {
                  items: {
                    properties: {
                      EntityType: {
                        type: 'string'
                      }
                      ResourceType: {
                        type: 'string'
                      }
                      ServiceName: {
                        type: 'string'
                      }
                      isGenericType: {
                        type: 'boolean'
                      }
                      selectorType: {
                        type: 'string'
                      }
                    }
                    required: [
                      'EntityType'
                      'ServiceName'
                      'ResourceType'
                      'isGenericType'
                      'selectorType'
                    ]
                    type: 'object'
                  }
                  type: 'array'
                }
              }
              type: 'object'
            }
          }
        }
        Set_Subscription_Entity_Selector: {
          runAfter: {
            Switch_Event_Type: [
              'Succeeded'
            ]
          }
          type: 'SetVariable'
          inputs: {
            name: 'entitySelector'
            value: 'type("AZURE_SUBSCRIPTION"), azureSubscriptionUuid("@{triggerBody()?[\'data\']?[\'context\']?[\'activityLog\']?[\'subscriptionId\']}")'
          }
        }
        Switch_Event_Type: {
          runAfter: {
            Initialize_Succeeded: [
              'Succeeded'
            ]
          }
          cases: {
            Case_Action_Required: {
              case: 'ActionRequired'
              actions: {
                Set_Action_Required_Type: {
                  runAfter: {
                  }
                  type: 'SetVariable'
                  inputs: {
                    name: 'eventType'
                    value: 'ERROR_EVENT'
                  }
                }
              }
            }
            Case_Incident: {
              case: 'Incident'
              actions: {
                Set_Incident_Type: {
                  runAfter: {
                  }
                  type: 'SetVariable'
                  inputs: {
                    name: 'eventType'
                    value: 'ERROR_EVENT'
                  }
                }
              }
            }
            Case_Informational: {
              case: 'Informational'
              actions: {
                Set_Informational_Type: {
                  runAfter: {
                  }
                  type: 'SetVariable'
                  inputs: {
                    name: 'eventType'
                    value: 'CUSTOM_INFO'
                  }
                }
              }
            }
            Case_Maintenance: {
              case: 'Maintenance'
              actions: {
                Set_Maintenance_Type: {
                  runAfter: {
                  }
                  type: 'SetVariable'
                  inputs: {
                    name: 'eventType'
                    value: 'CUSTOM_INFO'
                  }
                }
              }
            }
            Case_Security: {
              case: 'Security'
              actions: {
                Set_Security_Type: {
                  runAfter: {
                  }
                  type: 'SetVariable'
                  inputs: {
                    name: 'eventType'
                    value: 'CUSTOM_INFO'
                  }
                }
              }
            }
          }
          default: {
            actions: {
              Set_Default_Type: {
                runAfter: {
                }
                type: 'SetVariable'
                inputs: {
                  name: 'eventType'
                  value: 'ERROR_EVENT'
                }
              }
            }
          }
          expression: '@triggerBody()?[\'data\']?[\'context\']?[\'activityLog\']?[\'properties\']?[\'incidentType\']'
          type: 'Switch'
        }
      }
      outputs: {
      }
    }
    parameters: {
      '$connections': {
        value: {
          dynatrace: {
            connectionId: dynatraceConnection.id
            connectionName: dynatraceConnection.name
            id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location,'dynatrace')
          }
        }
      }
    }
  }
}

// Azure ServiceHealth Action Group
resource serviceHealthActionGroup 'microsoft.insights/actionGroups@2021-09-01' = {
  name: 'dt-forward-servicehealth'
  location: 'Global'
  tags: {}
  properties: {
    groupShortName: 'dt-svc-hlth'
    enabled: true
    emailReceivers: []
    smsReceivers: []
    webhookReceivers: []
    eventHubReceivers: []
    itsmReceivers: []
    azureAppPushReceivers: []
    automationRunbookReceivers: []
    voiceReceivers: []
    logicAppReceivers: [
      {
        name: 'dt-forward-servicehealth'
        resourceId: serviceHealthLogicApp.id
        callbackUrl: listCallbackURL('${serviceHealthLogicApp.id}/triggers/manual', serviceHealthLogicApp.apiVersion).value
        useCommonAlertSchema: false
      }
    ]
    azureFunctionReceivers: []
    armRoleReceivers: []
  }
}

// Azure ServiceHealth Alert
resource serviceHealthActivityLogAlerts 'microsoft.insights/activityLogAlerts@2020-10-01' = {
  name: 'dt-forward-servicehealth'
  location: 'Global'
  tags: {}
  properties: {
    scopes: [
      subscription().id
    ]
    condition: {
      allOf: [
        {
          field: 'category'
          equals: 'ServiceHealth'
        }
        {
          field: 'properties.impactedServices[*].ImpactedRegions[*].RegionName'
          containsAny: [
            'Global'
          ]
        }
      ]
    }
    actions: {
      actionGroups: [
        {
          actionGroupId: serviceHealthActionGroup.id
          webhookProperties: {}
        }
      ]
    }
    enabled: true
  }
}

// Azure ResourceHealth Logic App
resource resourceHealthLogicApp 'Microsoft.Logic/workflows@2019-05-01' = {
  name: 'dt-forward-resourcehealth'
  location: location
  properties: {
    state: 'Enabled'
    definition: {
      '$schema': 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#'
      contentVersion: '1.0.0.0'
      parameters: {
        '$connections': {
          defaultValue: {}
          type: 'Object'
        }
      }
      triggers: {
        manual: {
          type: 'Request'
          kind: 'Http'
          inputs: {
            schema: {
              properties: {
                data: {
                  properties: {
                    context: {
                      properties: {
                        activityLog: {
                          properties: {
                            channels: {
                              type: 'string'
                            }
                            correlationId: {
                              type: 'string'
                            }
                            eventDataId: {
                              type: 'string'
                            }
                            eventSource: {
                              type: 'string'
                            }
                            eventTimestamp: {
                              type: 'string'
                            }
                            level: {
                              type: 'string'
                            }
                            operationId: {
                              type: 'string'
                            }
                            operationName: {
                              type: 'string'
                            }
                            properties: {
                              properties: {
                                cause: {
                                  type: 'string'
                                }
                                currentHealthStatus: {
                                  type: 'string'
                                }
                                details: {
                                  type: 'string'
                                }
                                previousHealthStatus: {
                                  type: 'string'
                                }
                                title: {
                                  type: 'string'
                                }
                                type: {
                                  type: 'string'
                                }
                              }
                              type: 'object'
                            }
                            resourceGroupName: {
                              type: 'string'
                            }
                            resourceId: {
                              type: 'string'
                            }
                            resourceProviderName: {
                              type: 'string'
                            }
                            resourceType: {
                              type: 'string'
                            }
                            status: {
                              type: 'string'
                            }
                            submissionTimestamp: {
                              type: 'string'
                            }
                            subscriptionId: {
                              type: 'string'
                            }
                          }
                          type: 'object'
                        }
                      }
                      type: 'object'
                    }
                    status: {
                      type: 'string'
                    }
                  }
                  type: 'object'
                }
                schemaId: {
                  type: 'string'
                }
              }
              type: 'object'
            }
          }
          conditions: [
            {
              expression: '@not(empty(triggerBody())) '
            }
            {
              expression: '@and(equals(triggerBody()?[\'schemaId\'],\'Microsoft.Insights/activityLogs\'),equals(triggerBody()?[\'data\']?[\'context\']?[\'activityLog\']?[\'eventSource\'],\'ResourceHealth\'))'
            }
            {
              expression: '@and(equals(triggerBody()?[\'data\']?[\'context\']?[\'activityLog\']?[\'properties\']?[\'cause\'],\'PlatformInitiated\'))'
            }
          ]
        }
      }
      actions: {
        Compose_Resource_Mapping_JSON: {
          runAfter: {
            Initialize_Succeeded: [
              'Succeeded'
            ]
          }
          type: 'Compose'
          inputs: entityMappings
        }
        Have_one_or_more_ingested_events_failed: {
          actions: {
            One_or_more_events_were_not_successfully_ingested: {
              runAfter: {
              }
              type: 'Terminate'
              inputs: {
                runStatus: 'Failed'
              }
            }
          }
          runAfter: {
            If_Exists_Mapped_Entity: [
              'Succeeded'
            ]
          }
          expression: {
            and: [
              {
                not: {
                  equals: [
                    '@variables(\'succeeded\')'
                    true
                  ]
                }
              }
            ]
          }
          type: 'If'
        }
        If_Exists_Mapped_Entity: {
          actions: {
            Get_Mapped_EntityType: {
              runAfter: {
              }
              type: 'Compose'
              inputs: '@first(body(\'Map_Resource_to_Entity\'))[\'entityType\']'
            }
            Get_Mapped_Is_Generic_Type: {
              runAfter: {
                Set_Selector_Type: [
                  'Succeeded'
                ]
              }
              type: 'Compose'
              inputs: '@first(body(\'Map_Resource_to_Entity\'))[\'isGenericType\']'
            }
            Get_Mapped_SelectorType: {
              runAfter: {
                Set_Entity_Type: [
                  'Succeeded'
                ]
              }
              type: 'Compose'
              inputs: '@first(body(\'Map_Resource_to_Entity\'))[\'selectorType\']'
            }
            Is_Entity_Type_and_Selector_Type_Set: {
              actions: {
                Filter_failed_resource_events: {
                  runAfter: {
                    Ingest_Resource_Health_Alert: [
                      'Succeeded'
                    ]
                  }
                  type: 'Query'
                  inputs: {
                    from: '@body(\'Ingest_Resource_Health_Alert\')?[\'eventIngestResults\']'
                    where: '@not(equals(item()?[\'status\'], \'OK\'))'
                  }
                }
                Has_Ingest_Resource_Health_Alert_Succeeded: {
                  actions: {
                    Set_Ingest_Resource_Health_Alert_failed: {
                      runAfter: {
                      }
                      type: 'SetVariable'
                      inputs: {
                        name: 'succeeded'
                        value: false
                      }
                    }
                  }
                  runAfter: {
                    Filter_failed_resource_events: [
                      'Succeeded'
                    ]
                  }
                  expression: {
                    or: [
                      {
                        greater: [
                          '@length(body(\'Filter_failed_resource_events\'))'
                          0
                        ]
                      }
                    ]
                  }
                  type: 'If'
                }
                Ingest_Resource_Health_Alert: {
                  runAfter: {
                    Switch_Event_Type: [
                      'Succeeded'
                    ]
                  }
                  type: 'ApiConnection'
                  inputs: {
                    body: {
                      entitySelector: '@variables(\'entitySelector\')'
                      eventType: '@variables(\'eventType\')'
                      properties: '@triggerBody()?[\'data\']?[\'context\']?[\'activityLog\']?[\'properties\']'
                      startTime: '@{variables(\'startTimeInMs\')}'
                      timeout: 1440
                      title: '@triggerBody()?[\'data\']?[\'context\']?[\'activityLog\']?[\'properties\']?[\'title\']'
                    }
                    headers: {
                      'Content-Type': 'application/json;charset=utf-8'
                    }
                    host: {
                      connection: {
                        name: '@parameters(\'$connections\')[\'dynatrace\'][\'connectionId\']'
                      }
                    }
                    method: 'post'
                    path: '/api/v2/events/ingest'
                  }
                }
                Is_Generic_Entity_Type: {
                  actions: {
                    Switch_Generic_Selector_Type: {
                      runAfter: {
                      }
                      cases: {
                        Case_Generic_Resource_Id: {
                          case: 'resource-id'
                          actions: {
                            Set_Generic_Resource_Id_Selector: {
                              runAfter: {
                              }
                              type: 'SetVariable'
                              inputs: {
                                name: 'entitySelector'
                                value: 'type("@{variables(\'entityType\')}", customProperties("Resource ID:@{triggerBody()?[\'data\']?[\'context\']?[\'activityLog\']?[\'resourceId\']}")'
                              }
                            }
                          }
                        }
                      }
                      default: {
                        actions: {
                          Terminate_Generic_Selector_Type_Not_Implemented: {
                            runAfter: {
                            }
                            type: 'Terminate'
                            inputs: {
                              runStatus: 'Succeeded'
                            }
                          }
                        }
                      }
                      expression: '@variables(\'selectorType\')'
                      type: 'Switch'
                    }
                  }
                  runAfter: {
                  }
                  else: {
                    actions: {
                      'Switch_Non-Generic_Selector_Type': {
                        runAfter: {
                        }
                        cases: {
                          'Case_Non-Generic_Resource_Id': {
                            case: 'resource-id'
                            actions: {
                              Set_Non_Generic_Resource_Id_Selector: {
                                runAfter: {
                                }
                                type: 'SetVariable'
                                inputs: {
                                  name: 'entitySelector'
                                  value: 'type("@{variables(\'entityType\')}"), azureResourceId("@{tolower(triggerBody()?[\'data\']?[\'context\']?[\'activityLog\']?[\'resourceId\'])}")'
                                }
                              }
                            }
                          }
                          'Case_Non-Generic_Resource_Name': {
                            case: 'resource-name'
                            actions: {
                              Set_Non_Generic_Resource_Name_Selector: {
                                runAfter: {
                                }
                                type: 'SetVariable'
                                inputs: {
                                  name: 'entitySelector'
                                  value: 'type("@{variables(\'entityType\')}"),detectedName("@{last(split(triggerBody()?[\'data\']?[\'context\']?[\'activityLog\']?[\'resourceId\'],\'/\'),\'\')}"), azureResourceGroupName("@{triggerBody()?[\'data\']?[\'context\']?[\'activityLog\']?[\'resourceGroupName\']}"),fromRelationships.isAccessibleBy(type("AZURE_SUBSCRIPTION"), azureSubscriptionUuid("@{triggerBody()?[\'data\']?[\'context\']?[\'activityLog\']?[\'subscriptionId\']}"))'
                                }
                              }
                            }
                          }
                        }
                        default: {
                          actions: {
                            'Terminate_Non-Generic_Selector_Type_Not_Implemented': {
                              runAfter: {
                              }
                              type: 'Terminate'
                              inputs: {
                                runStatus: 'Succeeded'
                              }
                            }
                          }
                        }
                        expression: '@variables(\'selectorType\')'
                        type: 'Switch'
                      }
                    }
                  }
                  expression: {
                    and: [
                      {
                        equals: [
                          '@variables(\'isGenericType\')'
                          true
                        ]
                      }
                    ]
                  }
                  type: 'If'
                }
                Switch_Event_Type: {
                  runAfter: {
                    Is_Generic_Entity_Type: [
                      'Succeeded'
                    ]
                  }
                  cases: {
                    Case_Available: {
                      case: 'Available'
                      actions: {
                        Set_Available_Type: {
                          runAfter: {
                          }
                          type: 'SetVariable'
                          inputs: {
                            name: 'eventType'
                            value: 'CUSTOM_INFO'
                          }
                        }
                      }
                    }
                    Case_Degraded: {
                      case: 'Degraded'
                      actions: {
                        Set_Degraded_Type: {
                          runAfter: {
                          }
                          type: 'SetVariable'
                          inputs: {
                            name: 'eventType'
                            value: 'ERROR_EVENT'
                          }
                        }
                      }
                    }
                    Case_Unknown: {
                      case: 'Unknown'
                      actions: {
                        Set_Unknown_Type: {
                          runAfter: {
                          }
                          type: 'SetVariable'
                          inputs: {
                            name: 'eventType'
                            value: 'CUSTOM_INFO'
                          }
                        }
                      }
                    }
                  }
                  default: {
                    actions: {
                      Set_default_Type: {
                        runAfter: {
                        }
                        type: 'SetVariable'
                        inputs: {
                          name: 'eventType'
                          value: 'ERROR_EVENT'
                        }
                      }
                    }
                  }
                  expression: '@triggerBody()?[\'data\']?[\'context\']?[\'activityLog\']?[\'properties\']?[\'currentHealthStatus\']'
                  type: 'Switch'
                }
              }
              runAfter: {
                Set_Is_Generic_Type: [
                  'Succeeded'
                ]
              }
              else: {
                actions: {
                  Terminate_Entity_or_Selector_Type_Not_Set: {
                    runAfter: {
                    }
                    type: 'Terminate'
                    inputs: {
                      runStatus: 'Succeeded'
                    }
                  }
                }
              }
              expression: {
                and: [
                  {
                    not: {
                      equals: [
                        '@variables(\'entityType\')'
                        '\'\''
                      ]
                    }
                  }
                  {
                    not: {
                      equals: [
                        '@variables(\'selectorType\')'
                        '\'\''
                      ]
                    }
                  }
                ]
              }
              type: 'If'
            }
            Set_Entity_Type: {
              runAfter: {
                Get_Mapped_EntityType: [
                  'Succeeded'
                ]
              }
              type: 'SetVariable'
              inputs: {
                name: 'entityType'
                value: '@{outputs(\'Get_Mapped_EntityType\')}'
              }
            }
            Set_Is_Generic_Type: {
              runAfter: {
                Get_Mapped_Is_Generic_Type: [
                  'Succeeded'
                ]
              }
              type: 'SetVariable'
              inputs: {
                name: 'isGenericType'
                value: '@bool(outputs(\'Get_Mapped_Is_Generic_Type\'))'
              }
            }
            Set_Selector_Type: {
              runAfter: {
                Get_Mapped_SelectorType: [
                  'Succeeded'
                ]
              }
              type: 'SetVariable'
              inputs: {
                name: 'selectorType'
                value: '@{outputs(\'Get_Mapped_SelectorType\')}'
              }
            }
          }
          runAfter: {
            Map_Resource_to_Entity: [
              'Succeeded'
            ]
          }
          else: {
            actions: {
              Terminate__No_Mapped_Entity_Exists: {
                runAfter: {
                }
                type: 'Terminate'
                inputs: {
                  runStatus: 'Succeeded'
                }
              }
            }
          }
          expression: {
            and: [
              {
                greater: [
                  '@length(body(\'Map_Resource_to_Entity\'))'
                  0
                ]
              }
            ]
          }
          type: 'If'
        }
        Initialize_SelectorType: {
          runAfter: {
            Initialize_entityType: [
              'Succeeded'
            ]
          }
          type: 'InitializeVariable'
          inputs: {
            variables: [
              {
                name: 'selectorType'
                type: 'string'
              }
            ]
          }
        }
        Initialize_Succeeded: {
          runAfter: {
            Initialize_isGenericType: [
              'Succeeded'
            ]
          }
          type: 'InitializeVariable'
          inputs: {
            variables: [
              {
                name: 'succeeded'
                type: 'boolean'
                value: true
              }
            ]
          }
        }
        Initialize_entitySelector: {
          runAfter: {
            Initialize_startTimeInMs: [
              'Succeeded'
            ]
          }
          type: 'InitializeVariable'
          inputs: {
            variables: [
              {
                name: 'entitySelector'
                type: 'string'
              }
            ]
          }
        }
        Initialize_entityType: {
          runAfter: {
            Initialize_eventType: [
              'Succeeded'
            ]
          }
          type: 'InitializeVariable'
          inputs: {
            variables: [
              {
                name: 'entityType'
                type: 'string'
              }
            ]
          }
        }
        Initialize_eventType: {
          runAfter: {
            Initialize_entitySelector: [
              'Succeeded'
            ]
          }
          type: 'InitializeVariable'
          inputs: {
            variables: [
              {
                name: 'eventType'
                type: 'string'
              }
            ]
          }
        }
        Initialize_isGenericType: {
          runAfter: {
            Initialize_SelectorType: [
              'Succeeded'
            ]
          }
          type: 'InitializeVariable'
          inputs: {
            variables: [
              {
                name: 'isGenericType'
                type: 'boolean'
                value: false
              }
            ]
          }
        }
        Initialize_startTimeInMs: {
          runAfter: {
          }
          type: 'InitializeVariable'
          inputs: {
            variables: [
              {
                name: 'startTimeInMs'
                type: 'integer'
                value: '@  div(sub(ticks(parseDateTime(triggerBody()?[\'data\']?[\'context\']?[\'activityLog\']?[\'eventTimestamp\'])),ticks(\'1970-01-01\')),10000)'
              }
            ]
          }
        }
        Map_Resource_to_Entity: {
          runAfter: {
            Parse_Resource_Mapping_Array: [
              'Succeeded'
            ]
          }
          type: 'Query'
          inputs: {
            from: '@body(\'Parse_Resource_Mapping_Array\')?[\'EntityMappings\']'
            where: '@equals(item()?[\'ResourceType\'], toLower(triggerBody()?[\'data\']?[\'context\']?[\'activityLog\']?[\'resourceType\']))'
          }
        }
        Parse_Resource_Mapping_Array: {
          runAfter: {
            Compose_Resource_Mapping_JSON: [
              'Succeeded'
            ]
          }
          type: 'ParseJson'
          inputs: {
            content: '@outputs(\'Compose_Resource_Mapping_JSON\')'
            schema: {
              properties: {
                EntityMappings: {
                  items: {
                    properties: {
                      EntityType: {
                        type: 'string'
                      }
                      ResourceType: {
                        type: 'string'
                      }
                      ServiceName: {
                        type: 'string'
                      }
                      isGenericType: {
                        type: 'boolean'
                      }
                      selectorType: {
                        type: 'string'
                      }
                    }
                    required: [
                      'EntityType'
                      'ServiceName'
                      'ResourceType'
                      'isGenericType'
                      'selectorType'
                    ]
                    type: 'object'
                  }
                  type: 'array'
                }
              }
              type: 'object'
            }
          }
        }
      }
      outputs: {
      }
    }
    parameters: {
      '$connections': {
        value: {
          dynatrace: {
            connectionId: dynatraceConnection.id
            connectionName: dynatraceConnection.name
            id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location,'dynatrace')
          }
        }
      }
    }
  }
}

// Azure ResourceHealth Action Group
resource resourceHealthActionGroup 'microsoft.insights/actionGroups@2021-09-01' = {
  name: 'dt-forward-resourcehealth-action-group'
  location: 'Global'
  tags: {}
  properties: {
    groupShortName: 'dt-rsc-hlth'
    enabled: true
    emailReceivers: []
    smsReceivers: []
    webhookReceivers: []
    eventHubReceivers: []
    itsmReceivers: []
    azureAppPushReceivers: []
    automationRunbookReceivers: []
    voiceReceivers: []
    logicAppReceivers: [
      {
        name: 'dt-forward-resourcehealth'
        resourceId: resourceHealthLogicApp.id
        callbackUrl:  listCallbackURL('${resourceHealthLogicApp.id}/triggers/manual', resourceHealthLogicApp.apiVersion).value
        useCommonAlertSchema: false
      }
    ]
    azureFunctionReceivers: []
    armRoleReceivers: []
  }
}

// Azure ResourceHealth Alert
resource resourceHealthActivityLogAlerts 'microsoft.insights/activityLogAlerts@2020-10-01' = {
  name: 'dt-forward-resourcehealth'
  location: 'Global'
  tags: {}
  properties: {
    scopes: [
      subscription().id
    ]
    condition: {
      allOf: [
        {
          field: 'category'
          equals: 'ResourceHealth'
        }
      ]
    }
    actions: {
      actionGroups: [
        {
          actionGroupId: resourceHealthActionGroup.id
          webhookProperties: {}
        }
      ]
    }
    enabled: true
  }
}
