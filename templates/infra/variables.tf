variable "hcloud_token" {
  type      = string
  sensitive = true
}

variable "server_name" { type = string }
variable "image" { type = string }
variable "server_type" { type = string }
variable "location" { type = string }

variable "ssh_key_names" {
  type        = list(string)
  description = "Names of SSH keys as shown in Hetzner Cloud Console."
}

variable "ssh_source_ips" {
  type        = list(string)
  description = "Allowed source IP ranges for SSH to port 22 (bootstrap /32)."
}

variable "allow_http" {
  type        = bool
  default     = false
  description = "Expose TCP/80 at the Hetzner firewall."
}

variable "allow_https" {
  type        = bool
  default     = false
  description = "Expose TCP/443 at the Hetzner firewall."
}
