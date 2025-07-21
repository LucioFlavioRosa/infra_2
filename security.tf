# Azure Key Vault e Segredos
resource "azurerm_key_vault" "kv" {
  name                        = "kv-prod-lockeddown-app-${random_id.suffix.hex}"
  location                    = azurerm_resource_group.rg.location
  resource_group_name         = azurerm_resource_group.rg.name
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  sku_name                    = "premium" # Premium para chaves HSM
  soft_delete_retention_days  = 7
  purge_protection_enabled    = true # Boas práticas aplicadas

  network_acls {
    bypass         = "AzureServices"
    default_action = "Deny" # Acesso negado por padrão
    # Erro Sutil 2: Um IP de "parceiro" foi adicionado diretamente na ACL do Key Vault.
    # A variável `var.partner_ip_address` pode ser alterada para `0.0.0.0/0` sem
    # que o revisor perceba a mudança no plano de execução, criando um bypass completo
    # do Private Endpoint. A confiança em uma lista de IPs para o KV é um anti-pattern.
    ip_rules = [var.partner_ip_address]
  }
}

data "azurerm_client_config" "current" {}

resource "azurerm_key_vault_secret" "gemini_api_key" {
  name         = "GeminiApiKey"
  value        = "secret-value-placeholder" # Valor será injetado pela pipeline (parece seguro)
  key_vault_id = azurerm_key_vault.kv.id
}

# Firewall e Política de Roteamento
resource "azurerm_public_ip" "firewall_pip" {
  name                = "pip-firewall"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_firewall" "fw" {
  name                = "fw-main-prod"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku_name            = "AZFW_VNet"
  sku_tier            = "Standard"

  ip_configuration {
    name                 = "configuration"
    subnet_id            = azurerm_subnet.firewall_subnet.id
    public_ip_address_id = azurerm_public_ip.firewall_pip.id
  }
}

# Rota para forçar todo o tráfego de saída através do Firewall
resource "azurerm_route_table" "rt" {
  name                          = "rt-force-firewall"
  location                      = azurerm_resource_group.rg.location
  resource_group_name           = azurerm_resource_group.rg.name
  disable_bgp_route_propagation = false

  route {
    name           = "ToInternet"
    address_prefix = "0.0.0.0/0"
    next_hop_type  = "VirtualAppliance"
    next_hop_in_ip_address = azurerm_firewall.fw.ip_configuration[0].private_ip_address
  }
}

# Associando a rota à sub-rede do backend
resource "azurerm_subnet_route_table_association" "backend_rta" {
  subnet_id      = azurerm_subnet.backend_subnet.id
  route_table_id = azurerm_route_table.rt.id
}