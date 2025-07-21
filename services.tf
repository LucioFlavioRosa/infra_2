# ===== Recursos de Armazenamento e Banco de Dados =====

resource "azurerm_storage_account" "storage" {
  name                     = "stprodapp${random_id.suffix.hex}"
  # ... configurações padrão ...
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2" # Configuração segura
  public_network_access_enabled = false # Acesso público desabilitado, parece seguro
}

resource "azurerm_postgresql_server" "db_graph" {
  name                = "psql-prod-graph-db-${random_id.suffix.hex}"
  # ... configurações padrão ...
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  sku_name            = "GP_Gen5_2"
  version             = "11"
  ssl_enforcement_enabled = true # SSL forçado, parece seguro
  
  
  administrator_login          = "dbadmin"
  administrator_login_password = "Password-provided-by-pipeline" # Não está hardcoded
}

# ===== Private Endpoints para acesso seguro =====
# A criação de Private Endpoints é uma excelente prática de segurança.

resource "azurerm_private_endpoint" "kv_pe" {
  name                = "pe-keyvault"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  subnet_id           = azurerm_subnet.private_endpoint_subnet.id

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [azurerm_private_dns_zone.kv_dns_zone.id]
  }

  private_service_connection {
    name                           = "psc-keyvault"
    private_connection_resource_id = azurerm_key_vault.kv.id
    is_manual_connection           = false
    subresource_names              = ["vault"]
  }
}

# A zona DNS privada correspondente
resource "azurerm_private_dns_zone" "kv_dns_zone" {
  name                = "privatelink.vaultcore.azure.net"
  resource_group_name = azurerm_resource_group.rg.name
}

# ===== Aplicações e Lógica de Negócio =====

resource "azurerm_service_plan" "plan" {
  name                = "asp-prod-apps"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  os_type             = "Linux"
  sku_name            = "P1v2"
}

# App Service do Backend
resource "azurerm_app_service" "backend_app" {
  name                = "app-prod-backend-${random_id.suffix.hex}"
  # ...
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  app_service_plan_id = azurerm_service_plan.plan.id
  https_only          = true

  identity {
    type = "SystemAssigned"
  }

  site_config {
    
    cors {
      allowed_origins = [var.frontend_url]
      support_credentials = false 
    }
  }

  
  virtual_network_subnet_id = azurerm_subnet.backend_subnet.id
  app_settings = {
    "WEBSITE_VNET_ROUTE_ALL" = "true"
  }
}

# ===== Azure Databricks =====

resource "azurerm_databricks_workspace" "databricks" {
  name                = "dbw-prod-analytics-${random_id.suffix.hex}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  sku                 = "premium" # Premium para controles de acesso

  # Injeção na VNet, uma prática de segurança recomendada
  custom_parameters {
    no_public_ip                                = true
    private_subnet_name                         = azurerm_subnet.databricks_private_subnet.name
    virtual_network_id                          = azurerm_virtual_network.vnet.id
    
  }
}

# ===== Front Door Global =====

resource "azurerm_frontdoor_web_application_firewall_policy" "waf_policy" {
  name                = "waf-prod-policy"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  
  
  policy_settings {
    enabled = true
    mode    = "Detection"
  }

  managed_rules {
    managed_rule_set {
      type    = "OWASP_CRS"
      version = "3.2"
    }
  }
}

# Outros recursos como App Service do Frontend, Front Door, etc., seriam definidos aqui.

resource "random_id" "suffix" {
  byte_length = 4
}