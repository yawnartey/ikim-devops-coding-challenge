# setting up and using SOP for encrypting credentials before putting them into git

- we need s3 credentials to backup postgres into s3
- this has to be done automatically which means the secrets has to be pushed to git and flux gets is from git and then uses it
- secrets (aws s3 access keys) cannot be pushed to git
- this means we need a mechanism to:
  - encrypt it locally
  - push the encrypted keys to git
  - passes decryption mechanism to flux
  - flux decrypts it and uses it to setup the appropriate procedure for the backup into s3

to achieve this, the following was done

- generate SOPs age-key
  - the age-key contains a keypair used in encrypting the data
  - generate it by running: `age-keygen -o age.agekey`
  - public key is used to encrypt and private key is used to decrypt
- put the public key in `.sops.yaml`
  - this is the config file that sops is going to read
  - it is commited into the git repo
  - within the file, `path_regex` tells sop which files it should act on
  - within the same config file, `encrypted_regex` tells sop encrypt only values
  - add the public key for the encryption
- using sop for encryption
  - write the secrets manifest (the aws s3 access key and secret keys) and encrypt it locally
  - has been written at `platform/postgres/backup-credentials.sops.yaml`
  - do the encryption: `sops -e -i platform/postgres/backup-credentials.sops.yaml`
  - the encrypted files can now be commited and used
- get the private keys into the cluster
  - the private key is needed in the cluster to decrypt the manifest that was encrypted above
  - terraform pases this on to the vm. the actual private key is stored in `terraform.tfvars`
  - terraform passes it into `bootstrap.sh` with templatefile
  - bootstrap attached to the compute module (vm basically) now creates the secrets on the vm. of course it will be consumed as k8s secrets
  - this is the command: `kubectl create secret generic sops-age -n flux-system --from-literal=age.agekey="${sops_age_key}"`
- tell flux where to find the key so it can use it for the decryption
  - this has been written at `clusters/openbao-platform/postgres.yaml`
  - ```yaml
    decryption:
      provider: sops
      secretRef:
        name: sops-age
    ```
  - kustomize-controller sees the encrypted file, pulls the private key from the sops-age secret decrypts in memory and applies the decrypted secret
- cnpg picks the key and does it's backup
  - `objectstore.yaml` references the backed-up credentials
  - barman plugin reads the key and then authenticates to hetzner s3
