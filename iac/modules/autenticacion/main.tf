resource "aws_cognito_user_pool" "this" {
  name                     = "${var.nombre}-usuarios"
  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]
  deletion_protection      = "INACTIVE"

  password_policy {
    minimum_length    = 10
    require_lowercase = true
    require_uppercase = true
    require_numbers   = true
    require_symbols   = false
  }

  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  schema {
    name                = "empresa_id"
    attribute_data_type = "String"
    mutable             = true
    required            = false

    string_attribute_constraints {
      min_length = 0
      max_length = 64
    }
  }
}

resource "aws_cognito_user_group" "this" {
  for_each     = toset(["clientes", "empresas", "administradores"])
  name         = each.key
  user_pool_id = aws_cognito_user_pool.this.id
}

resource "aws_cognito_user_pool_client" "web" {
  name                          = "${var.nombre}-web"
  user_pool_id                  = aws_cognito_user_pool.this.id
  generate_secret               = false
  prevent_user_existence_errors = "ENABLED"
  explicit_auth_flows           = ["ALLOW_USER_PASSWORD_AUTH", "ALLOW_USER_SRP_AUTH", "ALLOW_REFRESH_TOKEN_AUTH"]
  read_attributes               = ["email", "email_verified", "custom:empresa_id"]
  write_attributes              = ["email"]
  access_token_validity         = 60
  id_token_validity             = 60
  refresh_token_validity        = 30

  token_validity_units {
    access_token  = "minutes"
    id_token      = "minutes"
    refresh_token = "days"
  }
}
