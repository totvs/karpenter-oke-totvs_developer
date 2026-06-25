terraform {
  required_version = ">= 1.6"
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = ">= 7.31, < 8.0"
    }
  }
}

provider "oci" {
  tenancy_ocid     = var.tenancy_ocid
  user_ocid        = var.user_ocid
  fingerprint      = var.fingerprint
  private_key_path = var.private_key_path
  region           = var.region
}

provider "oci" {
  alias            = "home"
  tenancy_ocid     = var.tenancy_ocid
  user_ocid        = var.user_ocid
  fingerprint      = var.fingerprint
  private_key_path = var.private_key_path
  region           = var.region
}

data "oci_containerengine_node_pool_option" "node_pool_options" {
  node_pool_option_id = "all"
  compartment_id      = var.compartment_ocid
  node_pool_os_type   = "OL8"
}

locals {
  node_pool_image_matches = var.oke_node_pool_image_name != "" ? [
    for source in data.oci_containerengine_node_pool_option.node_pool_options.sources :
    source.image_id if source.source_name == var.oke_node_pool_image_name
  ] : []

  oke_node_pool_image_id   = var.oke_node_pool_image_id != "" ? var.oke_node_pool_image_id : (length(local.node_pool_image_matches) > 0 ? local.node_pool_image_matches[0] : "")
  oke_node_pool_image_type = local.oke_node_pool_image_id != "" ? "custom" : var.oke_node_pool_image_type
}

// Common locals used by modules in this root
// VCN and image IDs are provided via variables for easier environment configuration

module "oke" {
  source  = "oracle-terraform-modules/oke/oci"
  version = "~> 4.5.9"

  # provider mapping: map module-local provider names to root provider configurations
  providers = {
    oci      = oci
    oci.home = oci.home
  }

  tenancy_id  = var.tenancy_ocid
  region      = var.region
  home_region = var.region

  compartment_id     = var.compartment_ocid
  cluster_name       = var.cluster_name
  kubernetes_version = var.k8s_version
  cluster_type       = "enhanced"

  vcn_cidrs     = var.oke_vcn_cidrs
  subnets       = var.oke_subnets
  cni_type      = var.oke_cni_type
  pods_cidr     = var.oke_pods_cidr
  services_cidr = var.oke_services_cidr

  node_pool_image_type = local.oke_node_pool_image_type
  node_pool_image_id   = local.oke_node_pool_image_id
  node_pool_os_version = var.oke_node_pool_os_version



  availability_domains = {
    bastion  = 1
    operator = 2
    fss      = 1
  }

  node_pools = {
    workers = {
      shape            = var.oke_node_shape # recommended flexible shape
      ocpus            = var.oke_node_ocpus
      memory_in_gbs    = var.oke_node_memory_in_gbs
      node_pool_size   = var.oke_node_pool_size
      boot_volume_size = var.oke_node_boot_volume_size
    }
  }

  create_operator = false # Opcional: remove VM operator

  # Disable creating a bastion VM host (use managed bastion service or none)
  create_bastion_host = false

  # Control plane access (port 6443)
  control_plane_allowed_cidrs = var.oke_control_plane_allowed_cidrs

  # Worker/pod internet egress
  allow_worker_internet_access = var.oke_allow_worker_internet_access
  allow_pod_internet_access    = var.oke_allow_pod_internet_access

}

# Optional ICMP egress for worker nodes (useful for ping tests)
resource "oci_core_network_security_group_security_rule" "oke_workers_egress_icmp" {
  count                     = var.oke_allow_worker_icmp_egress ? 1 : 0
  network_security_group_id = module.oke.nsg_ids["workers"]
  description               = "Allow worker nodes ICMP egress to Internet"
  direction                 = "EGRESS"
  protocol                  = "1" # ICMP
  destination               = "0.0.0.0/0"
  destination_type          = "CIDR_BLOCK"
  stateless                 = false

  icmp_options {
    type = 8
    code = 0
  }
}


