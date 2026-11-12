# Gitlab Example:
Most Government teams use gitlab, so while we are using Github actions, here is an example of a gitlab deployment...
```bash
    stages:
      - deploy-edge
    deploy_pi5_node:
      stage: deploy-edge
      image: 
        name: hashicorp/terraform:latest
        entrypoint: [""]
      before_script:
        # 1. Install SOPS binary
        - wget -O /usr/local/bin/sops https://github.com/getsops/sops/releases/download/v3.8.1/sops-v3.8.1.linux.amd64
        - chmod +x /usr/local/bin/sops
        # 2. Make the Age private key available to SOPS
        # The variable $SOPS_AGE_KEY comes from GitLab CI/CD Variables
        - export SOPS_AGE_KEY="$SOPS_AGE_KEY"
      script:
        # 3. Decrypt the machine configuration in-memory or to a temp file
        - sops -d configs/worker-pi5.enc.yaml > /tmp/worker-pi5.yaml
        
        # 4. Terraform applies the config directly to the Pi's IP over port 50000
        - terraform init
        - terraform apply -auto-approve -var="worker_config_path=/tmp/worker-pi5.yaml"
        
        # 5. Clean up temporary unencrypted files
        - rm -f /tmp/worker-pi5.yaml
      rules:
        - if: '$CI_COMMIT_BRANCH == "main"'
```
