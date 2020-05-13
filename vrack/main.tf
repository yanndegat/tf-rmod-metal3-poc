terraform {
  required_version = ">= 0.12.0"
  required_providers {
    openstack = ">= 1.20"
    ovh       = ">= 0.6"
  }
}

locals {
  ovh_creds = jsondecode(file(var.ovh_secret_path))
}

provider ovh {
  endpoint           = "ovh-eu"
  application_key    = local.ovh_creds["application_key"]
  application_secret = local.ovh_creds["application_secret"]
  consumer_key       = local.ovh_creds["consumer_key"]
}


provider openstack {
  region = var.region
  cloud  = var.cloud_name
}

###
### this scripts setups the vrack network
###
data openstack_identity_auth_scope_v3 os {
  name = var.name
}

data ovh_dedicated_server "server" {
  for_each     = var.dedicated_servers_ids
  service_name = each.key
}

resource ovh_vrack_dedicated_server_interface "vdsi" {
  for_each = var.dedicated_servers_ids

  vrack_id     = var.vrack_id
  interface_id = [for i in data.ovh_dedicated_server.server[each.key].vnis : i.uuid if i.mode == "vrack"][0]
}

resource ovh_vrack_cloudproject vrack_openstack {
  vrack_id   = var.vrack_id
  project_id = data.openstack_identity_auth_scope_v3.os.project_id
}

