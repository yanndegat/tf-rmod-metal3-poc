variable nb {
  description = "Number of nodes to be created"
}

variable name {
  description = "Prefix for the node resources"
}

variable flavor_name {
  description = "Flavor to be used for nodes"
  default     = "b2-7"
}

variable image_name {
  description = "Image to boot nodes from"
  default     = "Ubuntu 18.04"
}

variable keypair {
  description = "SSH keypair to inject in the instance (previosly created in OpenStack)"
}

variable ctrl_subnet_id {
  description = "Id of the network subnet to attach nodes to"
}

variable pxe_subnet_id {
  description = "Id of the network subnet to attach nodes to"
}

variable secgroup_id {
  description = "id of the security group for nodes"
}

variable ssh_user {
  description = "Ssh username"
  default     = "ubuntu"
}

variable bastion_host {
  description = "Ssh bastion host"
}

variable bastion_user {
  description = "Ssh username for bastion"
  default     = "ubuntu"
}
