# Hardening and Production Improvements

Recommended improvements after the baseline project is working:

1. Replace the Terraform service principal secret file with workload identity or a secure runner-based identity flow.
2. Move Jenkins ACR push credentials to Azure Key Vault plus External Secrets Operator.
3. Add private AKS API server and controlled jump access.
4. Replace public Jenkins `LoadBalancer` with internal ingress and SSO.
5. Use Azure Policy for AKS and Defender for Cloud.
6. Add Prometheus/Grafana or Azure Monitor managed collection.
7. Use cert-manager with DNS-01 and a production ingress controller.
8. Add environment approvals and protected Jenkins deployments.
9. Add Terraform plan/apply split with manual approval for production.
10. Pin Helm chart versions and provider versions tightly.

