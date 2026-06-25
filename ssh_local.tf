locals {
  # Read the operator's public key from the default path on the workstation running
  # terraform. This keeps function calls out of tfvars files (which are limited to
  # literal values).
  ssh_public_key_file = trimspace(file("/****/*****/.ssh/id_rsa.pub"))
}
