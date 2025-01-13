# Appendix:

## **1.****Some details about ****the cluster and listener**** behaviors**

We know that the primary server holds the IP of the listener
on its interfaces, meaning that calling the listener’s IP address on the
network,  **results in the primary server responding** .

ipconfig on the primary server of our example:

| Listener |
| -------- |

![1736794588382](image/setup_MSSQL_multisubnet_AlwaysOn-Copy(2)/1736794588382.png)

IP of the cluster will also be assigned to the interface of
one of the servers which is usually the primary server but not necessarily. This is an example of a same-subnet
secondary replica holding the cluster IP address:

| Cluster |
| ------- |

![1736794690093](image/setup_MSSQL_multisubnet_AlwaysOn-Copy(2)/1736794690093.png)

The cluster and the listener in this cluster will have 2 IP
addresses each. When the primary server is on subnet 241, the secondary subnet
listener IP address will be offline:

![1736795622794](image/setup_MSSQL_multisubnet_AlwaysOn-Copy(2)/1736795622794.png)

After failover to the second subnet:

![1736795651979](image/setup_MSSQL_multisubnet_AlwaysOn-Copy(2)/1736795651979.png)

However, regarding the cluster, it is reluctant to change
its IP address and the host of its IP address by a mere failover. It is even
reluctant to switch to another subnet so long as a healthy node on the same
subnet of the current failing node exists. In our example the primary was at
first Node1, then Node3, but the cluster IP address remained on Node2. It was
on Node2 due to earlier circumstances.

But when all the nodes on the primary subnet failed, the
cluster IP address also switched to the second subnet:

![1736795688921](image/setup_MSSQL_multisubnet_AlwaysOn-Copy(2)/1736795688921.png)

![1736795697520](image/setup_MSSQL_multisubnet_AlwaysOn-Copy(2)/1736795697520.png)

Note that obviously both cluster and listener can only be
online on 1 subnet at the same time, i.e. when they are online on one subnet,
they will be offline on the other one. So, in order for the disaster recovery
node to serve the application, either an IP forwarding service must redirect
the requests to 192.168.241.115 to 10.10.10.115, or the application connection
string must point to this new listener IP address with a different subnet.

When Node1 and Node2 failed and the AG automatically failed over to Node3:

![1736795744514](image/setup_MSSQL_multisubnet_AlwaysOn-Copy(2)/1736795744514.png)

The interface of Node3 has 3 IP addresses above.

## **2.****Testing Availability Group:

**

Logically there will be no difference between any of the
nodes in this cluster in terms of being primary, synchronous, asynchronous,
automatic failover, etc.

| Disaster Node |
| ------------- |

![1736795855762](image/setup_MSSQL_multisubnet_AlwaysOn-Copy(2)/1736795855762.png)

All failover scenarios were tested. (Automatic failover,
manual failover, manual forced failover to the disaster recovery node, etc.)


END  ![1736795907385](image/setup_MSSQL_multisubnet_AlwaysOn-Copy(2)/1736795907385.png)
