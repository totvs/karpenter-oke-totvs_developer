output "oke_vcn_id" {
  description = "VCN ID created/used by the OKE module"
  value       = module.oke.vcn_id
}

output "oke_subnet_ids" {
  description = "OKE subnet IDs (cp, worker, int_lb, pub_lb, pod)"
  value       = module.oke.subnet_ids
}

output "oke_nsg_ids" {
  description = "OKE NSG IDs (cp, worker, int_lb, pub_lb, pod)"
  value       = module.oke.nsg_ids
}

output "oke_ig_route_id" {
  description = "Route table ID for Internet Gateway in OKE VCN"
  value       = module.oke.ig_route_id
}

output "oke_nat_route_id" {
  description = "Route table ID for NAT Gateway in OKE VCN"
  value       = module.oke.nat_route_id
}

output "oke_drg_id" {
  description = "DRG ID from OKE module (if created or provided)"
  value       = module.oke.drg_id
}
