plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

plugin "google" {
  enabled = true
  version = "0.27.0"
  source  = "github.com/terraform-linters/tflint-ruleset-google"
}

# Naming convention rules
rule "terraform_naming_convention" {
  enabled = true
}

# Require all variables to have descriptions
rule "terraform_documented_variables" {
  enabled = true
}

# Require all outputs to have descriptions
rule "terraform_documented_outputs" {
  enabled = true
}

# Require all variables to be typed
rule "terraform_typed_variables" {
  enabled = true
}

# Require version pinning
rule "terraform_required_version" {
  enabled = true
}

rule "terraform_required_providers" {
  enabled = true
}

# Detect unused declarations
rule "terraform_unused_declarations" {
  enabled = true
}

# Standard module structure
rule "terraform_standard_module_structure" {
  enabled = true
}
