# CNPG Backups and Restore Drills

Coin-Ops CNPG backups use the CloudNativePG Barman Cloud Plugin. The custom
PostgreSQL runtime image is not modified; Barman runs in plugin-managed
sidecars. The active AWS EKS path stores backups in S3. The GCS and k3s notes
below remain valid for their legacy configurations.

For all commands in the active AWS environment, either use
`make eks-kubectl ARGS='...'` or export:

```bash
export KUBECONFIG="$PWD/ansible/artifacts/kubeconfig-aws-eks.yaml"
```

## Provisioning

1. Run Terraform so the provider-specific object-storage bucket, backup identity, credentials, and generated Ansible metadata are created.
2. Run the Jenkins `coinops-eks-deploy-coinops` job or `make eks-coinops` so
   Ansible installs CNPG, the Barman Cloud Plugin, credential Secret,
   ObjectStore, and daily ScheduledBackup. Use `make k3s-coinops` only for the
   legacy k3s path.
3. Confirm the plugin is available:

    kubectl rollout status deployment/barman-cloud -n cnpg-system

4. Confirm backup resources exist:

    kubectl get objectstore,scheduledbackup,backup -n coinops-data

## Backup Checks

The default schedule is 0 0 2 * * *, which is 02:00 UTC daily in CNPG six-field cron format. The default retention policy is 30d.

Check recent backup status:

    kubectl get backup -n coinops-data
    kubectl describe scheduledbackup coinops-postgres-daily -n coinops-data

Create an on-demand plugin backup when validating a new environment:

    kubectl apply -f - <<YAML
    apiVersion: postgresql.cnpg.io/v1
    kind: Backup
    metadata:
      name: coinops-postgres-manual
      namespace: coinops-data
    spec:
      cluster:
        name: coinops-postgres
      method: plugin
      pluginConfiguration:
        name: barman-cloud.cloudnative-pg.io
    YAML

## Test Namespace Restore

Use a separate namespace for restore drills so production Services and Secrets are not overwritten. A restore creates a new CNPG Cluster from the original cluster's backup archive; do not patch the live `coinops-postgres` Cluster for a drill.

Before testing restore, confirm pod networking and CNPG backup status are healthy:

    kubectl get cluster,pod,svc,endpoints -n coinops-data -o wide
    kubectl rollout status deployment/barman-cloud -n cnpg-system
    kubectl get objectstore,scheduledbackup,backup -n coinops-data

The `coinops-data` NetworkPolicies must allow the active pod and service CIDRs.
For EKS, these come from generated Terraform runtime metadata; the current
service CIDR is `10.43.0.0/16` and pod addresses come from the AWS VPC CNI. For
legacy k3s, defaults are `10.42.0.0/16` and `10.43.0.0/16`. A quick connectivity
check is:

    PRIMARY="$(kubectl get cluster coinops-postgres -n coinops-data -o jsonpath='{.status.currentPrimary}')"
    POD_IP="$(kubectl get pod "$PRIMARY" -n coinops-data -o jsonpath='{.status.podIP}')"

    kubectl exec -n coinops-data "$PRIMARY" -c postgres -- pg_isready -h "$POD_IP" -p 5432

Create a marker row before the manual backup:

    APP_USER="$(kubectl get secret coinops-postgres-app -n coinops-data -o jsonpath='{.data.username}' | base64 -d)"
    DB_NAME="$(kubectl get cluster coinops-postgres -n coinops-data -o jsonpath='{.spec.bootstrap.initdb.database}')"
    MARKER="restore-check-$(date +%s)"

    kubectl delete job cnpg-marker -n coinops-data --ignore-not-found
    kubectl apply -f - <<YAML
    apiVersion: batch/v1
    kind: Job
    metadata:
      name: cnpg-marker
      namespace: coinops-data
    spec:
      backoffLimit: 2
      template:
        spec:
          restartPolicy: Never
          securityContext:
            runAsNonRoot: true
            runAsUser: 999
            runAsGroup: 999
            seccompProfile:
              type: RuntimeDefault
          containers:
            - name: psql
              image: postgres:16
              securityContext:
                allowPrivilegeEscalation: false
                capabilities:
                  drop: ["ALL"]
              env:
                - name: PGPASSWORD
                  valueFrom:
                    secretKeyRef:
                      name: coinops-postgres-app
                      key: password
                - name: APP_USER
                  value: "$APP_USER"
                - name: DB_NAME
                  value: "$DB_NAME"
                - name: MARKER
                  value: "$MARKER"
              command:
                - sh
                - -ec
                - |
                  until pg_isready -h coinops-postgres-rw -p 5432 -U "\$APP_USER" -d "\$DB_NAME"; do
                    sleep 5
                  done
                  psql -h coinops-postgres-rw -U "\$APP_USER" -d "\$DB_NAME" <<SQL
                  CREATE SCHEMA IF NOT EXISTS restore_check;
                  CREATE TABLE IF NOT EXISTS restore_check.marker (
                    id text primary key,
                    created_at timestamptz default now()
                  );
                  INSERT INTO restore_check.marker(id) VALUES ('\$MARKER')
                  ON CONFLICT (id) DO NOTHING;
                  SELECT * FROM restore_check.marker ORDER BY created_at DESC LIMIT 5;
                  SQL
    YAML

    kubectl wait job/cnpg-marker -n coinops-data --for=condition=Complete --timeout=5m
    kubectl logs job/cnpg-marker -n coinops-data
    echo "$MARKER"

Trigger an on-demand backup and wait for it to complete:

    BACKUP_NAME="coinops-postgres-manual-$(date +%Y%m%d%H%M%S)"
    kubectl apply -f - <<YAML
    apiVersion: postgresql.cnpg.io/v1
    kind: Backup
    metadata:
      name: ${BACKUP_NAME}
      namespace: coinops-data
    spec:
      cluster:
        name: coinops-postgres
      method: plugin
      pluginConfiguration:
        name: barman-cloud.cloudnative-pg.io
    YAML

    kubectl get backup "$BACKUP_NAME" -n coinops-data -w
    kubectl describe backup "$BACKUP_NAME" -n coinops-data

Create the restore namespace and copy the required Secrets:

    kubectl create namespace coinops-restore-test

    for secret in ghcr-pull-secret coinops-postgres-superuser coinops-postgres-app coinops-cnpg-s3-backup; do
      kubectl get secret "$secret" -n coinops-data -o yaml \
        | sed 's/namespace: coinops-data/namespace: coinops-restore-test/' \
        | kubectl apply -f -
    done

For GCP, copy `coinops-cnpg-gcs-backup` instead of `coinops-cnpg-s3-backup`.

Create an ObjectStore in the restore namespace. For AWS:

    DEST="$(kubectl get objectstore coinops-postgres-s3 -n coinops-data -o jsonpath='{.spec.configuration.destinationPath}')"
    kubectl apply -f - <<YAML
    apiVersion: barmancloud.cnpg.io/v1
    kind: ObjectStore
    metadata:
      name: coinops-postgres-s3
      namespace: coinops-restore-test
    spec:
      configuration:
        destinationPath: "$DEST"
        s3Credentials:
          accessKeyId:
            name: coinops-cnpg-s3-backup
            key: ACCESS_KEY_ID
          secretAccessKey:
            name: coinops-cnpg-s3-backup
            key: ACCESS_SECRET_KEY
        wal:
          compression: gzip
        data:
          compression: gzip
    YAML

For GCP, use `coinops-postgres-gcs`, `coinops-cnpg-gcs-backup`, and `googleCredentials` with the `gcsCredentials` key from the live ObjectStore.

Create a restore-only Cluster with a new name. Keep `serverName: coinops-postgres`; it points the restore at the original cluster's backup archive.

    PG_IMAGE="$(kubectl get cluster coinops-postgres -n coinops-data -o jsonpath='{.spec.imageName}')"
    PG_STORAGE="$(kubectl get cluster coinops-postgres -n coinops-data -o jsonpath='{.spec.storage.size}')"

    kubectl apply -f - <<YAML
    apiVersion: postgresql.cnpg.io/v1
    kind: Cluster
    metadata:
      name: coinops-postgres-restore
      namespace: coinops-restore-test
    spec:
      instances: 1
      enableSuperuserAccess: true
      imageName: "$PG_IMAGE"
      postgresUID: 70
      postgresGID: 70
      imagePullSecrets:
        - name: ghcr-pull-secret
      superuserSecret:
        name: coinops-postgres-superuser
      bootstrap:
        recovery:
          source: origin
      externalClusters:
        - name: origin
          plugin:
            name: barman-cloud.cloudnative-pg.io
            parameters:
              barmanObjectName: coinops-postgres-s3
              serverName: coinops-postgres
      storage:
        size: "$PG_STORAGE"
      postgresql:
        shared_preload_libraries:
          - pg_cron
        parameters:
          cron.database_name: "$DB_NAME"
    YAML

Wait for restore and verify the marker:

    kubectl wait cluster/coinops-postgres-restore \
      -n coinops-restore-test \
      --for=condition=Ready \
      --timeout=20m

    APP_PASS="$(kubectl get secret coinops-postgres-app -n coinops-restore-test -o jsonpath='{.data.password}' | base64 -d)"
    kubectl run cnpg-restore-check --rm -i --restart=Never \
      -n coinops-restore-test \
      --image=postgres:16 \
      --env="PGPASSWORD=$APP_PASS" \
      -- psql -h coinops-postgres-restore-rw -U "$APP_USER" -d "$DB_NAME" \
      -c "SELECT * FROM restore_check.marker ORDER BY created_at DESC LIMIT 10;"

After validation, delete the test namespace:

    kubectl delete namespace coinops-restore-test

## Notes

- Terraform stores generated backup credentials in state. GCP uses a bucket-scoped service account key; AWS uses a bucket-scoped IAM user access key.
- GCP backup buckets have public access prevention and uniform bucket-level access enabled. AWS backup buckets have public access blocked, versioning enabled, and default SSE-S3 encryption.
- If the CNPG operator is older than 1.26, Ansible fails before applying plugin resources.
- Legacy k3s servers keep UFW disabled because host-level forwarding rules can
  block CNI traffic. EKS uses AWS security groups, VPC CNI, and Kubernetes
  NetworkPolicies instead.
- If direct pod-to-pod checks fail but deleting `coinops-data` NetworkPolicies
  makes them pass, fix the generated pod/service CIDR metadata and re-apply the
  appropriate CoinOps job. Do not leave default-deny policies deleted.
