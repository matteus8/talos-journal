# Quick start
A few commands to remember...
## Install CLI
See [here](https://github.com/getsops/sops/releases)
```bash
# Download the binary
curl -LO https://github.com/getsops/sops/releases/download/v3.13.3/sops-v3.13.3.linux.amd64
# Move the binary in to your PATH
mv sops-v3.13.3.linux.amd64 /usr/local/bin/sops
# Make the binary executable
chmod +x /usr/local/bin/sops
```
# Working with SOPS 
- `sops -e secrets.yaml > secrets.enc.yaml`
- `sops -d secrets.enc.yaml > /tmp/worker-pi5.yaml`
