apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: ${CLUSTER_ISSUER_NAME}
spec:
  acme:
    email: ${LETSENCRYPT_EMAIL}
    server: https://acme-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      name: ${CLUSTER_ISSUER_NAME}-account-key
    solvers:
      - http01:
          ingress:
            class: ${INGRESS_CLASS_NAME}
