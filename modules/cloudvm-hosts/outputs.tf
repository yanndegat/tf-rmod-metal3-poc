output "hosts" {
  description = "List of hosts"
  value = [
    for s in openstack_compute_instance_v2.node[*] :
    {
      id        = s.id
      name      = s.name
      ctrl_ipv4 = [for i in s.network : i.fixed_ip_v4 if i.access_network][0]
      pxe_ipv4  = [for i in s.network : i.fixed_ip_v4 if i.access_network][0]
    }
  ]
}
