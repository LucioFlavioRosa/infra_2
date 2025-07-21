variable "partner_ip_address" {
  description = "IP do escritório parceiro para acesso de emergência ao Key Vault."
  type        = string
  default     = "203.0.113.10/32" # Um IP de documentação, parece inofensivo
}

variable "frontend_url" {
  description = "URL do frontend para configuração de CORS."
  type        = string
  default     = "https://app.example.com"
}