locals {
  secret_item_names = {
    for key, value in try(var.secrets.items, {}) :
    key => try(value.name, tostring(value))
  }
}

resource "azurerm_key_vault" "this" {
  name                       = var.key_vault_name
  location                   = var.location
  resource_group_name        = var.resource_group_name
  tenant_id                  = var.tenant_id
  sku_name                   = "standard"
  soft_delete_retention_days = 7
  purge_protection_enabled   = false

  access_policy {
    tenant_id = var.tenant_id
    object_id = var.object_id

    secret_permissions = [
      "Get",
      "List",
      "Set",
      "Delete",
      "Recover",
      "Purge",
    ]

    certificate_permissions = [
      "Create",
      "Delete",
      "Get",
      "Import",
      "List",
      "Purge",
      "Recover",
      "Update",
    ]
  }

  access_policy {
    tenant_id = var.tenant_id
    object_id = azurerm_user_assigned_identity.app_gateway.principal_id

    secret_permissions = [
      "Get",
      "List",
    ]

    certificate_permissions = [
      "Get",
      "List",
    ]
  }

  tags = {
    Name = var.key_vault_name
  }
}

resource "azurerm_user_assigned_identity" "app_gateway" {
  name                = "${var.name_prefix}-appgw-identity"
  location            = var.location
  resource_group_name = var.resource_group_name
}

resource "azurerm_key_vault_certificate" "api" {
  name         = "api-tls"
  key_vault_id = azurerm_key_vault.this.id

  certificate_policy {
    issuer_parameters {
      name = "Self"
    }

    key_properties {
      exportable = true
      key_size   = 2048
      key_type   = "RSA"
      reuse_key  = true
    }

    lifetime_action {
      action {
        action_type = "AutoRenew"
      }

      trigger {
        days_before_expiry = 30
      }
    }

    secret_properties {
      content_type = "application/x-pkcs12"
    }

    x509_certificate_properties {
      key_usage = [
        "digitalSignature",
        "keyEncipherment",
      ]

      subject            = "CN=${var.api_domain}"
      validity_in_months = 12

      subject_alternative_names {
        dns_names = [var.api_domain]
      }
    }
  }
}
