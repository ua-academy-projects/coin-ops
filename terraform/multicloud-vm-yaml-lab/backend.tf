# The backend type is selected by scripts/lab.sh before `terraform init`.
# It renders backend.generated.tf as either:
# - terraform { backend "s3" {} }
# - terraform { backend "azurerm" {} }
