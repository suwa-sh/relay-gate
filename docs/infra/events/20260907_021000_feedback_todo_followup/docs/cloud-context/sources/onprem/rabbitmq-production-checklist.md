---
source_url: "https://www.rabbitmq.com/docs/production-checklist"
fetched_at: "2026-08-30T10:05:32Z"
vendor: "onprem"
layer: "product"
---

:::::::::::::::::::::::::::::::: {.docMainContainer_TBSr role="main"}
::::::::::::::::::::::::::::::: {.container .padding-top--md .padding-bottom--lg}
:::::::::::::::::::::::::::::: row
::::::::::::::::::::::::::: {.col .docItemCol_VOVn}
:::::::::::::::::::::::::: docItemContainer_Djhp
[Version: 4.3]{.theme-doc-version-badge .badge .badge--secondary}

::: {.tocCollapsible_ETCw .theme-doc-toc-mobile .tocMobile_ITEo}
On this page
:::

:::::::::::::::::::::::: {.theme-doc-markdown .markdown}
## Overview[​](#overview "Direct link to Overview"){.hash-link aria-label="Direct link to Overview" translate="no"} {#overview .anchor .anchorTargetStickyNavbar_Vzrq}

Data services such as RabbitMQ often have many tunable parameters. Some configurations or practices make a lot of sense for development but are not really suitable for production. No single configuration fits every use case. It is, therefore, important to assess system configuration and have a plan for \"day two operations\" activities such as [upgrades](/docs/upgrade) before going into production.

## Table of Contents[​](#toc "Direct link to Table of Contents"){.hash-link aria-label="Direct link to Table of Contents" translate="no"} {#toc .anchor .anchorTargetStickyNavbar_Vzrq}

Production systems have concerns that go beyond configuration: system observability, security, application development practices, resource usage, [release support timeline](/release-information), and more.

[Monitoring](/docs/monitoring) and metrics are the foundation of a production-grade system. Besides helping detect issues, it provides the operator data that can be used to size and configure both RabbitMQ nodes and applications.

This guide provides recommendations in a few areas:

- [Storage](#storage) considerations for node data directories
- [Networking](#networking)-related recommendations
- Recommendations related to [virtual hosts, users and permissions](#users-and-permissions)
- [Monitoring and resource usage](#monitoring-and-resource-usage)
- [Configurable limits](#limits)
- [Security](#security)
- [Clustering](#clustering) and multi-node deployments
- [Application-level](#apps) practices and considerations

and more.

## Minimum Hardware Requirements[​](#minimum-hardware "Direct link to Minimum Hardware Requirements"){.hash-link aria-label="Direct link to Minimum Hardware Requirements" translate="no"} {#minimum-hardware .anchor .anchorTargetStickyNavbar_Vzrq}

RabbitMQ can used with a broad range of workloads. Some may be very I/O heavy (streams), others can require more CPU resources (large number of concurrent connections and queues). Those workloads may require a different mix of CPU, storage and network resources.

::::: {.theme-admonition .theme-admonition-tip .admonition_xJq3 .alert .alert--success}
::: admonitionHeading_Gvgb
[ ![](data:image/svg+xml;base64,PHN2ZyB2aWV3Ym94PSIwIDAgMTIgMTYiPgo8cGF0aCBmaWxsLXJ1bGU9ImV2ZW5vZGQiIGQ9Ik02LjUgMEMzLjQ4IDAgMSAyLjE5IDEgNWMwIC45Mi41NSAyLjI1IDEgMyAxLjM0IDIuMjUgMS43OCAyLjc4IDIgNHYxaDV2LTFjLjIyLTEuMjIuNjYtMS43NSAyLTQgLjQ1LS43NSAxLTIuMDggMS0zIDAtMi44MS0yLjQ4LTUtNS41LTV6bTMuNjQgNy40OGMtLjI1LjQ0LS40Ny44LS42NyAxLjExLS44NiAxLjQxLTEuMjUgMi4wNi0xLjQ1IDMuMjMtLjAyLjA1LS4wMi4xMS0uMDIuMTdINWMwLS4wNiAwLS4xMy0uMDItLjE3LS4yLTEuMTctLjU5LTEuODMtMS40NS0zLjIzLS4yLS4zMS0uNDItLjY3LS42Ny0xLjExQzIuNDQgNi43OCAyIDUuNjUgMiA1YzAtMi4yIDIuMDItNCA0LjUtNCAxLjIyIDAgMi4zNi40MiAzLjIyIDEuMTlDMTAuNTUgMi45NCAxMSAzLjk0IDExIDVjMCAuNjYtLjQ0IDEuNzgtLjg2IDIuNDh6TTQgMTRoNWMtLjIzIDEuMTQtMS4zIDItMi41IDJzLTIuMjctLjg2LTIuNS0yeiIgLz4KPC9zdmc+) ]{.admonitionIcon_Rf37}tip
:::

::: admonitionContent_BuS1
This section describes a recommended minimum of resources for production systems.
:::
:::::

Below is a minimum system requirements for production deployments, per node:

- No colocation with other data services (e.g. data stores) or disk, network I/O heavy applications
- 4 CPU cores
- 4 GiB of RAM
- See [Storage](#storage) below for storage

Lower-spec environments can be acceptable for certain less loaded environments, for quality assurance and development environments.

::::: {.theme-admonition .theme-admonition-danger .admonition_xJq3 .alert .alert--danger}
::: admonitionHeading_Gvgb
[ ![](data:image/svg+xml;base64,PHN2ZyB2aWV3Ym94PSIwIDAgMTIgMTYiPgo8cGF0aCBmaWxsLXJ1bGU9ImV2ZW5vZGQiIGQ9Ik01LjA1LjMxYy44MSAyLjE3LjQxIDMuMzgtLjUyIDQuMzFDMy41NSA1LjY3IDEuOTggNi40NS45IDcuOThjLTEuNDUgMi4wNS0xLjcgNi41MyAzLjUzIDcuNy0yLjItMS4xNi0yLjY3LTQuNTItLjMtNi42MS0uNjEgMi4wMy41MyAzLjMzIDEuOTQgMi44NiAxLjM5LS40NyAyLjMuNTMgMi4yNyAxLjY3LS4wMi43OC0uMzEgMS40NC0xLjEzIDEuODEgMy40Mi0uNTkgNC43OC0zLjQyIDQuNzgtNS41NiAwLTIuODQtMi41My0zLjIyLTEuMjUtNS42MS0xLjUyLjEzLTIuMDMgMS4xMy0xLjg5IDIuNzUuMDkgMS4wOC0xLjAyIDEuOC0xLjg2IDEuMzMtLjY3LS40MS0uNjYtMS4xOS0uMDYtMS43OEM4LjE4IDUuMzEgOC42OCAyLjQ1IDUuMDUuMzJMNS4wMy4zbC4wMi4wMXoiIC8+Cjwvc3ZnPg==) ]{.admonitionIcon_Rf37}danger
:::

::: admonitionContent_BuS1
RabbitMQ was not designed to run in environments with a single CPU core, or being colocated with other disk and network I/O-heavy tools.
:::
:::::

## Storage Considerations[​](#storage "Direct link to Storage Considerations"){.hash-link aria-label="Direct link to Storage Considerations" translate="no"} {#storage .anchor .anchorTargetStickyNavbar_Vzrq}

### Use Durable Storage[​](#storage-durability "Direct link to Use Durable Storage"){.hash-link aria-label="Direct link to Use Durable Storage" translate="no"} {#storage-durability .anchor .anchorTargetStickyNavbar_Vzrq}

::::: {.theme-admonition .theme-admonition-important .admonition_xJq3 .alert .alert--info}
::: admonitionHeading_Gvgb
[ ![](data:image/svg+xml;base64,PHN2ZyB2aWV3Ym94PSIwIDAgMTQgMTYiPgo8cGF0aCBmaWxsLXJ1bGU9ImV2ZW5vZGQiIGQ9Ik03IDIuM2MzLjE0IDAgNS43IDIuNTYgNS43IDUuN3MtMi41NiA1LjctNS43IDUuN0E1LjcxIDUuNzEgMCAwIDEgMS4zIDhjMC0zLjE0IDIuNTYtNS43IDUuNy01Ljd6TTcgMUMzLjE0IDEgMCA0LjE0IDAgOHMzLjE0IDcgNyA3IDctMy4xNCA3LTctMy4xNC03LTctN3ptMSAzSDZ2NWgyVjR6bTAgNkg2djJoMnYtMnoiIC8+Cjwvc3ZnPg==) ]{.admonitionIcon_Rf37}important
:::

::: admonitionContent_BuS1
Modern RabbitMQ features, such as [Khepri](/docs/metadata-store), [quorum queues](/docs/quorum-queues) and [streams](/docs/streams), are designed for durable storage only.
:::
:::::

Data safety features of [quorum queues](/docs/quorum-queues) and [streams](/docs/streams) expect node data storage to be durable. Both data structures also assume reasonably stable latency of I/O operations, something that network-attached storage will not be always ready to provide in practice.

Quorum queue and stream replicas hosted on restarted nodes that use transient storage will have to perform a full sync of the entire data set on the leader replica. This can result in massive data transfers and network link overload that could have been avoided by using durable storage.

When nodes are restarted, the rest of the cluster expects them to retain the information about their cluster peers. When this is not the case, restarted nodes may be able to rejoin as new nodes but a [special peer clean up mechanism](/docs/cluster-formation#node-health-checks-and-cleanup) would have to be enabled to remove their prior identities.

Transient entities (such as queues) and RAM node support will be removed in RabbitMQ 4.x.

### Overprovision Disk Space[​](#overprovision-disk-space "Direct link to Overprovision Disk Space"){.hash-link aria-label="Direct link to Overprovision Disk Space" translate="no"} {#overprovision-disk-space .anchor .anchorTargetStickyNavbar_Vzrq}

::::: {.theme-admonition .theme-admonition-important .admonition_xJq3 .alert .alert--info}
::: admonitionHeading_Gvgb
[ ![](data:image/svg+xml;base64,PHN2ZyB2aWV3Ym94PSIwIDAgMTQgMTYiPgo8cGF0aCBmaWxsLXJ1bGU9ImV2ZW5vZGQiIGQ9Ik03IDIuM2MzLjE0IDAgNS43IDIuNTYgNS43IDUuN3MtMi41NiA1LjctNS43IDUuN0E1LjcxIDUuNzEgMCAwIDEgMS4zIDhjMC0zLjE0IDIuNTYtNS43IDUuNy01Ljd6TTcgMUMzLjE0IDEgMCA0LjE0IDAgOHMzLjE0IDcgNyA3IDctMy4xNCA3LTctMy4xNC03LTctN3ptMSAzSDZ2NWgyVjR6bTAgNkg2djJoMnYtMnoiIC8+Cjwvc3ZnPg==) ]{.admonitionIcon_Rf37}important
:::

::: admonitionContent_BuS1
The rule of thumb is: when in doubt, overprovision the disks that RabbitMQ nodes will use. Quorum queues and streams can have substantial on-disk footprint.
:::
:::::

Quorum queues and streams can have substantial on-disk footprint. Depending on the workload and settings, they may or may not reclaim disk space of consumed and confirmed or expired messages quickly.

[Disk space to RAM ratio recommendations](#resource-limits-disk-space) are listed below. The rule of thumb is: when in doubt, overprovision the disks that RabbitMQ nodes will use.

### Network-attached Storage (NAS)[​](#storage-nas "Direct link to Network-attached Storage (NAS)"){.hash-link aria-label="Direct link to Network-attached Storage (NAS)" translate="no"} {#storage-nas .anchor .anchorTargetStickyNavbar_Vzrq}

Network-attached storage (NAS) can be used for RabbitMQ node data directories, provided that the NAS volume

- It offers low I/O latency
- It can guarantee no significant latency spikes (for example, due to sharing with other I/O-heavy services)

Quorum queues, streams, and other RabbitMQ features will benefit from fast local SSD and NVMe storage. When possible, prefer local storage to NAS.

### Storage Isolation[​](#storage-isolation "Direct link to Storage Isolation"){.hash-link aria-label="Direct link to Storage Isolation" translate="no"} {#storage-isolation .anchor .anchorTargetStickyNavbar_Vzrq}

RabbitMQ nodes must never share their data directories. Ideally, should not share their disk I/O with other services for most predictable latency and throughput.

### Choice of a Filesystem[​](#storage-filesystems "Direct link to Choice of a Filesystem"){.hash-link aria-label="Direct link to Choice of a Filesystem" translate="no"} {#storage-filesystems .anchor .anchorTargetStickyNavbar_Vzrq}

RabbitMQ nodes can use most widely used local filesystems: ext4, btfs, and so on.

Avoid using distributed filesystems for node data directories:

- RabbitMQ\'s storage subsystem assumes the standard local filesystem semantics for `fsync(2)` and other key operations. Distributed filesystems often [deviate from these standard guarantees](https://docs.ceph.com/en/latest/cephfs/posix/){target="_blank" rel="noopener noreferrer"}
- Distributed filesystems are usually designed for shared access to a subset of directories. Sharing a data directory between RabbitMQ nodes is **an absolute no-no** and is guaranteed to result in data corruption since nodes will not coordinate their writes

## Virtual Hosts, Users, Permissions[​](#users-and-permissions "Direct link to Virtual Hosts, Users, Permissions"){.hash-link aria-label="Direct link to Virtual Hosts, Users, Permissions" translate="no"} {#users-and-permissions .anchor .anchorTargetStickyNavbar_Vzrq}

It is often necessary to seed a cluster with virtual hosts, users, permissions, topologies, policies and so on. The recommended way of doing this at deployment time is [via definition import](/docs/definitions). Definitions can be imported on node boot or at any point after cluster deployment using `rabbitmqadmin` or the `POST /api/definitions` [HTTP API endpoint](/docs/management).

### Virtual Hosts[​](#virtual-hosts "Direct link to Virtual Hosts"){.hash-link aria-label="Direct link to Virtual Hosts" translate="no"} {#virtual-hosts .anchor .anchorTargetStickyNavbar_Vzrq}

In a single-tenant environment, for example, when your RabbitMQ cluster is dedicated to power a single system in production, using default virtual host (`/`) is perfectly fine.

In multi-tenant environments, use a separate vhost for each tenant/environment, e.g. `project1_development`, `project1_production`, `project2_development`, `project2_production`, and so on.

### Users[​](#users "Direct link to Users"){.hash-link aria-label="Direct link to Users" translate="no"} {#users .anchor .anchorTargetStickyNavbar_Vzrq}

For production environments, delete the default user (`guest`). Default user only can connect from localhost by default, because it has well-known credentials. Instead of enabling remote connections, consider creating a separate user with administrative permissions and a generated password.

It is recommended to use a separate user per application. For example, if you have a mobile app, a Web app, and a data aggregation system, you\'d have 3 separate users. This makes a number of things easier:

- Correlating client connections with applications
- Using [fine-grained permissions](/docs/access-control)
- Credentials roll-over (e.g. periodically or in case of a breach)

In case there are many instances of the same application, there\'s a trade-off between better security (having a set of credentials per instance) and convenience of provisioning (sharing a set of credentials between some or all instances).

For IoT applications that involve many clients performing the same or similar function and having fixed IP addresses, it may make sense to [authenticate using x509 certificates](/docs/ssl) or [source IP address ranges](https://github.com/gotthardp/rabbitmq-auth-backend-ip-range){target="_blank" rel="noopener noreferrer"}.

### Anonymous Login[​](#anonymous-login "Direct link to Anonymous Login"){.hash-link aria-label="Direct link to Anonymous Login" translate="no"} {#anonymous-login .anchor .anchorTargetStickyNavbar_Vzrq}

For production environments, it is almost always a good idea to disable anonymous logins.

You can disable the `ANONYMOUS` [SASL mechansim](/docs/access-control#mechanisms) in [rabbitmq.conf](/docs/configure#config-file) as follows:

:::: {.language-ini .codeBlockContainer_Ckt0 .theme-code-block style="--prism-color:#393A34;--prism-background-color:#f6f8fa"}
::: codeBlockContent_QJqH
``` {.prism-code .language-ini .codeBlock_bY9V .thin-scrollbar tabindex="0" style="color:#393A34;background-color:#f6f8fa"}



auth_mechanisms.1 = PLAIN




auth_mechanisms.2 = AMQPLAIN




# note: the ANONYMOUS mechanism is not listed










# Value none has a special meaning that no user is configured for anonymous logins.




anonymous_login_user = none



```
:::
::::

## Monitoring and Resource Limits[​](#monitoring-and-resource-usage "Direct link to Monitoring and Resource Limits"){.hash-link aria-label="Direct link to Monitoring and Resource Limits" translate="no"} {#monitoring-and-resource-usage .anchor .anchorTargetStickyNavbar_Vzrq}

RabbitMQ nodes are limited by various resources, both physical (e.g. the amount of RAM available) as well as software (e.g. max number of file handles a process can open). It is important to evaluate resource limit configurations before going into production and continuously monitor resource usage after that.

### Monitoring[​](#monitoring "Direct link to Monitoring"){.hash-link aria-label="Direct link to Monitoring" translate="no"} {#monitoring .anchor .anchorTargetStickyNavbar_Vzrq}

[Monitoring](/docs/monitoring) several aspects of the system, from infrastructure and kernel metrics to RabbitMQ to application-level metrics is essential. While monitoring requires an upfront investment in terms of time, it is very effective at catching issues and noticing potentially problematic trends early (or at all).

### Memory[​](#resource-limits-ram "Direct link to Memory"){.hash-link aria-label="Direct link to Memory" translate="no"} {#resource-limits-ram .anchor .anchorTargetStickyNavbar_Vzrq}

RabbitMQ uses [Resource-driven alarms](/docs/alarms) to throttle publishers when consumers do not keep up.

By default, RabbitMQ will not accept any new messages when it detects that it\'s using more than 60% of the available memory (as reported by the OS): `vm_memory_high_watermark.relative = 0.6`. This is a safe default and care should be taken when modifying this value, even when the host is a dedicated RabbitMQ node.

The OS and file system use system memory to speed up operations for all system processes. Failing to leave enough free system memory for this purpose will have an adverse effect on system performance due to OS swapping, and can even result in RabbitMQ process termination.

A few recommendations when adjusting the default `vm_memory_high_watermark`:

- Nodes hosting RabbitMQ should have at least **256 MiB** of memory available at all times. Deployments that use [quorum queues](/docs/quorum-queues) require more, see [how quorum queue use resources](/docs/quorum-queues#resource-use) for more information.
- The recommended `vm_memory_high_watermark.relative` range is `0.4 to 0.7`
- Values above `0.7` should be used with care and with solid [memory usage](/docs/memory-use) and infrastructure-level [monitoring](/docs/monitoring) in place. The OS and file system must be left with at least 30% of the memory, otherwise performance may degrade severely due to paging.

These are some very broad-stroked guidelines. As with every tuning scenario, monitoring, benchmarking and measuring are required to find the best setting for the environment and workload.

Learn more about [RabbitMQ and system memory](/docs/memory) in a separate guide.

### Disk Space[​](#resource-limits-disk-space "Direct link to Disk Space"){.hash-link aria-label="Direct link to Disk Space" translate="no"} {#resource-limits-disk-space .anchor .anchorTargetStickyNavbar_Vzrq}

The current 50MB `disk_free_limit` default works very well for development and [tutorials](/tutorials). Production deployments require a much greater safety margin. Insufficient disk space will lead to node failures and may result in data loss as all disk writes will fail.

Why is the default 50MB then? Development environments sometimes use really small partitions to host `/var/lib`, for example, which means nodes go into resource alarm state right after booting. The very low default ensures that RabbitMQ works out of the box for everyone. As for production deployments, we recommend the following:

The minimum recommended free disk space low watermark value is about the same as the high memory watermark. For example, on a node configured to have its memory watermark of 4GB, `disk_free_limit.absolute = 4G` would be a recommended minimum.

::::: {.theme-admonition .theme-admonition-warning .admonition_xJq3 .alert .alert--warning}
::: admonitionHeading_Gvgb
[ ![](data:image/svg+xml;base64,PHN2ZyB2aWV3Ym94PSIwIDAgMTYgMTYiPgo8cGF0aCBmaWxsLXJ1bGU9ImV2ZW5vZGQiIGQ9Ik04Ljg5MyAxLjVjLS4xODMtLjMxLS41Mi0uNS0uODg3LS41cy0uNzAzLjE5LS44ODYuNUwuMTM4IDEzLjQ5OWEuOTguOTggMCAwIDAgMCAxLjAwMWMuMTkzLjMxLjUzLjUwMS44ODYuNTAxaDEzLjk2NGMuMzY3IDAgLjcwNC0uMTkuODc3LS41YTEuMDMgMS4wMyAwIDAgMCAuMDEtMS4wMDJMOC44OTMgMS41em0uMTMzIDExLjQ5N0g2Ljk4N3YtMi4wMDNoMi4wMzl2Mi4wMDN6bTAtMy4wMDRINi45ODdWNS45ODdoMi4wMzl2NC4wMDZ6IiAvPgo8L3N2Zz4=) ]{.admonitionIcon_Rf37}warning
:::

::: admonitionContent_BuS1
Nodes running out of disk space should be considered a very serious operational problem, commonly leading to outages and possibly data loss for the affected node.

When in doubt, overprovision the disk space and/or use a high `disk_free_limit`.
:::
:::::

### Open File Handles Limit[​](#resource-limits-file-handle-limit "Direct link to Open File Handles Limit"){.hash-link aria-label="Direct link to Open File Handles Limit" translate="no"} {#resource-limits-file-handle-limit .anchor .anchorTargetStickyNavbar_Vzrq}

Operating systems limit maximum number of concurrently open file handles, which includes network sockets. Make sure that you have limits set high enough to allow for expected number of concurrent connections and queues.

Make sure production environments allow for at least 50K open file descriptors for effective RabbitMQ user, including in development environments.

As a guideline, multiply the 95th percentile number of concurrent connections by 2 and add the total number of queues to calculate the recommended open file handle limit. Values as high as 500K are not inadequate and will not consume a lot of hardware resources, therefore, they are recommended for production setups.

See [Networking guide](/docs/networking) for more information.

### Log Collection[​](#logging "Direct link to Log Collection"){.hash-link aria-label="Direct link to Log Collection" translate="no"} {#logging .anchor .anchorTargetStickyNavbar_Vzrq}

It is highly recommended that logs of all RabbitMQ nodes and applications (when possible) are collected and aggregated. Logs can be crucially important in investigating unusual system behaviour.

## Configurable Limits[​](#limits "Direct link to Configurable Limits"){.hash-link aria-label="Direct link to Configurable Limits" translate="no"} {#limits .anchor .anchorTargetStickyNavbar_Vzrq}

Production clusters should adopt at least some configurable limits that act as guard rails that prevent poorly behaved applications from leaking resources and affecting cluster stability.

RabbitMQ provides a comprehensive set of [configurable limits](/docs/limits) at multiple levels: from cluster-wide to [per virtual host](/docs/vhosts#limits) and [per user](/docs/user-limits), down to individual connections, channels, queues, and streams.

Adopting these limits is particularly important in multi-tenant environments or when RabbitMQ is offered as a service. Even in single-tenant deployments, limits help prevent resource leaks and provide early detection of application issues.

Consult the [Configurable Limits guide](/docs/limits) for detailed information on available limits and how to configure them.

## Security Considerations[​](#security "Direct link to Security Considerations"){.hash-link aria-label="Direct link to Security Considerations" translate="no"} {#security .anchor .anchorTargetStickyNavbar_Vzrq}

### Users and Permissions[​](#security-users-and-permissions "Direct link to Users and Permissions"){.hash-link aria-label="Direct link to Users and Permissions" translate="no"} {#security-users-and-permissions .anchor .anchorTargetStickyNavbar_Vzrq}

See the section on vhosts, users, and credentials above.

### Inter-node and CLI Tool Authentication[​](#inter-node-authentication "Direct link to Inter-node and CLI Tool Authentication"){.hash-link aria-label="Direct link to Inter-node and CLI Tool Authentication" translate="no"} {#inter-node-authentication .anchor .anchorTargetStickyNavbar_Vzrq}

RabbitMQ nodes authenticate to each other using a [shared secret](/docs/clustering#erlang-cookie) stored in a file. On Linux and other UNIX-like systems, it is necessary to restrict cookie file access only to the OS users that will run RabbitMQ and [CLI tools](/docs/cli).

It is important that the value is generated in a reasonably secure way (e.g. not computed from an easy to guess value). This is usually done using deployment automation tools at the time of initial deployment. Those tools can use default or placeholder values: don\'t rely on them. Allowing the runtime to generate a cookie file on one node and copying it to all other nodes is also a poor practice: it makes the generated value more predictable since the generation algorithm is known.

CLI tools use the same authentication mechanism. It is recommended that [inter-node and CLI communication port](/docs/clustering#ports) access is limited to the hosts that run RabbitMQ nodes or CLI tools.

[Securing inter-node communication with TLS](/docs/clustering-ssl) is recommended. It implies that CLI tools are also configured to use TLS.

### Firewall Configuration[​](#security-firewall-rules "Direct link to Firewall Configuration"){.hash-link aria-label="Direct link to Firewall Configuration" translate="no"} {#security-firewall-rules .anchor .anchorTargetStickyNavbar_Vzrq}

[Ports used by RabbitMQ](/docs/networking#ports) can be broadly put into one of two categories:

- Ports used by client libraries (AMQP 0-9-1, AMQP 1.0, MQTT, STOMP, HTTP API)
- All other ports (inter node communication, CLI tools and so on)

Access to ports from the latter category generally should be restricted to hosts running RabbitMQ nodes or CLI tools. Ports in the former category should be accessible to hosts that run applications, which in some cases can mean public networks, for example, behind a load balancer.

### TLS[​](#security-tls "Direct link to TLS"){.hash-link aria-label="Direct link to TLS" translate="no"} {#security-tls .anchor .anchorTargetStickyNavbar_Vzrq}

We recommend using [TLS connections](/docs/ssl) when possible, at least to encrypt traffic. Peer verification (authentication) is also recommended. Development and QA environments can use [self-signed TLS certificates](https://github.com/rabbitmq/tls-gen/){target="_blank" rel="noopener noreferrer"}. Self-signed certificates can be appropriate in production environments when RabbitMQ and all applications run on a trusted network or isolated using technologies such as VMware NSX.

While RabbitMQ tries to offer a reasonably secure TLS configuration by default, it is highly recommended evaluating TLS configuration (versions cipher suites and so on) using tools such as [testssl.sh](https://testssl.sh/){target="_blank" rel="noopener noreferrer"}. Please refer to the [TLS guide](/docs/ssl) to learn more.

Note that TLS can have significant impact on overall system throughput, including CPU usage of both RabbitMQ and applications that use it.

### Encryption at Rest[​](#security-encryption-at-rest "Direct link to Encryption at Rest"){.hash-link aria-label="Direct link to Encryption at Rest" translate="no"} {#security-encryption-at-rest .anchor .anchorTargetStickyNavbar_Vzrq}

RabbitMQ itself does not encrypt data it writes to disk, such as message payloads or [metadata](/docs/metadata-store). This is by design --- encrypting messages on the server side would have a significant performance impact, since the broker would need to encrypt and decrypt the payload of every message passing through it. We recommend the following alternatives, which address data-at-rest encryption without that cost.

- **Encrypt the underlying storage.** Full-disk or volume-level encryption (for example, [LUKS](https://gitlab.com/cryptsetup/cryptsetup){target="_blank" rel="noopener noreferrer"}, or encrypted cloud block storage) protects *all* data at rest with hardware-accelerated performance.
- **Use end-to-end encryption.** Client applications can encrypt payloads before publishing and decrypt them after consuming. This ensures that message contents stay confidential even from anyone with access to the broker itself, including its administrators. As a result, the broker only ever sees and stores opaque encrypted bytes.

Both of these options can be used independently or can complement each other to achieve the best security outcome for your use case.

## Networking Configuration[​](#networking "Direct link to Networking Configuration"){.hash-link aria-label="Direct link to Networking Configuration" translate="no"} {#networking .anchor .anchorTargetStickyNavbar_Vzrq}

Production environments may require network configuration tuning, for example, to sustain a high number of concurrent clients. Please refer to the [Networking Guide](/docs/networking) for details.

### Minimum Available Network Throughput Estimate[​](#networking-throughput "Direct link to Minimum Available Network Throughput Estimate"){.hash-link aria-label="Direct link to Minimum Available Network Throughput Estimate" translate="no"} {#networking-throughput .anchor .anchorTargetStickyNavbar_Vzrq}

With higher message rates and large message payloads, traffic bandwidth available to cluster nodes becomes an important factor.

The following (intentionally oversimplified) formula can be used to compute the **minimum amount of bandwidth** that must be available to cluster nodes, in bits per second:

:::: {.language-ini .codeBlockContainer_Ckt0 .theme-code-block style="--prism-color:#393A34;--prism-background-color:#f6f8fa"}
::: codeBlockContent_QJqH
``` {.prism-code .language-ini .codeBlock_bY9V .thin-scrollbar tabindex="0" style="color:#393A34;background-color:#f6f8fa"}



MR * MS * 110% * 8



```
:::
::::

where

- `MR`: 95th percentile message rate per second
- `MS`: 95th percentile message size, in bytes
- 110%: accounts for message properties, protocol metadata, and other data transferred
- 8: bits per byte

For example, with a message rate (`MR`) of 20K per second and 6 KB message payloads (`MS`):

:::: {.language-ini .codeBlockContainer_Ckt0 .theme-code-block style="--prism-color:#393A34;--prism-background-color:#f6f8fa"}
::: codeBlockContent_QJqH
``` {.prism-code .language-ini .codeBlock_bY9V .thin-scrollbar tabindex="0" style="color:#393A34;background-color:#f6f8fa"}



20K * 6 KB * 110% * 8 bit/B = 20000 * 6000 * 1.1 * 8 = 1.056 (gigabit/second)



```
:::
::::

With the above inputs, cluster nodes must have network links with throughput of at least 1.056 gigabit per second.

This formula **is a rule of thumb** and does not consider protocol- or workload-specific nuances.

## Clustering Considerations[​](#clustering "Direct link to Clustering Considerations"){.hash-link aria-label="Direct link to Clustering Considerations" translate="no"} {#clustering .anchor .anchorTargetStickyNavbar_Vzrq}

### Cluster Size[​](#clustering-cluster-size "Direct link to Cluster Size"){.hash-link aria-label="Direct link to Cluster Size" translate="no"} {#clustering-cluster-size .anchor .anchorTargetStickyNavbar_Vzrq}

The number of queues, queue replication factor, number of connections, maximum message backlog and sometimes message throughput are factors that determine how large should a cluster be.

Single node clusters can be sufficient when simplicity is preferred over everything else: development, integration testing and certain QA environments.

Three node clusters are the next step up. They can tolerate a single node failure (or unavailability) and still [maintain quorum](/docs/quorum-queues). Simplicity is traded off for availability, resiliency and, in certain cases, throughput.

It is recommended to use clusters with an odd number of nodes (3, 5, 7, etc) so that when one node becomes unavailable, the service remains available and a clear majority of nodes can be identified.

For most environments, configuring queue replication to more than half --- but not all --- cluster nodes is sufficient.

#### Uneven Numbers of Nodes and Cluster Majority[​](#uneven-numbers-of-nodes-and-cluster-majority "Direct link to Uneven Numbers of Nodes and Cluster Majority"){.hash-link aria-label="Direct link to Uneven Numbers of Nodes and Cluster Majority" translate="no"} {#uneven-numbers-of-nodes-and-cluster-majority .anchor .anchorTargetStickyNavbar_Vzrq}

It is important to pick a [partition handling strategy](/docs/partitions) before going into production. When in doubt, use the `pause_minority` strategy with an odd number of nodes (3, 5, 7, and so on).

Uneven number of nodes make network partition recovery more predictable, with the common option of the minority automatically refusing to service commands.

#### Data Locality Considerations[​](#data-locality-considerations "Direct link to Data Locality Considerations"){.hash-link aria-label="Direct link to Data Locality Considerations" translate="no"} {#data-locality-considerations .anchor .anchorTargetStickyNavbar_Vzrq}

With multi-node clusters, data locality becomes an important consideration. Since [clients can connect to any node](/docs/clustering), RabbitMQ nodes may need to perform inter-cluster routing of messages and internal operations. Data locality will be best when producers (publishers) connect to RabbitMQ nodes where queue leaders are running. Such topology is difficult to achieve in practice.

With classic queues, all deliveries are performed from the leader replica. Quorum queues can deliver messages from queue replicas as well, so as long as consumers connect to a node where a quorum queue replica is hosted, messages delivered to those consumers will be performed from the local node.

#### Growing Node Count to Sustain More Concurrent Clients[​](#growing-node-count-to-sustain-more-concurrent-clients "Direct link to Growing Node Count to Sustain More Concurrent Clients"){.hash-link aria-label="Direct link to Growing Node Count to Sustain More Concurrent Clients" translate="no"} {#growing-node-count-to-sustain-more-concurrent-clients .anchor .anchorTargetStickyNavbar_Vzrq}

Environments that have to sustain a [large number of concurrent client connections](/docs/networking#tuning-for-large-number-of-connections) will benefit from more cluster nodes as long as the connections are distributed across them. This can be achieved using a load balancer or making clients randomly pick a node to connect to from the provided node list.

#### Increasing Node Counts vs. Deploying Separate Clusters for Separate Purposes[​](#increasing-node-counts-vs-deploying-separate-clusters-for-separate-purposes "Direct link to Increasing Node Counts vs. Deploying Separate Clusters for Separate Purposes"){.hash-link aria-label="Direct link to Increasing Node Counts vs. Deploying Separate Clusters for Separate Purposes" translate="no"} {#increasing-node-counts-vs-deploying-separate-clusters-for-separate-purposes .anchor .anchorTargetStickyNavbar_Vzrq}

All metadata ([definitions](/docs/definitions): virtual hosts, users, queues, exchanges, bindings, etc.) is replicated across all nodes in the cluster, and most metadata changes are synchronous in nature.

The cost of propagating such changes goes up with the number of cluster nodes, both during operations and node restarts. Users who find themselves in need of clusters with node counts in double digits should **consider using independent clusters for separate parts of the system** where possible.

### Node Time Synchronization[​](#clustering-ntp "Direct link to Node Time Synchronization"){.hash-link aria-label="Direct link to Node Time Synchronization" translate="no"} {#clustering-ntp .anchor .anchorTargetStickyNavbar_Vzrq}

A RabbitMQ cluster will typically function well without clocks of participating servers being synchronized. However some plugins, such as the management one, make use of local timestamps for metrics processing and may display incorrect statistics when the current time of nodes drift apart. It is therefore recommended that servers use NTP or similar to ensure clocks remain in sync.

## Application Considerations[​](#apps "Direct link to Application Considerations"){.hash-link aria-label="Direct link to Application Considerations" translate="no"} {#apps .anchor .anchorTargetStickyNavbar_Vzrq}

The way applications are designed and use RabbitMQ client libraries is a major contributor to the overall system resilience. Applications that use resources inefficiently or leak them will eventually affect the rest of the system. For example, an app that continuously opens connections but never closes them will exhaust cluster nodes out of file descriptors so no new connections will be accepted. This and similar problems can manifest themselves in more complex scenarios, e.g those collectively known as the thundering herd problem.

This section covers a number of most common problems. Most of these problems are generally not protocol-specific or new. They can be hard to detect, however. Adequate [monitoring](/docs/monitoring) of the system is critically important as it is the only way to spot problematic trends (e.g. channel leaks, growing file descriptor usage from poor connection management) early.

### Connection Management[​](#apps-connection-management "Direct link to Connection Management"){.hash-link aria-label="Direct link to Connection Management" translate="no"} {#apps-connection-management .anchor .anchorTargetStickyNavbar_Vzrq}

Messaging protocols generally assume long-lived connections. Some applications connect to RabbitMQ on start and only close the connection(s) when they have to terminate. Others open and close connections more dynamically. For the latter group it is important to close them when they are no longer used.

Connections can be closed for reasons outside of application developer\'s control. Messaging protocols supported by RabbitMQ use a feature called [heartbeats](/docs/heartbeats) (the name may vary but the concept does not) to detect such connections quicker than the TCP stack. Developers should be careful about using heartbeat timeout that are too low (less than 5 seconds) as that may produce false positives when network congestion or system load goes up.

Very short lived connections should be avoided when possible. The following section will cover this in more detail.

It is recommended that, when possible, publishers and consumers use separate connections so that consumers are isolated from potential [flow control](/docs/connections#flow-control) that may be applied to publishing connections, affecting [manual consumer acknowledgements](/docs/confirms).

### Connection Churn[​](#apps-connection-churn "Direct link to Connection Churn"){.hash-link aria-label="Direct link to Connection Churn" translate="no"} {#apps-connection-churn .anchor .anchorTargetStickyNavbar_Vzrq}

As mentioned above, messaging protocols generally assume long-lived connections. Some applications may open a new connection to perform a single operation (e.g. publish a message) and then close it. This is highly inefficient as opening a connection is an expensive operation (compared to reusing an existing one). Such workload also leads to [connection churn](/docs/networking#dealing-with-high-connection-churn). Nodes experiencing high connection churn must be tuned to release TCP connections much quicker than kernel defaults, otherwise they will eventually run out of file handles or memory and will stop accepting new connections.

If a small number of long lived connections is not an option, connection pooling can help reduce peak resource usage.

### Recovery from Connection Failures[​](#apps-automatic-recovery "Direct link to Recovery from Connection Failures"){.hash-link aria-label="Direct link to Recovery from Connection Failures" translate="no"} {#apps-automatic-recovery .anchor .anchorTargetStickyNavbar_Vzrq}

Some client libraries, for example, [Java](/client-libraries/java-api-guide), [.NET](/client-libraries/dotnet-api-guide) and [Ruby](http://rubybunny.info){target="_blank" rel="noopener noreferrer"}, support automatic connection recovery after network failures. If the client used provides this feature, it is recommended to use it instead of developing your own recovery mechanism.

Other clients (Go, Pika) do not support automatic connection recovery as a feature but do provide examples that demonstrate how to recover from connection failures.

### Excessive Channel Usage[​](#apps-excessive-channel-usage "Direct link to Excessive Channel Usage"){.hash-link aria-label="Direct link to Excessive Channel Usage" translate="no"} {#apps-excessive-channel-usage .anchor .anchorTargetStickyNavbar_Vzrq}

Channels also consume resources in both client and server. Applications should minimize the number of channels they use when possible and close channels that are no longer necessary. Channels, like connections, are meant to be long lived.

Note that closing a connection automatically closes all channels on it.

### Polling Consumers[​](#apps-polling-consumers "Direct link to Polling Consumers"){.hash-link aria-label="Direct link to Polling Consumers" translate="no"} {#apps-polling-consumers .anchor .anchorTargetStickyNavbar_Vzrq}

[Polling consumers](/docs/consumers#polling) (consumption with `basic.get`) is a feature that application developers should avoid in most cases as polling is inherently inefficient.
::::::::::::::::::::::::
::::::::::::::::::::::::::
:::::::::::::::::::::::::::

:::: {.col .col--3}
::: {.tableOfContents_bqdL .thin-scrollbar .theme-doc-toc-desktop}
- [Overview](#overview){.table-of-contents__link .toc-highlight}
- [Table of Contents](#toc){.table-of-contents__link .toc-highlight}
- [Minimum Hardware Requirements](#minimum-hardware){.table-of-contents__link .toc-highlight}
- [Storage Considerations](#storage){.table-of-contents__link .toc-highlight}
  - [Use Durable Storage](#storage-durability){.table-of-contents__link .toc-highlight}
  - [Overprovision Disk Space](#overprovision-disk-space){.table-of-contents__link .toc-highlight}
  - [Network-attached Storage (NAS)](#storage-nas){.table-of-contents__link .toc-highlight}
  - [Storage Isolation](#storage-isolation){.table-of-contents__link .toc-highlight}
  - [Choice of a Filesystem](#storage-filesystems){.table-of-contents__link .toc-highlight}
- [Virtual Hosts, Users, Permissions](#users-and-permissions){.table-of-contents__link .toc-highlight}
  - [Virtual Hosts](#virtual-hosts){.table-of-contents__link .toc-highlight}
  - [Users](#users){.table-of-contents__link .toc-highlight}
  - [Anonymous Login](#anonymous-login){.table-of-contents__link .toc-highlight}
- [Monitoring and Resource Limits](#monitoring-and-resource-usage){.table-of-contents__link .toc-highlight}
  - [Monitoring](#monitoring){.table-of-contents__link .toc-highlight}
  - [Memory](#resource-limits-ram){.table-of-contents__link .toc-highlight}
  - [Disk Space](#resource-limits-disk-space){.table-of-contents__link .toc-highlight}
  - [Open File Handles Limit](#resource-limits-file-handle-limit){.table-of-contents__link .toc-highlight}
  - [Log Collection](#logging){.table-of-contents__link .toc-highlight}
- [Configurable Limits](#limits){.table-of-contents__link .toc-highlight}
- [Security Considerations](#security){.table-of-contents__link .toc-highlight}
  - [Users and Permissions](#security-users-and-permissions){.table-of-contents__link .toc-highlight}
  - [Inter-node and CLI Tool Authentication](#inter-node-authentication){.table-of-contents__link .toc-highlight}
  - [Firewall Configuration](#security-firewall-rules){.table-of-contents__link .toc-highlight}
  - [TLS](#security-tls){.table-of-contents__link .toc-highlight}
  - [Encryption at Rest](#security-encryption-at-rest){.table-of-contents__link .toc-highlight}
- [Networking Configuration](#networking){.table-of-contents__link .toc-highlight}
  - [Minimum Available Network Throughput Estimate](#networking-throughput){.table-of-contents__link .toc-highlight}
- [Clustering Considerations](#clustering){.table-of-contents__link .toc-highlight}
  - [Cluster Size](#clustering-cluster-size){.table-of-contents__link .toc-highlight}
  - [Node Time Synchronization](#clustering-ntp){.table-of-contents__link .toc-highlight}
- [Application Considerations](#apps){.table-of-contents__link .toc-highlight}
  - [Connection Management](#apps-connection-management){.table-of-contents__link .toc-highlight}
  - [Connection Churn](#apps-connection-churn){.table-of-contents__link .toc-highlight}
  - [Recovery from Connection Failures](#apps-automatic-recovery){.table-of-contents__link .toc-highlight}
  - [Excessive Channel Usage](#apps-excessive-channel-usage){.table-of-contents__link .toc-highlight}
  - [Polling Consumers](#apps-polling-consumers){.table-of-contents__link .toc-highlight}
:::
::::
::::::::::::::::::::::::::::::
:::::::::::::::::::::::::::::::
::::::::::::::::::::::::::::::::
