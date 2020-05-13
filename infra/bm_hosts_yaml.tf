data ovh_dedicated_server ns {
  for_each = var.baremetal_hosts
  service_name = each.key
}

locals {

  bm_hosts = {
    for s in data.ovh_dedicated_server.ns:
    s.service_name => {
      apiVersion =  "metal3.io/v1alpha1"
      kind =  "BareMetalHost"
      metadata = {
        name =  s.service_name
        namespace = "metal3"
      }

      spec = {
        bmc = {
          address =  "ovh://${s.service_name}"
          credentialsName =  s.service_name
        }
        bootMACAddress = [
          for vni in s.vnis: vni.nics[0] if vni.mode == "vrack"
        ][0]

        online = true

        userData = {
          name = s.service_name
          namespace = "metal3"
        }

        image = {
          url = "http://10.0.0.1:6180/images/focal-server-cloudimg-amd64.img"
          checksum = "6cf35c51a565a8821a5c5e8b73196b2e"
        }
      }
    }
  }

  bm_hosts_secrets = {
    for s in data.ovh_dedicated_server.ns:
    s.service_name => {
      apiVersion=  "v1"
      kind = "Secret"
      metadata = {
        name = s.service_name
        namespace = "metal3"
      }
      type =  "Opaque"
      data = {
        username = base64encode("dummy")
        password = base64encode("dummy")

        userData = base64encode(<<EOF
#cloud-config
ssh_authorized_keys:
 - ${tls_private_key.private_key.public_key_openssh}
write_files:
 - path: /etc/systemd/network/10-vrack.network
   permissions: '0644'
   content: |
    [Match]
    Name=*
    MACAddress=${[ for vni in s.vnis: vni.nics[0] if vni.mode == "vrack" ][0]}
    [Network]
    DHCP=ipv4
    [DHCP]
    # favor public default routes over vrack
    RouteMetric=2048
 - path: /etc/systemd/network/20-pub.network
   permissions: '0644'
   content: |
    [Match]
    Name=*
    MACAddress=${[for vni in s.vnis: vni.nics[0] if vni.mode == "public" ][0]}
    [Network]
    #Address=${s.ip}
    DHCP=yes
runcmd:
  - sed -i -e '/^PermitRootLogin/s/^.*$/PermitRootLogin no/' /etc/ssh/sshd_config
  - systemctl restart systemd-networkd sshd
EOF
          )
        networkData = ""
        metaData = ""
      }
    }
  }
}
