variable ssh_auth_sock {
  type        = string
  description = "ssh agent auth sock"
}

variable name {
  type        = string
  description = "Stack name"
}

variable region {
  type        = string
  description = "Openstack region"
}

variable cloud_name {
  type        = string
  description = "Openstack cloud name (see clouds.yaml)"
}

variable ovh_secret_path {
  type        = string
  description = "Path to the JSON file containing the OVH API credentials to use"
}

variable remote_ssh_prefixes {
  type        = set(string)
  description = "ipv4 prefixes allowed to connect to the ssh bastion host"
  default     = ["0.0.0.0/0"]
}

variable remote_ip_prefixes {
  description = "ipv4 prefixes allowed to connect to the nodes through standard ports"
  default     = ["0.0.0.0/0"]
}

variable cloudvm_nb {
  type        = number
  description = "Number of Cloud VM"
  default     = 1
}

variable baremetal_hosts {
  type        = set(string)
  description = "Baremetal hosts defined as service_name: hostname"
  default = []
}

variable vlan_id {
  description = "Vrack vlan id"
  default     = 1004
}

variable ssh_user {
  default = "centos"
}

variable image_name {
  default = "Centos 8"
}
