@description('Name of the App Service')
param appServiceName string = 'deadlock-demo-app'

@description('Location for all resources')
param location string = resourceGroup().location

@description('App Service Plan SKU')
@allowed([
  'S1'
  'S2'
  'S3'
  'P1v2'
  'P2v2'
  'P3v2'
])
param appServicePlanSku string = 'S1'

@description('Application Insights Workspace name')
param workspaceName string = 'deadlock-demo-workspace'

@description('Resource group name for outputs')
param resourceGroupName string = resourceGroup().name

// App Service Plan
resource appServicePlan 'Microsoft.Web/serverfarms@2023-01-01' = {
  name: '${appServiceName}-plan'
  location: location
  sku: {
    name: appServicePlanSku
  }
  properties: {
    reserved: false
  }
}

// Log Analytics Workspace
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: workspaceName
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
}

// Application Insights
resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: '${appServiceName}-ai'
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalyticsWorkspace.id
  }
}

// App Service (Production)
resource appService 'Microsoft.Web/sites@2023-01-01' = {
  name: appServiceName
  location: location
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
    siteConfig: {
      netFrameworkVersion: 'v8.0'
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      appSettings: [
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: applicationInsights.properties.ConnectionString
        }
        {
          name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
          value: applicationInsights.properties.InstrumentationKey
        }
        {
          name: 'ApplicationInsightsAgent_EXTENSION_VERSION'
          value: '~3'
        }
        {
          name: 'EnableDeadlockSimulation'
          value: 'false'
        }
        {
          name: 'PerformanceSettings__TimeoutThresholdMs'
          value: '5000'
        }
        {
          name: 'PerformanceSettings__HealthyResponseTimeMs'
          value: '500'
        }
        {
          name: 'PerformanceSettings__DegradedResponseTimeMs'
          value: '2000'
        }
        {
          name: 'PerformanceSettings__DeadlockProbabilityPercent'
          value: '15'
        }
      ]
      healthCheckPath: '/health'
    }
  }
}

// Staging Slot
resource stagingSlot 'Microsoft.Web/sites/slots@2023-01-01' = {
  parent: appService
  name: 'staging'
  location: location
  properties: {
    serverFarmId: appServicePlan.id
    siteConfig: {
      netFrameworkVersion: 'v8.0'
      appSettings: [
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: applicationInsights.properties.ConnectionString
        }
        {
          name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
          value: applicationInsights.properties.InstrumentationKey
        }
        {
          name: 'ApplicationInsightsAgent_EXTENSION_VERSION'
          value: '~3'
        }
        {
          name: 'EnableDeadlockSimulation'
          value: 'false'
        }
        {
          name: 'PerformanceSettings__TimeoutThresholdMs'
          value: '5000'
        }
        {
          name: 'PerformanceSettings__HealthyResponseTimeMs'
          value: '500'
        }
        {
          name: 'PerformanceSettings__DegradedResponseTimeMs'
          value: '2000'
        }
        {
          name: 'PerformanceSettings__DeadlockProbabilityPercent'
          value: '15'
        }
      ]
      healthCheckPath: '/health'
    }
  }
}

// Action Group for Alerts
resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: '${appServiceName}-action-group'
  location: 'global'
  properties: {
    groupShortName: 'DeadlockDemo'
    enabled: true
    emailReceivers: [
      {
        name: 'SRE Team'
        emailAddress: 'sre-team@example.com'
        useCommonAlertSchema: true
      }
    ]
    webhookReceivers: []
  }
}

// Performance Degradation Alert
resource performanceAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: '${appServiceName}-performance-degradation'
  location: 'global'
  properties: {
    description: 'Alert when average response time exceeds 2000ms for 5 minutes - triggers SRE Agent remediation'
    severity: 2
    enabled: true
    scopes: [
      appService.id
    ]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'ResponseTime'
          metricName: 'HttpResponseTime'
          operator: 'GreaterThan'
          threshold: 2000
          timeAggregation: 'Average'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    actions: [
      {
        actionGroupId: actionGroup.id
        webHookProperties: {
          remediation_type: 'slot_swap'
          target_slot: 'staging'
          verification_timeout_minutes: '5'
          app_name: appServiceName
          resource_group: resourceGroupName
          alert_type: 'performance_degradation'
        }
      }
    ]
  }
}

// Thread Pool Exhaustion Alert
resource threadPoolAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: '${appServiceName}-thread-pool-exhaustion'
  location: 'global'
  properties: {
    description: 'Alert when thread pool utilization is high - potential deadlock indicator'
    severity: 2
    enabled: true
    scopes: [
      appService.id
    ]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'ThreadPoolUtilization'
          metricName: 'CpuTime'
          operator: 'GreaterThan'
          threshold: 60
          timeAggregation: 'Total'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    actions: [
      {
        actionGroupId: actionGroup.id
      }
    ]
  }
}

// Request Timeout Rate Alert
resource timeoutAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: '${appServiceName}-timeout-rate'
  location: 'global'
  properties: {
    description: 'Alert when request timeout rate exceeds 10% - deadlock indicator'
    severity: 2
    enabled: true
    scopes: [
      appService.id
    ]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'ErrorRate'
          metricName: 'Http5xx'
          operator: 'GreaterThan'
          threshold: 10
          timeAggregation: 'Average'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    actions: [
      {
        actionGroupId: actionGroup.id
      }
    ]
  }
}

// Health Check Failure Alert
resource healthCheckAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: '${appServiceName}-health-check-failure'
  location: 'global'
  properties: {
    description: 'Alert when health checks fail - immediate attention required'
    severity: 1
    enabled: true
    scopes: [
      appService.id
    ]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT1M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'HealthCheckFailure'
          metricName: 'Http4xx'
          operator: 'GreaterThan'
          threshold: 0
          timeAggregation: 'Total'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    actions: [
      {
        actionGroupId: actionGroup.id
      }
    ]
  }
}

// Output values
output appServiceName string = appService.name
output appServiceUrl string = 'https://${appService.properties.defaultHostName}'
output stagingUrl string = 'https://${replace(appService.properties.defaultHostName, '.azurewebsites.net', '-staging.azurewebsites.net')}'
output applicationInsightsConnectionString string = applicationInsights.properties.ConnectionString
output applicationInsightsInstrumentationKey string = applicationInsights.properties.InstrumentationKey
output workspaceName string = logAnalyticsWorkspace.name
output workspaceId string = logAnalyticsWorkspace.id
output resourceGroupName string = resourceGroupName
output actionGroupName string = actionGroup.name
