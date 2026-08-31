# PostgreSQL backup verification and restore

This runbook covers how to restore the postgres backend for openbao. Every manifest file here needs to be applied on the cluster the recovery is being run on.

<!-- This file is documentation, not desired state. Nothing here is reconciled by
Flux. Every manifest below is applied by hand during an incident and removed
afterwards. See "Why this is not in a Flux path" at the end. -->

## How the backup has been configured and setup

| Backup tool         | Where it lives                                      | What it does                              |
| ------------------- | --------------------------------------------------- | ----------------------------------------- |
| Barman Cloud Plugin | `platform/cnpg-barman-plugin/manifest.yaml`         | runs the backup and WAL archiving         |
| `ObjectStore`       | `platform/postgres/objectstore.yaml`                | bucket, endpoint, retention, credentials  |
| Credentials         | `platform/postgres/backup-credentials.sops.yaml`    | S3 keys, age-encrypted, decrypted by Flux |
| WAL archiver        | `plugins` block in `platform/postgres/cluster.yaml` | continuous WAL shipping                   |
| `ScheduledBackup`   | `platform/postgres/scheduledbackup.yaml`            | base backup daily at 02:00                |

Bucket layout under `s3://openbao-platform-backups/openbao-postgres/`:

- `base/<timestamp>/` holds `data.tar.gz` and `backup.info`, one directory per
  base backup. This is the starting point of any restore.
- `wals/<timeline>/` holds every WAL segment since archiving began. These are
  replayed on top of a base backup to reach an arbitrary point in time.

Retention is 30 days, set on the `ObjectStore`.

## Prerequisites

- You should be connected to the cluster and be able to run `kubectl` against the cluster
- To inspect the bucket, either use:
  - the Hetzner Cloud console or
  - `aws` cli which will require a secret and access keys. These can be retrieved from `infra/terraform.tfvars` as this is where it has been currently stored

Find the pod currently acting as the Postgres primary before running any psql command. The cluster runs three instances and only the primary accepts writes and which pod holds that role changes after a failover:

```
kubectl get cluster openbao-postgres -n openbao -o jsonpath='{.status.currentPrimary}{"\n"}'
```

## 1. Verify backups are healthy

Run this as a routine check to verify that the backups are indeed in place as expected and the cluster is in a healthy state

```
kubectl get cluster openbao-postgres -n openbao
kubectl get backup -n openbao
kubectl get scheduledbackup -n openbao
kubectl get objectstore -n openbao
```

Check that WAL archiving is actually working:

```
kubectl get cluster openbao-postgres -n openbao \
  -o jsonpath='{.status.conditions[?(@.type=="ContinuousArchiving")]}{"\n"}'
```

Inspect the bucket directly:

```
AWS_ACCESS_KEY_ID=<key> AWS_SECRET_ACCESS_KEY=<secret> \
aws s3 ls s3://openbao-platform-backups/openbao-postgres/base/ \
  --endpoint-url https://fsn1.your-objectstorage.com
```

If a backup is older than 24hrs, then it means a backup is not firing. Backup can also be triggered manually from the command below:

## 2. Trigger a backup on demand

```
kubectl apply -f - <<'EOF'
apiVersion: postgresql.cnpg.io/v1
kind: Backup
metadata:
  name: manual-1
  namespace: openbao
spec:
  cluster:
    name: openbao-postgres
  method: plugin
  pluginConfiguration:
    name: barman-cloud.cloudnative-pg.io
EOF
```

watch the backup live

```
kubectl get backup manual-1 -n openbao -w
```

`phase: completed` means the base backup is in the bucket. To find the object path:

```
kubectl get backup manual-1 -n openbao -o yaml | sed -n '/^status:/,$p'
```

`backupId` is the directory name under `base/`.

## 3. Restore to the latest available state

Recovery always creates a new cluster. It never modifies the source, so this is safe to run while `openbao-postgres` is serving traffic.

```yaml
kubectl apply -f - <<'EOF'
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: openbao-postgres-restored
  namespace: openbao
spec:
  instances: 1

  affinity:
    nodeSelector:
      node-role.kubernetes.io/database: ""
    tolerations:
      - key: workload
        operator: Equal
        value: database
        effect: NoSchedule

  storage:
    storageClass: local-path
    size: 30Gi

  bootstrap:
    recovery:
      source: openbao-postgres-origin

  externalClusters:
    - name: openbao-postgres-origin
      plugin:
        name: barman-cloud.cloudnative-pg.io
        parameters:
          barmanObjectName: openbao-postgres-backups
          serverName: openbao-postgres
EOF

```

Notes on the fields that are easy to miss and to not get it right:

- `bootstrap.recovery` replaces `bootstrap.initdb`. A cluster cannot have both of them.
- `serverName` is the name of the **original** cluster, because that is the prefix the objects sit under in he bucket. It is not the name of the new cluster.
- `instances: 1` for demo purposes only. For a real production case, a real recovery is going to use 3 or more.

Watch it come up:

```
kubectl get cluster -n openbao -w
kubectl logs -n openbao openbao-postgres-restored-1 -c postgres -f
```

## 4. Point-in-time recovery

Same manifest as above, with a target added under `recovery`:

```yaml
bootstrap:
  recovery:
    source: openbao-postgres-origin
    recoveryTarget:
      targetTime: "2026-08-30 12:25:00.000000+00"
```

## 5. This steps can be used to demo the above documented disaster recovery

This steps demonstrates a disaster recovery approach and proves that it works as expected. The step creates a table, drops that table (to illustrate what happens during a disaster) and then restore just before the drop

**Write a marker and record the time.**

```
PRIMARY=$(kubectl get cluster openbao-postgres -n openbao -o jsonpath='{.status.currentPrimary}')

kubectl exec -n openbao "$PRIMARY" -c postgres -- \
  psql -U postgres -d openbao -c \
  "CREATE TABLE restore_test (id serial primary key, note text, at timestamptz default now());
   INSERT INTO restore_test (note) VALUES ('before-drop');
   SELECT * FROM restore_test;"

date -u +"%Y-%m-%d %H:%M:%S.000000+00"
```

Save that timestamp.

**Force a WAL switch so the insert reaches the archive.**

```
kubectl exec -n openbao "$PRIMARY" -c postgres -- \
  psql -U postgres -c "SELECT pg_switch_wal();"
```

Wait for the segment to appear under `wals/` before continuing.

**Destroy the data.**

```
kubectl exec -n openbao "$PRIMARY" -c postgres -- \
  psql -U postgres -d openbao -c "DROP TABLE restore_test;"
```

**Restore to just before the drop.** Apply the manifest from section 4 using
the saved timestamp.

**Prove the data came back.**

```
kubectl exec -n openbao openbao-postgres-restored-1 -c postgres -- \
  psql -U postgres -d openbao -c "SELECT * FROM restore_test;"
```

The row is present in the restored cluster and absent in the live one. That
pair of outputs is the evidence that PITR works.

**Clean up.**

```
kubectl delete cluster openbao-postgres-restored -n openbao
```

## 6. Real disaster recovery for OpenBao

The steps mentioned above proves the recovery mechanims. Recovering the platform for production-based cases needs two more things as outlined below:

**The restored database holds ciphertext.** OpenBao encrypts everything before it reaches Postgres. A restored database is unreadable until OpenBao is unsealed with the Shamir key shares held in the `openbao-unseal-keys` Secret in the `openbao` namespace. Losing that Secret means losing the data, regardless of how good the database backups are. Restoring Postgres is necessary but not sufficient.

**OpenBao points at a fixed connection URL.** The server reads `BAO_PG_CONNECTION_URL` from the `openbao-postgres-app` Secret, which CNPG generates and which names the original cluster. Two options:

1. Delete the damaged `openbao-postgres` and recreate it with the same name
   using a `bootstrap.recovery` block, so the generated Secret and service
   names are unchanged. This is the cleaner path, and it is the one to take
   in a real outage.
2. Restore under a new name and repoint OpenBao at it, which means editing the HelmRelease and rolling the pods.

After either path, the OpenBao pods come back sealed and must be unsealed before the platform is usable.
