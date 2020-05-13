variable region {
  description = "Openstack region"
}

variable cloud_name {
  description = "Openstack cloud name (see clouds.yaml)"
}

variable ovh_secret_path {
  description = "Path to the JSON file containing the OVH API credentials to use"
}

variable vrack_id {
  description = "id of the iplb"
}

variable dedicated_servers_ids {
  description = "service names of your dedicated servers"
  type        = set(string)
}

variable name {
  description = "Stack name"
  default     = "sd-metal3"
}
