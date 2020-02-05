HWPE-Mem
--------

.. HWPEs are connected to external L1/L2 shared-memory by means of a simple
.. memory protocol, using a request/grant handshake. The protocol used is
.. called HWPE Memory (*HWPE-Mem*) protocol, and it is essnetially similar
.. to the protocol used by cores and DMAs operating on memories.
.. This document focuses on the specific signal names used within HWPEs
.. and in the reference implementation of HWPE-Stream IPs.
.. It supports neither multiple outstanding transactions nor bursts, as
.. HWPEs using this protocol are assumed to be closely coupled to memories.
.. It uses a two signal *handshake* and carries two phases, a *request* and
.. a *response*.

.. The HWPE-Mem protocol is used to connect a *master* to a *slave*.
.. :numref:`hwpe_tcdm_master_slave` and :numref:`hwpe_tcdm_signals` report
.. the signals used by the HWPE-Mem protocol.

.. .. _hwpe_tcdm_master_slave:
.. .. figure:: img/hwpe_tcdm_master_slave.*
..   :figwidth: 60%
..   :width: 60%
..   :align: center

..   Data flow of the HWPE-Mem protocol. Red signals carry the
..   *handshake*; blue signals the *request* phase; green signals the
..   *response* phase.

.. _hwpe_tcdm_signals:
.. table:: HWPE-Mem signals.

  +------------+----------+----------------------------------------+---------------------+
  | **Signal** | **Size** | **Description**                        | **Direction**       |
  +------------+----------+----------------------------------------+---------------------+
  | *req*      | 1 bit    | Handshake request signal (1=asserted). | *master* to *slave* |
  +------------+----------+----------------------------------------+---------------------+
  | *gnt*      | 1 bit    | Handshake grant signal (1=asserted).   | *slave* to *master* |
  +------------+----------+----------------------------------------+---------------------+
  | *add*      | `AW`     | Word-aligned memory address.           | *master* to *slave* |
  +------------+----------+----------------------------------------+---------------------+
  | *wen*      | 1 bit    | Write enable signal (1=read, 0=write). | *master* to *slave* |
  +------------+----------+----------------------------------------+---------------------+
  | *be*       | `DW/BW`  | Byte enable signal (1=valid byte).     | *master* to *slave* |
  +------------+----------+----------------------------------------+---------------------+
  | *data*     | `DW`     | Data word to be stored.                | *master* to *slave* |
  +------------+----------+----------------------------------------+---------------------+
  | *pl*       | `DW/WW`  | Packet length in number of words.      | *master* to *slave* |
  +------------+----------+----------------------------------------+---------------------+
  | *ps*       | `SW`     | Packet stride in number of words.      | *master* to *slave* |
  +------------+----------+----------------------------------------+---------------------+
  | *r_data*   | 32 bit   | Loaded data word.                      | *slave* to *master* |
  +------------+----------+----------------------------------------+---------------------+
  | *r_valid*  | 1 bit    | Valid loaded data word (1=asserted).   | *slave* to *master* |
  +------------+----------+----------------------------------------+---------------------+

The handshake signals *req* and *gnt* are used to validate transactions
between masters and slaves. Transactions are subject to the following
rules:

1. **A valid handshake occurs in the cycle when both** *req* **and** *gnt*
   **are asserted**. This is true for both write and read transactions.

2. *r_valid* **must be asserted the cycle after a valid read handshake;**
   *r_data* **must be valid on this cycle**. This is due to
   the tightly-coupled nature of memories; if the memory cannot
   respond in one cycle, it must delay granting the transaction.

3. **The assertion of** *req* **(transition 0 to 1) cannot depend**
   **combinationally on the state of** *gnt*. On the other hand,
   the assertion of *gnt* (transition 0 to 1) can depend combinationally
   on the state of *req* (and typically it does). This rule avoids
   deadlocks in ping-pong logic.

The semantics of the *r_valid* signal are not well defined with respect
to the usual TCDM protocol. In PULP clusters, *r_valid* will be asserted
also after write transactions, not only in reads. However, the HWPE-Mem
protocol and the IPs in this repository should not make assumptions
on the *r_valid* in write transactions.

HWPE-MemDecoupled
-----------------

The HWPE-Mem protocol can be used to directly connect an accelerator to the
shared memory of a PULP-based system. However, transactions using this protocol
are inherently latency sensitive. HWPE-Mem rule 2 embodies this: an operation
is complete only when its response has arrived. This means that HWPE-Mem
streams, including load and store transactions, cannot be enqueued in
a FIFO queue.
To overcome this limitation, a variant of the HWPE-Mem protocol is
HWPE-MemDecoupled. This protocol uses the same interface as HWPE-Mem but
lifts rule 2 and adds a new rule 4. Transactions are thus following the
following rules:

1. **A valid handshake occurs in the cycle when both** *req* **and** *gnt*
   **are asserted**. This is true for both write and read transactions.

3. **The assertion of** *req* **(transition 0 to 1) cannot depend**
   **combinationally on the state of** *gnt*. On the other hand,
   the assertion of *gnt* (transition 0 to 1) can depend combinationally
   on the state of *req* (and typically it does). This rule avoids
   deadlocks in ping-pong logic.

4. **The stream of transactions includes only reads (** *wen* **=1) or**
   **only writes (** *wen* **=0)**. Mixing reads and writes in the stream
   is not allowed.

HWPE-MemDecoupled transactions are insensitive to latency and their
*request* and *response* phases can be treated similarly to separate
HWPE-Stream streams.
Once two or more HWPE-MemDecoupled transactions are mixed, the mixed
interface has to be treated as a HWPE-Mem protocol (i.e. it is sensitive
to latency).
