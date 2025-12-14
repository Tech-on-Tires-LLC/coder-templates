terraform {
  required_version = ">= 1.4.0"

  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 0.21.0"
    }
    vultr = {
      source  = "vultr/vultr"
      version = ">= 2.19.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = ">= 4.0.0"
    }
  }
}

provider "coder" {}

provider "vultr" {
  api_key = var.vultr_api_key
}

/*** Coder workspace context ***/
data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

/*** Parameters exposed in Coder UI ***/
variable "vultr_api_key" {
  description = "Vultr API key (use Coder parameter / secret)."
  type        = string
  sensitive   = true
}

variable "region" {
  description = "Vultr region ID (e.g. dfw, ewr, lax)."
  type        = string
  default     = "atl"
}

variable "plan" {
  description = "Vultr compute plan ID (e.g. vc2-1c-2gb or vc2-1c-1gb)."
  type        = string
  default     = "vc2-1c-2gb"
}

variable "os_id" {
  description = "Vultr OS ID (e.g. 1743 for Ubuntu 22.04 x64, 2657 for Ubuntu 25.10 x64)."
  type        = number
  default     = 2657
}

/*** SSH key injected into the VM at provision time ***/
resource "tls_private_key" "workspace" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "vultr_ssh_key" "workspace" {
  name    = "coder-${data.coder_workspace_owner.me.name}-${data.coder_workspace.me.name}"
  ssh_key = tls_private_key.workspace.public_key_openssh
}

/*** Coder agent definition ***/
resource "coder_agent" "dev" {
  arch = "amd64"
  os   = "linux"
  dir  = "/home/coder"

  display_apps {
    web_terminal = true
    vscode       = true
    ssh_helper   = true
  }

  # Runs on the VM after the agent connects.
  # The agent runs as the 'coder' user, so this script runs as 'coder'.
  startup_script = <<-EOT
    #!/usr/bin/env bash
    set -eu

    # Install code-server (VS Code in browser) if not present
    if ! command -v code-server >/dev/null 2>&1; then
      curl -fsSL https://code-server.dev/install.sh | sh
    fi

    # Create project directory
    mkdir -p ~/project
  EOT

  env = {
    GIT_AUTHOR_NAME      = data.coder_workspace_owner.me.name
    GIT_AUTHOR_EMAIL     = data.coder_workspace_owner.me.email
    GIT_COMMITTER_NAME   = data.coder_workspace_owner.me.name
    GIT_COMMITTER_EMAIL  = data.coder_workspace_owner.me.email
  }

  metadata {
    key          = "provider"
    display_name = "Provider"
    script       = "echo Vultr"
    interval     = 3600
    timeout      = 5
    order        = 10
  }

  metadata {
    key          = "region"
    display_name = "Region"
    script       = "echo ${var.region}"
    interval     = 3600
    timeout      = 5
    order        = 11
  }
}

/*** Vultr firewall for Coder workspace ***/
resource "vultr_firewall_group" "workspace" {
  description = "Coder workspace firewall"
}

# Allow SSH access to the instance (adjust subnet/subnet_size as needed to lock down access).
resource "vultr_firewall_rule" "workspace_ssh" {
  firewall_group_id = vultr_firewall_group.workspace.id

  protocol = "tcp"
  port     = "22"

  ip_type     = "v4"
  subnet      = "0.0.0.0"
  subnet_size = 0
}

# (Optional) Allow ICMP (ping) so the instance is reachable for diagnostics.
resource "vultr_firewall_rule" "workspace_icmp" {
  firewall_group_id = vultr_firewall_group.workspace.id

  protocol = "icmp"

  ip_type     = "v4"
  subnet      = "0.0.0.0"
  subnet_size = 0
}

/*** Vultr instance ***/
resource "vultr_instance" "workspace" {
  region      = var.region
  plan        = var.plan
  os_id       = var.os_id
  label       = "coder-${data.coder_workspace_owner.me.name}-${data.coder_workspace.me.name}"
  hostname    = "coder-${data.coder_workspace.me.name}"
  enable_ipv6 = true
  backups     = "disabled"

  ssh_key_ids       = [vultr_ssh_key.workspace.id]
  firewall_group_id = vultr_firewall_group.workspace.id

  # Cloud-init: create 'coder' user and run agent via systemd.
  user_data = <<-CLOUDINIT
    #cloud-config
    users:
      - name: coder
        sudo: ["ALL=(ALL) NOPASSWD:ALL"]
        groups: sudo
        shell: /bin/bash
    packages:
      - curl
      - git
    write_files:
      - path: /opt/coder/init
        permissions: "0755"
        encoding: b64
        content: ${base64encode(coder_agent.dev.init_script)}
      - path: /etc/systemd/system/coder-agent.service
        permissions: "0644"
        content: |
          [Unit]
          Description=Coder Agent
          After=network-online.target
          Wants=network-online.target

          [Service]
          User=coder
          ExecStart=/opt/coder/init
          Environment=CODER_AGENT_TOKEN=${coder_agent.dev.token}
          Restart=always
          RestartSec=10
          TimeoutStopSec=90
          KillMode=process
          OOMScoreAdjust=-900
          SyslogIdentifier=coder-agent

          [Install]
          WantedBy=multi-user.target
    runcmd:
      - chown coder:coder /home/coder
      - systemctl enable coder-agent
      - systemctl start coder-agent
  CLOUDINIT
}

# See https://registry.coder.com/modules/coder/code-server
module "code-server" {
  count  = data.coder_workspace.me.start_count
  source = "registry.coder.com/coder/code-server/coder"

  # This ensures that the latest non-breaking version of the module gets downloaded, you can also pin the module version to prevent breaking changes in production.
  version = "~> 1.0"

  agent_id = coder_agent.dev.id
  order    = 1
}
