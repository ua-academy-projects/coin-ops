# Multicloud VM YAML Lab

One neutral YAML config drives provider-specific Terraform roots.

Use these roots:

- `roots/gcp` for GCP
- `roots/aws` for AWS

The shared config lives in:

- `config/lab.yaml`

Run Terraform from a provider root, not from this directory:

```bash
cd roots/aws
terraform init -backend-config=backend.hcl -reconfigure
terraform plan
```

The design layers are:

1. `config/lab.yaml`: cloud-neutral intent and catalog dictionary.
2. `locals.intent.tf`: normalized neutral model.
3. `locals.gcp.tf` / `locals.aws.tf`: provider-specific adapters.
4. provider modules: resource creation.
