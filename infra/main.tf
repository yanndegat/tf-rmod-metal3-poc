terraform {
  required_version = ">= 0.12.0"
  required_providers {
    openstack = ">= 1.20"
    #    ovh = ">= 0.8"
    tls   = "~> 2.1"
    null  = "~> 2.1"
    local = "~> 1.4"
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
  cloud  = var.cloud_name
  region = var.region
}

###
# Create the ssh key pair in both openstack & ovh api
###
resource tls_private_key private_key {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource null_resource ssh_agent_register {
  triggers = {
    always = timestamp()
  }

  provisioner "local-exec" {
    environment = {
      key           = base64encode(tls_private_key.private_key.private_key_pem)
      SSH_AUTH_SOCK = var.ssh_auth_sock
    }
    command = "echo $${key} | base64 -d | ssh-add -"
  }
}

# Keypair which will be used on nodes and bastion
resource openstack_compute_keypair_v2 keypair {
  name       = var.name
  public_key = tls_private_key.private_key.public_key_openssh
}

###
# Network & bastion setup
# The openstack network will host the subnet config and the according dhcp agent
###
module "network" {
  source  = "../modules/network"
  name    = var.name
  vlan_id = var.vlan_id
  region  = var.region

  remote_ssh_prefixes = var.remote_ssh_prefixes
  ssh_keypair         = openstack_compute_keypair_v2.keypair.name
}

###
# Create cloud vms
###
module "metal3-sg" {
  source = "../modules/secgroup"
  name   = var.name
  # dont forget to add docker ip range
  allowed_ingress_prefixes = var.remote_ip_prefixes
  allowed_ingress_tcp      = ["6443"]
  allowed_ssh_sg_ids       = [module.network.bastion_sg_id]
  allowed_sg_ids           = [module.network.bastion_sg_id]
}

module "metal3-nodes" {
  source         = "../modules/cloudvm-hosts"
  image_name     = var.image_name
  ssh_user       = var.ssh_user
  nb             = var.cloudvm_nb
  name           = var.name
  ctrl_subnet_id = module.network.ctrl_subnet_id
  pxe_subnet_id  = module.network.pxe_subnet_id
  secgroup_id    = module.metal3-sg.id
  keypair        = openstack_compute_keypair_v2.keypair.name
  bastion_host   = module.network.bastion_ipv4
}

resource null_resource install_microk8s {
  triggers = {
    server_id = module.metal3-nodes.hosts[0].id
  }


  provisioner "file" {
    connection {
      type         = "ssh"
      host         = module.metal3-nodes.hosts[0].ctrl_ipv4
      user         = var.ssh_user
      agent        = true
      bastion_host = module.network.bastion_ipv4
      bastion_user = "ubuntu"
    }

    source = "${path.module}/resources"
    destination = "/home/${var.ssh_user}/"
  }

  provisioner "file" {
    connection {
      type         = "ssh"
      host         = module.metal3-nodes.hosts[0].ctrl_ipv4
      user         = var.ssh_user
      agent        = true
      bastion_host = module.network.bastion_ipv4
      bastion_user = "ubuntu"
    }

    destination = "/home/${var.ssh_user}/resources/ironic_bmo_configmap.env"
    content = <<EOF
HTTP_PORT=6180
# centos
PROVISIONING_INTERFACE=eth1
# ubuntu
#PROVISIONING_INTERFACE=ens4
DHCP_RANGE=10.0.2.20,10.0.2.30
DEPLOY_KERNEL_URL=http://10.0.0.1:6180/images/ironic-python-agent.kernel
DEPLOY_RAMDISK_URL=http://10.0.0.1:6180/images/ironic-python-agent.initramfs
IRONIC_ENDPOINT=http://10.0.0.1:6385/v1/
IRONIC_INSPECTOR_ENDPOINT=http://10.0.0.1:5050/v1/
CACHEURL=http://10.0.0.1:6180/images
IRONIC_FAST_TRACK=false
OVH_APPLICATION_KEY=${local.ovh_creds["application_key"]}
OVH_APPLICATION_SECRET=${local.ovh_creds["application_secret"]}
OVH_CONSUMER_KEY=${local.ovh_creds["consumer_key"]}
OVH_ENDPOINT=ovh-eu
OVH_POWEROFF_SCRIPT=poweroff.ipxe
OVH_BOOT_SCRIPT=boot.ipxe
EOF
  }

  provisioner "remote-exec" {
    connection {
      type         = "ssh"
      host         = module.metal3-nodes.hosts[0].ctrl_ipv4
      user         = var.ssh_user
      agent        = true
      bastion_host = module.network.bastion_ipv4
      bastion_user = "ubuntu"
    }

    inline = [
      "sudo dnf install -y epel-release && sudo dnf upgrade -y",
      "sudo yum install -y snapd && sudo systemctl enable --now snapd.socket",
      "sudo ln -s /var/lib/snapd/snap /snap",
      "sudo snap list microk8s || sudo snap install microk8s --classic --channel=1.18/stable",
      "sudo usermod -a -G microk8s $USER",
      "mkdir -p ~/.kube",
      "sudo chown -f -R $USER ~/.kube",
    ]
  }

}

resource null_resource install_postmicrok8s {
  triggers = {
    server_id = module.metal3-nodes.hosts[0].id
    microk8s = null_resource.install_microk8s.id
  }

  provisioner "remote-exec" {
    connection {
      type         = "ssh"
      host         = module.metal3-nodes.hosts[0].ctrl_ipv4
      user         = var.ssh_user
      agent        = true
      bastion_host = module.network.bastion_ipv4
      bastion_user = "ubuntu"
    }

    inline = [ "bash -x ~/resources/install.sh" ]
  }
}

resource null_resource install_bm_hosts_def {
  for_each = var.baremetal_hosts

  triggers = {
    server_id = module.metal3-nodes.hosts[0].id
    microk8s = null_resource.install_microk8s.id
  }

  provisioner "file" {
    connection {
      type         = "ssh"
      host         = module.metal3-nodes.hosts[0].ctrl_ipv4
      user         = var.ssh_user
      agent        = true
      bastion_host = module.network.bastion_ipv4
      bastion_user = "ubuntu"
    }

    destination = "/home/${var.ssh_user}/resources/${each.key}.yaml"
    content = <<EOF
---
${yamlencode(local.bm_hosts[each.key])}
---
${yamlencode(local.bm_hosts_secrets[each.key])}
EOF
  }
}

resource ovh_me_ipxe_script scripts {
  for_each = fileset("${path.module}/resources", "*.ipxe")
  name     = each.key
  script   = file("${path.module}/resources/${each.key}")
}


resource ovh_dedicated_server_update "disable_server_mon" {
  for_each = var.baremetal_hosts
  service_name = each.key

  monitoring = false

  lifecycle {
    ignore_changes = [boot_id]
  }

}
