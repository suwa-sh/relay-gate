---
source_url: "https://www.postgresql.org/docs/current/high-availability.html"
fetched_at: "2026-08-30T10:05:32Z"
vendor: "onprem"
layer: "product"
---

::::::: container-fluid
:::: {.row .justify-content-md-center}
::: col
:::
::::

:::: {.row .justify-content-center .pg-shout-box}
::: {.col .text-white .text-center}
August 13, 2026: [PostgreSQL 18.6, 17.11, 16.15, 15.19, 14.24 and 19 Beta 3 Released!](/about/news/postgresql-186-1711-1615-1519-1424-and-19-beta-3-released-3365/)
:::
::::
:::::::

::::::::::::::::::::::::::: {.container-fluid .margin}
:::::::::::::::::::::::::: row
::::::::::::::::::::::::: {#pgContentWrap .col-11}
::::::::::::::: row
:::::::::::: {.col-md-6 .mb-2}
::::: row
:::: col
::: {}
[Documentation](/docs/ "Documentation") → [PostgreSQL 18](/docs/18/index.html)
:::
::::
:::::

:::: row
::: col
Supported Versions: [Current](/docs/current/high-availability.html "PostgreSQL 18 - Chapter 26. High Availability, Load Balancing, and Replication"){.docs-version-selected} ([18](/docs/18/high-availability.html "PostgreSQL 18 - Chapter 26. High Availability, Load Balancing, and Replication"){.docs-version-selected}) / [17](/docs/17/high-availability.html "PostgreSQL 17 - Chapter 26. High Availability, Load Balancing, and Replication") / [16](/docs/16/high-availability.html "PostgreSQL 16 - Chapter 26. High Availability, Load Balancing, and Replication") / [15](/docs/15/high-availability.html "PostgreSQL 15 - Chapter 26. High Availability, Load Balancing, and Replication") / [14](/docs/14/high-availability.html "PostgreSQL 14 - Chapter 26. High Availability, Load Balancing, and Replication")
:::
::::

:::: row
::: col
Development Versions: [19](/docs/19/high-availability.html "PostgreSQL 19 - Chapter 26. High Availability, Load Balancing, and Replication"){rel="nofollow"} / [devel](/docs/devel/high-availability.html "PostgreSQL devel - Chapter 26. High Availability, Load Balancing, and Replication"){rel="nofollow"}
:::
::::

:::: row
::: col-12
Unsupported versions: [13](/docs/13/high-availability.html "PostgreSQL 13 - Chapter 26. High Availability, Load Balancing, and Replication"){rel="nofollow"} / [12](/docs/12/high-availability.html "PostgreSQL 12 - Chapter 26. High Availability, Load Balancing, and Replication"){rel="nofollow"} / [11](/docs/11/high-availability.html "PostgreSQL 11 - Chapter 26. High Availability, Load Balancing, and Replication"){rel="nofollow"} / [10](/docs/10/high-availability.html "PostgreSQL 10 - Chapter 26. High Availability, Load Balancing, and Replication"){rel="nofollow"} / [9.6](/docs/9.6/high-availability.html "PostgreSQL 9.6 - Chapter 26. High Availability, Load Balancing, and Replication"){rel="nofollow"} / [9.5](/docs/9.5/high-availability.html "PostgreSQL 9.5 - Chapter 26. High Availability, Load Balancing, and Replication"){rel="nofollow"} / [9.4](/docs/9.4/high-availability.html "PostgreSQL 9.4 - Chapter 26. High Availability, Load Balancing, and Replication"){rel="nofollow"} / [9.3](/docs/9.3/high-availability.html "PostgreSQL 9.3 - Chapter 26. High Availability, Load Balancing, and Replication"){rel="nofollow"} / [9.2](/docs/9.2/high-availability.html "PostgreSQL 9.2 - Chapter 26. High Availability, Load Balancing, and Replication"){rel="nofollow"} / [9.1](/docs/9.1/high-availability.html "PostgreSQL 9.1 - Chapter 26. High Availability, Load Balancing, and Replication"){rel="nofollow"} / [9.0](/docs/9.0/high-availability.html "PostgreSQL 9.0 - Chapter 26. High Availability, Load Balancing, and Replication"){rel="nofollow"} / [8.4](/docs/8.4/high-availability.html "PostgreSQL 8.4 - Chapter 26. High Availability, Load Balancing, and Replication"){rel="nofollow"} / [8.3](/docs/8.3/high-availability.html "PostgreSQL 8.3 - Chapter 26. High Availability, Load Balancing, and Replication"){rel="nofollow"} / [8.2](/docs/8.2/high-availability.html "PostgreSQL 8.2 - Chapter 26. High Availability, Load Balancing, and Replication"){rel="nofollow"}
:::
::::
::::::::::::

:::: {.col-md-6 .col-lg-5 .offset-lg-1}
::: input-group
:::
::::
:::::::::::::::

:::::::::: {#docContent}
::: navheader
+-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------+
| Chapter 26. High Availability, Load Balancing, and Replication                                                                                                                                                                                                                                                                                                                                      |
+:=================================================================================================================+:==================================================================+:===============================:+==================================================================:+=======================================================================================================:+
| [Prev](continuous-archiving.html "25.3. Continuous Archiving and Point-in-Time Recovery (PITR)"){accesskey="p"}  | [Up](admin.html "Part III. Server Administration"){accesskey="u"} | Part III. Server Administration | [Home](index.html "PostgreSQL 18.6 Documentation"){accesskey="h"} |  [Next](different-replication-solutions.html "26.1. Comparison of Different Solutions"){accesskey="n"} |
+------------------------------------------------------------------------------------------------------------------+-------------------------------------------------------------------+---------------------------------+-------------------------------------------------------------------+--------------------------------------------------------------------------------------------------------+

------------------------------------------------------------------------
:::

::::::: {#HIGH-AVAILABILITY .chapter}
::::: titlepage
:::: {}
::: {}
## Chapter 26. High Availability, Load Balancing, and Replication {#chapter-26.-high-availability-load-balancing-and-replication .title}
:::
::::
:::::

::: toc
**Table of Contents**

[ [26.1. Comparison of Different Solutions](different-replication-solutions.html) ]{.sect1}

[ [26.2. Log-Shipping Standby Servers](warm-standby.html) ]{.sect1}

[ [26.2.1. Planning](warm-standby.html#STANDBY-PLANNING) ]{.sect2}

[ [26.2.2. Standby Server Operation](warm-standby.html#STANDBY-SERVER-OPERATION) ]{.sect2}

[ [26.2.3. Preparing the Primary for Standby Servers](warm-standby.html#PREPARING-PRIMARY-FOR-STANDBY) ]{.sect2}

[ [26.2.4. Setting Up a Standby Server](warm-standby.html#STANDBY-SERVER-SETUP) ]{.sect2}

[ [26.2.5. Streaming Replication](warm-standby.html#STREAMING-REPLICATION) ]{.sect2}

[ [26.2.6. Replication Slots](warm-standby.html#STREAMING-REPLICATION-SLOTS) ]{.sect2}

[ [26.2.7. Cascading Replication](warm-standby.html#CASCADING-REPLICATION) ]{.sect2}

[ [26.2.8. Synchronous Replication](warm-standby.html#SYNCHRONOUS-REPLICATION) ]{.sect2}

[ [26.2.9. Continuous Archiving in Standby](warm-standby.html#CONTINUOUS-ARCHIVING-IN-STANDBY) ]{.sect2}

[ [26.3. Failover](warm-standby-failover.html) ]{.sect1}

[ [26.4. Hot Standby](hot-standby.html) ]{.sect1}

[ [26.4.1. User\'s Overview](hot-standby.html#HOT-STANDBY-USERS) ]{.sect2}

[ [26.4.2. Handling Query Conflicts](hot-standby.html#HOT-STANDBY-CONFLICT) ]{.sect2}

[ [26.4.3. Administrator\'s Overview](hot-standby.html#HOT-STANDBY-ADMIN) ]{.sect2}

[ [26.4.4. Hot Standby Parameter Reference](hot-standby.html#HOT-STANDBY-PARAMETERS) ]{.sect2}

[ [26.4.5. Caveats](hot-standby.html#HOT-STANDBY-CAVEATS) ]{.sect2}
:::

[]{#id-1.6.13.2 .indexterm} []{#id-1.6.13.3 .indexterm} []{#id-1.6.13.4 .indexterm} []{#id-1.6.13.5 .indexterm} []{#id-1.6.13.6 .indexterm} []{#id-1.6.13.7 .indexterm}

Database servers can work together to allow a second server to take over quickly if the primary server fails (high availability), or to allow several computers to serve the same data (load balancing). Ideally, database servers could work together seamlessly. Web servers serving static web pages can be combined quite easily by merely load-balancing web requests to multiple machines. In fact, read-only database servers can be combined relatively easily too. Unfortunately, most database servers have a read/write mix of requests, and read/write servers are much harder to combine. This is because though read-only data needs to be placed on each server only once, a write to any server has to be propagated to all servers so that future read requests to those servers return consistent results.

This synchronization problem is the fundamental difficulty for servers working together. Because there is no single solution that eliminates the impact of the sync problem for all use cases, there are multiple solutions. Each solution addresses this problem in a different way, and minimizes its impact for a specific workload.

Some solutions deal with synchronization by allowing only one server to modify the data. Servers that can modify data are called read/write, *master* or *primary* servers. Servers that track changes in the primary are called *standby* or *secondary* servers. A standby server that cannot be connected to until it is promoted to a primary server is called a *warm standby* server, and one that can accept connections and serves read-only queries is called a *hot standby* server.

Some solutions are synchronous, meaning that a data-modifying transaction is not considered committed until all servers have committed the transaction. This guarantees that a failover will not lose any data and that all load-balanced servers will return consistent results no matter which server is queried. In contrast, asynchronous solutions allow some delay between the time of a commit and its propagation to the other servers, opening the possibility that some transactions might be lost in the switch to a backup server, and that load balanced servers might return slightly stale results. Asynchronous communication is used when synchronous would be too slow.

Solutions can also be categorized by their granularity. Some solutions can deal only with an entire database server, while others allow control at the per-table or per-database level.

Performance must be considered in any choice. There is usually a trade-off between functionality and performance. For example, a fully synchronous solution over a slow network might cut performance by more than half, while an asynchronous one might have a minimal performance impact.

The remainder of this section outlines various failover, replication, and load balancing solutions.
:::::::

::: navfooter

------------------------------------------------------------------------

  ------------------------------------------------------------------------------------------------------------------ ------------------------------------------------------------------- --------------------------------------------------------------------------------------------------------
  [Prev](continuous-archiving.html "25.3. Continuous Archiving and Point-in-Time Recovery (PITR)"){accesskey="p"}     [Up](admin.html "Part III. Server Administration"){accesskey="u"}     [Next](different-replication-solutions.html "26.1. Comparison of Different Solutions"){accesskey="n"}
  25.3. Continuous Archiving and Point-in-Time Recovery (PITR)                                                        [Home](index.html "PostgreSQL 18.6 Documentation"){accesskey="h"}                                                                   26.1. Comparison of Different Solutions
  ------------------------------------------------------------------------------------------------------------------ ------------------------------------------------------------------- --------------------------------------------------------------------------------------------------------
:::
::::::::::

::: {#docComments}
## Submit correction

If you see anything in the documentation that is not correct, does not match your experience with the particular feature or requires further clarification, please use [this form](/account/comments/new/18/high-availability.html/){rel="nofollow"} to report a documentation issue.
:::
:::::::::::::::::::::::::
::::::::::::::::::::::::::
:::::::::::::::::::::::::::
