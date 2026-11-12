# Archived Terraform Exploration (siderolabs/talos)

> [!NOTE]
> **Archival Note / Why this is deprecated for our Edge Lab:**
> This configuration demonstrates how Sidero Labs' official Terraform provider (`siderolabs/talos`) can be used to generate PKI and inject machine configs. While this pattern is excellent for cloud environments (AWS/Azure) or hypervisors (Proxmox/vSphere) where Terraform provisions the underlying virtual machines, we decided against using it for our physical bare-metal edge lab in favor of a Git repo and native `talosctl`s.
>
> **The Reason:** On physical bare metal, Terraform cannot create or destroy physical hardware. Wrapping physical boards in a `terraform.tfstate` file introduces unnecessary state-locking, drift, and network dependency issues on an intermittently connected edge. Treating our Git repository as the source of truth and using native `talosctl` commands (`talosctl apply-config`, `talosctl patch mc`, `talosctl upgrade`) gives us pure, stateless GitOps without the state file baggage.

```hcl
resource "talos_machine_secrets" "this" {}

data "talos_machine_configuration" "this" {
  cluster_name     = "example-cluster"
  machine_type     = "controlplane"
  cluster_endpoint = "https://cluster.local:6443"
  machine_secrets  = talos_machine_secrets.this.machine_secrets
}

data "talos_client_configuration" "this" {
  cluster_name         = "example-cluster"
  client_configuration = talos_machine_secrets.this.client_configuration
  nodes                = ["10.5.0.2"]
}

resource "talos_machine_configuration_apply" "this" {
  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.this.machine_configuration
  node                        = "10.5.0.2"
  config_patches = [
    yamlencode({
      machine = {
        install = {
          disk  = "/dev/sdd"
          image = "ghcr.io/siderolabs/installer:v1.12.6"
        }
      }
    })
  ]
}
```