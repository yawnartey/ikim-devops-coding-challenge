# setting up automated postgress backup into hetzner s3

- postgres holds openbao's data which implies it has to be backed up frequently so as to not looose the data
- backups have to live outside of the cluster, therefore they are being sent into an s3 bucket on hetzner
- two things are needed from the backup to be able to perform a proper restore
  - a base backup which is a full snapshot of the database
  - the wal stream, which is every change since the snapshot
  - restoring from base gets us data back to the moment the backup was taken
  - base + wal allows restoring to any point in time

to achieve this, the following was done

- create the bucket within which the backups will be stored in on hetzner with terraform
  - this has been written at the storage module at `infra/storage`
  - bucket name is `openbao-platform-backups` in hetzner s3
  - `prevent_destroy = true` so a terraform destroy cannot wipe the backups
- install barman cloud plugin required for continous backups of postgres into s3
  - installed via vendored plugin
  - the command to install is:

  ```
    curl -sSL https://github.com/cloudnative-pg/plugin-barman-cloud/releases/download/v0.14.0/manifest.yaml \
  -o platform/cnpg-barman-plugin/manifest.yaml
  ```

  - the manifest created from the command is: `platform/cnpg-barman-plugin/manifest.yaml`
  - flux kustomization for the manifest sits at `clusters/openbao-platform/cnpg-barman-plugin.yaml`

- creating the backup (more of telling the plugin where to put the backup)
  - this has been written at `platform/postgres/objectstore.yaml`
  - destination path, in essence where the bucket is: `destinationPath: s3://openbao-platform-backups/`
  - the bucket's endpoint url: `endpointURL: https://fsn1.your-objectstorage.com`
  - compress both the wal (point in time backup) and the data (planned backup) in gzip format
  - turning on the backup has been configured at `platform/postgres/cluster.yaml` at the `plugins` block
  - `isWALArchiver: true` makes the plugin the archiver for this cluster
  - `barmanObjectName` points at the objectstore above points to the objectstore above
- schedule the backup
  - this has been written at `platform/postgres/scheduledbackup.yaml`
  - `schedule: "0 0 2 * * *"` which is 02:00 every day
- how the backed up data is structured when they get to the bucket
  - `openbao-postgres/base/<timestamp>/` holds `data.tar.gz` and `backup.info`
  - `openbao-postgres/wals/<timeline>/` holds every wal segment that has been backed up

- we can force a backup to see it is actually working
  - command below does this:

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

  - now watch the backup taking place in real time

    ```
    kubectl get backup -n openbao -w
    ```
