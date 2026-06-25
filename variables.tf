variable "compartment_ocid" {
  description = "OCID do compartment"
  type        = string
}

variable "region" {
  description = "OCI Region"
  type        = string
  default     = "sa-saopaulo-1"
}

variable "k8s_version" {
  description = "Kubernetes version"
  type        = string
  default     = "v1.32.1"
}

variable "environment" {
  type    = string
  default = "lab"
}

variable "cluster_name" {
  type    = string
  default = "cluster-lab"
}

variable "tenancy_ocid" {
  type = string
}

variable "user_ocid" {
  description = "User OCID"
  type        = string
  sensitive   = true
}

variable "fingerprint" {
  description = "API Key fingerprint"
  type        = string
  sensitive   = true
}

variable "private_key_path" {
  description = "Private key path"
  type        = string
  sensitive   = true
}

variable "ssh_public_key" {
  description = "Optional SSH public key to inject into resources that need admin SSH access. Leave empty to disable."
  type        = string
  default     = ""
}

variable "oke_vcn_id" {
  description = "VCN OCID used by the OKE module (leave empty to create a new VCN)"
  type        = string
  default     = ""
}

variable "oke_node_shape" {
  description = "Shape used by the OKE worker node pool"
  type        = string
}

variable "oke_node_ocpus" {
  description = "OCPUs for the OKE worker node pool"
  type        = number
}

variable "oke_node_memory_in_gbs" {
  description = "Memory (GB) for the OKE worker node pool"
  type        = number
}

variable "oke_node_pool_size" {
  description = "Number of nodes in the OKE worker pool"
  type        = number
}

variable "oke_node_boot_volume_size" {
  description = "Boot volume size (GB) for the OKE worker nodes"
  type        = number
}

variable "oke_vcn_cidrs" {
  description = "CIDR blocks usados pela VCN do OKE"
  type        = list(string)
  default     = ["10.0.0.0/16"]
}

variable "oke_subnets" {
  description = "Mapa de subnets (netnum/newbits) para o módulo OKE"
  type        = map(any)
  default = {
    bastion  = { netnum = 0, newbits = 13 }
    operator = { netnum = 1, newbits = 13 }
    cp       = { netnum = 2, newbits = 13 }
    int_lb   = { netnum = 16, newbits = 11 }
    pub_lb   = { netnum = 17, newbits = 11 }
    workers  = { netnum = 1, newbits = 2 }
    pods     = { netnum = 2, newbits = 2 }
    fss      = { netnum = 18, newbits = 11 }
  }
}

variable "oke_cni_type" {
  description = "CNI do OKE (flannel ou npn)"
  type        = string
  default     = "flannel"
}

variable "oke_pods_cidr" {
  description = "CIDR de pods do cluster OKE"
  type        = string
  default     = "10.244.0.0/16"
}

variable "oke_services_cidr" {
  description = "CIDR de services do cluster OKE"
  type        = string
  default     = "10.96.0.0/16"
}

variable "oke_node_pool_image_type" {
  description = "Tipo de imagem do node pool (oke, platform ou custom)"
  type        = string
  default     = "oke"
}

variable "oke_node_pool_image_name" {
  description = "Nome da imagem do node pool (override opcional)"
  type        = string
  default     = ""
}

variable "oke_node_pool_image_id" {
  description = "OCID da imagem do node pool (override opcional)"
  type        = string
  default     = ""
}

variable "oke_node_pool_os_version" {
  description = "Versão do Oracle Linux para o node pool"
  type        = string
  default     = ""
}

variable "oke_control_plane_allowed_cidrs" {
  description = "CIDR blocks allowed to access the OKE control plane endpoint"
  type        = list(string)
  default     = []
}

variable "oke_allow_worker_internet_access" {
  description = "Allow worker nodes egress to the internet"
  type        = bool
  default     = false
}

variable "oke_allow_pod_internet_access" {
  description = "Allow pod egress to the internet (when using NPN CNI)"
  type        = bool
  default     = false
}

variable "oke_allow_worker_icmp_egress" {
  description = "Allow worker nodes to send ICMP (ping) to the internet"
  type        = bool
  default     = false
}