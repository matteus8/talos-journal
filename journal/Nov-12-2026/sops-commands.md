# Quick start: Working with SOPS & Age

A few essential commands to remember when encrypting Talos configs...

## 1. Install SOPS
See [here](https://github.com/getsops/sops/releases)
```bash
# Download the binary (for Linux AMD64)
curl -LO https://github.com/getsops/sops/releases/download/v3.9.4/sops-v3.9.4.linux.amd64
# Move the binary into your PATH
mv sops-v3.9.4.linux.amd64 /usr/local/bin/sops
# Make the binary executable
chmod +x /usr/local/bin/sops

# Or on macOS with Homebrew:
# brew install sops age
```

## 2. Generate an Age Key Pair
```bash
# Generate a new private/public key file
age-keygen -o age.key

# The public key looks like: age1ql3z7hjy...
# The secret key looks like: AGE-SECRET-KEY-1...
```

## 3. Configure Your Environment
```bash
# Tell SOPS where to find the private key for decryption
export SOPS_AGE_KEY_FILE=./age.key

# Or for CI/CD runners (like GitLab Variables):
# export SOPS_AGE_KEY="AGE-SECRET-KEY-1..."
```

## 4. Encrypting & Decrypting Machine Configs & Talosconfig
```bash
# Encrypt machine config and talosconfig using the recipient public key
sops --encrypt --age <PUBLIC_AGE_KEY> worker-pi5.yaml > worker-pi5.enc.yaml
sops --encrypt --age <PUBLIC_AGE_KEY> talosconfig > talosconfig.enc

# Decrypt back into YAML
sops -d worker-pi5.enc.yaml > /tmp/worker-pi5.yaml
sops -d talosconfig.enc > /tmp/talosconfig
```
