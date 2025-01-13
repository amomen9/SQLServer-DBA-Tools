| **192.168.241.111** |
| ------------------------- |

| **192.168.241.112** |
| ------------------------- |

| **10.10.10.113** |
| ---------------------- |

**3.
![1736789306255](image/setup_MSSQL_multisubnet_AlwaysOn-Copy/1736789306255.png)
**

**4.
![1736789331807](image/setup_MSSQL_multisubnet_AlwaysOn-Copy/1736789331807.png)
**

**5.
![1736789357719](image/setup_MSSQL_multisubnet_AlwaysOn-Copy/1736789357719.png)
**

**6.
![1736789373022](image/setup_MSSQL_multisubnet_AlwaysOn-Copy/1736789373022.png)
**

A warning shows up:
![1736789392227](image/setup_MSSQL_multisubnet_AlwaysOn-Copy/1736789392227.png)

Storage validation is unimportant to us right now.
![1736789400726](image/setup_MSSQL_multisubnet_AlwaysOn-Copy/1736789400726.png)

This warning strongly recommends that the
link between our nodes is highly available and fault tolerant. We disregard it
for our test case.

**7.
![1736789420213](image/setup_MSSQL_multisubnet_AlwaysOn-Copy/1736789420213.png)
**

**8.
**Entering cluster IP
addresses for both subnets. Windows server failover cluster’s “Create Cluster Wizard”
automatically detects that your cluster is multi-subnet based on the nodes you
have added.
![1736789447908](image/setup_MSSQL_multisubnet_AlwaysOn-Copy/1736789447908.png)

If multiple subnets exist, all the subnets will be listed
here.

**9.
![1736789477875](image/setup_MSSQL_multisubnet_AlwaysOn-Copy/1736789477875.png)
**

**10.  **
![1736789501646](image/setup_MSSQL_multisubnet_AlwaysOn-Copy/1736789501646.png)

**11.  **
![1736789523986](image/setup_MSSQL_multisubnet_AlwaysOn-Copy/1736789523986.png)

## Setting up the AlwaysOn Availability group role for the cluster:

**1.
![1736789549757](image/setup_MSSQL_multisubnet_AlwaysOn-Copy/1736789549757.png)
**

**2.
![1736789573225](image/setup_MSSQL_multisubnet_AlwaysOn-Copy/1736789573225.png)
2. In the “New Availability Group” wizard, listener IP addresses for both subnets should be
defined:

![1736789573225](image/setup_MSSQL_multisubnet_AlwaysOn-Copy/1736789573225.png)The rest of the configurations are very similar to single-subnet

Availability Group configurations.

·
**Conclusion and notable points in contrast with the
single-subnet Availability Group:**

After joining the secondary subnet servers to the domain,
the cluster and AlwaysOn AG can be created as normal with the following new
concepts:

When setting the IP for the
cluster, you have to set an IP for each subnet (Overall 2 IPs). The
functionality of these IPs has been explained in the “Some details about the
cluster and listener behaviors” section. As noted, only one of these two IP
addresses can be online at the same time in the cluster.

When setting up a listener
for the AG, you have to specify a listener IP for each subnet (Overall 2 IPs).
As noted, only one of these two IP addresses can be online at the same time in
the cluster.
