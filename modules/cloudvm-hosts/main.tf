data openstack_images_image_v2 image {
  name        = var.image_name
  most_recent = true
}

data openstack_networking_subnet_v2 ctrl {
  subnet_id    = var.ctrl_subnet_id
  ip_version   = 4
  dhcp_enabled = true
}

data openstack_networking_subnet_v2 pxe {
  subnet_id    = var.pxe_subnet_id
  ip_version   = 4
  dhcp_enabled = false
}

resource openstack_networking_port_v2 ctrl {
  count          = var.nb
  name           = "${var.name}_ctrl"
  network_id     = data.openstack_networking_subnet_v2.ctrl.network_id
  admin_state_up = "true"

  fixed_ip {
    subnet_id = data.openstack_networking_subnet_v2.ctrl.id
  }
}

resource openstack_networking_port_v2 pxe {
  count          = var.nb
  name           = "${var.name}_pxe"
  network_id     = data.openstack_networking_subnet_v2.pxe.network_id
  admin_state_up = "true"

  fixed_ip {
    subnet_id = data.openstack_networking_subnet_v2.pxe.id
    ip_address = cidrhost(data.openstack_networking_subnet_v2.pxe.cidr, count.index + 1)
  }
}

# Create instance
resource openstack_compute_instance_v2 node {
  count       = var.nb
  name        = "${var.name}-${format("%03d", count.index)}"
  image_id    = data.openstack_images_image_v2.image.id
  flavor_name = var.flavor_name
  key_pair    = var.keypair


  # ctrl port on ens3/eth0
  network {
    port           = openstack_networking_port_v2.ctrl[count.index].id
    access_network = true
  }

  # pxe port on ens4/eth1
  network {
    port           = openstack_networking_port_v2.pxe[count.index].id
    access_network = false
  }


  user_data = <<EOF
#cloud-config
write_files:
 - path: /etc/systemd/network/10-ens3.network
   permissions: '0644'
   content: |
    [Match]
    Name=ens3 eth0
    [Network]
    DHCP=ipv4
    [DHCP]
    # favor ens4 default routes over ens3
    RouteMetric=2048
 - path: /etc/systemd/network/20-ens4.network
   permissions: '0644'
   content: |
    [Match]
    Name=ens4 eth1
    [Network]
    Address=${openstack_networking_port_v2.pxe[count.index].all_fixed_ips[0]}
    Broadcast=${cidrnetmask(data.openstack_networking_subnet_v2.pxe.cidr)}
    DHCP=no
runcmd:
  - sed -i -e '/^PermitRootLogin/s/^.*$/PermitRootLogin no/' /etc/ssh/sshd_config
  - systemctl restart systemd-networkd sshd
EOF

  # This is to ensure SSH comes up
  provisioner "remote-exec" {
    inline = ["echo 'ssh up'"]

    connection {
      type         = "ssh"
      host         = self.access_ip_v4
      user         = var.ssh_user
      agent        = true
      bastion_host = var.bastion_host
      bastion_user = var.bastion_user
    }
  }
}
