# GitLab CI/CD Pipeline (GitOps with talosctl)

Most government and defense teams use GitLab CI. While we are using GitHub Actions for this repo, here is an example of an air-gapped or internal GitLab CI pipeline deploying machine configs natively via `talosctl` (pure GitOps, no Terraform state required):

```yaml
stages:
  - deploy-edge

deploy_pi5_node:
  stage: deploy-edge
  image:
    name: alpine:latest # likley tagged
  variables:
    PI5_IP: "192.168.1.101" # or some matrix or Gitlab Variable
  before_script:
    - apk add --no-cache curl
    # 1. Install SOPS
    - curl -LO https://github.com/getsops/sops/releases/download/v3.9.4/sops-v3.9.4.linux.amd64
    - mv sops-v3.9.4.linux.amd64 /usr/local/bin/sops
    - chmod +x /usr/local/bin/sops
    # 2. Install talosctl
    - curl -sL https://talos.dev/install | sh
    # 3. Inject Age private key from Protected GitLab CI Variables
    - export SOPS_AGE_KEY="$SOPS_AGE_KEY"
  script:
    # 4. Decrypt machine config in-memory to temporary file
    - sops -d configs/worker-pi5.enc.yaml > /tmp/worker-pi5.yaml
    
    # 5. Native GitOps: Apply config directly to node API over mTLS
    - talosctl apply-config --nodes $PI5_IP --file /tmp/worker-pi5.yaml --talosconfig configs/talosconfig
    
    # 6. Clean up unencrypted in-memory config
    - rm -f /tmp/worker-pi5.yaml
  rules:
    - if: '$CI_COMMIT_BRANCH == "main"'
```

Why this beats Terraform in CI/CD on bare metal:
- Zero `terraform.tfstate` locking or remote backend dependencies (no S3/MinIO/RustFS required).
- Uses native Talos mTLS on port 50000
- The runner container is ephemeral; once the job finishes, the decrypted config is completely wiped
