# Packer build commands
.PHONY: packer-aws packer-gcp

# Tries to find project ID from GCP_PROJECT_ID or TF_VAR_gcp_project_id
PROJECT_ID := $(or $(GCP_PROJECT_ID),$(TF_VAR_project_id))

packer-aws:
	packer init aws.pkr.hcl && packer build -var "region=us-east-1" aws.pkr.hcl

packer-gcp:
	@if [ -z "$(PROJECT_ID)" ]; then \
		echo "Error: GCP_PROJECT_ID or TF_VAR_project_id must be set"; \
		exit 1; \
	fi
	packer init gcp.pkr.hcl && packer build -var "project_id=$(PROJECT_ID)" gcp.pkr.hcl
