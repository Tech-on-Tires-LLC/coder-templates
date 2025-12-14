# Coder Workspace on Vultr

This Terraform template provisions a Coder development workspace on Vultr.

## Features

- **Vultr Instance**: Provisions a virtual machine on Vultr.
- **Firewall**: Configures a firewall to allow SSH and ICMP.
- **Coder Agent**: Automatically installs and starts the Coder agent.
- **Code Server**: Installs `code-server` (VS Code in the browser).
- **SSH Access**: Injects a generated SSH key for secure access.
- **Persistence**: The workspace runs on a persistent VM (until destroyed).

## Prerequisites

- **Coder**: A running Coder deployment.
- **Vultr Account**: You need a Vultr account.
- **Vultr API Key**: An API key from Vultr with permissions to manage instances, SSH keys, and firewalls.

## Usage

1.  **Create a Template in Coder**:
    - Go to your Coder deployment.
    - Create a new template.
    - Upload this `main.tf` file (or the directory containing it).

2.  **Create a Workspace**:
    - Use the template to create a new workspace.
    - You will be prompted to enter your **Vultr API Key**.
    - Optionally, you can customize the **Region**, **Plan**, and **OS ID**.

## Variables

| Name | Description | Type | Default |
|------|-------------|------|---------|
| `vultr_api_key` | **Required**. Your Vultr API Key. | `string` | N/A |
| `region` | Vultr region ID (e.g., `atl`, `dfw`, `ewr`). | `string` | `atl` |
| `plan` | Vultr compute plan ID (e.g., `vc2-1c-2gb`). | `string` | `vc2-1c-2gb` |
| `os_id` | Vultr OS ID. | `number` | `2657` |

## Resources Created

- `vultr_instance`: The compute instance.
- `vultr_firewall_group`: Firewall group for the workspace.
- `vultr_ssh_key`: SSH key for the workspace.
- `tls_private_key`: Ephemeral private key for the session/workspace.

## Customization

You can modify the `main.tf` file to:
- Change the default region or plan.
- Add more packages to the `cloud-init` user data.
- Adjust firewall rules (e.g., restrict SSH to a specific IP).
