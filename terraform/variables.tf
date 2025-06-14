variable "admin_username" {
  description = "Admin username for the VM"
  default     = "azureuser"
}

variable "ssh_public_key_path" {
  description = "Path to your public key file"
  default     = "~/.ssh/azure-vm-key.pub"
}
