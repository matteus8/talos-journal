# GitLab CI/CD Pipeline (Centralized Push Deployment with talosctl)

Most government and defense teams use GitLab CI. While we are using GitHub Actions for this repo, here is an example of an internal GitLab CI pipeline deploying machine configs natively via `talosctl` (centralized CI push, no Terraform state required):

```yaml
stages:
  - deploy-edge

deploy_pi5_node:
  stage: deploy-edge
  image:
    name: alpine:latest # likely tagged
  variables:
    PI5_IP: "192.168.1.101" # or some matrix or GitLab Variable
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
    # Ensure temporary decrypted files are always wiped even if any step fails
    - trap 'rm -f /tmp/worker-pi5.yaml /tmp/talosconfig' EXIT

    # 4. Decrypt machine config and talosconfig in-memory
    - sops -d configs/worker-pi5.enc.yaml > /tmp/worker-pi5.yaml
    - sops -d configs/talosconfig.enc > /tmp/talosconfig
    
    # 5. Centralized CI push: Apply config directly to node API over mTLS
    - talosctl apply-config --nodes $PI5_IP --file /tmp/worker-pi5.yaml --talosconfig /tmp/talosconfig
  rules:
    - if: '$CI_COMMIT_BRANCH == "main"'
```

Why this beats Terraform in CI/CD on bare metal:
- Zero `terraform.tfstate` locking or remote backend dependencies (no S3/MinIO/RustFS required).
- Uses native Talos mTLS on port 50000
- The runner container is ephemeral, and the exit trap guarantees temporary decrypted secrets are wiped cleanly.
