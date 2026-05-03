terraform {
  required_version = ">= 1.6.0"
  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.48"
    }
  }
}

provider "hcloud" {
  token = var.hcloud_token
}

locals {
  public_web_ports = {
    "80"  = var.allow_http
    "443" = var.allow_https
  }
}

resource "hcloud_firewall" "fw" {
  name = "${var.server_name}-fw"

  # SSH restricted to a narrow allow-list (bootstrap /32).
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "22"
    source_ips = var.ssh_source_ips
  }

  dynamic "rule" {
    for_each = { for port, enabled in local.public_web_ports : port => enabled if enabled }
    content {
      direction  = "in"
      protocol   = "tcp"
      port       = rule.key
      source_ips = ["0.0.0.0/0", "::/0"]
    }
  }
}

resource "hcloud_server" "vps" {
  name        = var.server_name
  image       = var.image
  server_type = var.server_type
  location    = var.location

  firewall_ids = [hcloud_firewall.fw.id]
  ssh_keys     = var.ssh_key_names
}

output "public_ipv4" {
  value = hcloud_server.vps.ipv4_address
}
