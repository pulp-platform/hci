# Copyright 2025 ETH Zurich and University of Bologna.
# Solderpad Hardware License, Version 0.51, see LICENSE.solderpad for details.
# SPDX-License-Identifier: SHL-0.51
#
# Sergio Mazzola <smazzola@iis.ee.ethz.ch>

include bender.mk

HCI_ROOT = $(shell pwd)

# Tooling
BENDER ?= bender

################
# Dependencies #
################

.PHONY: checkout
checkout: $(HCI_ROOT)/.bender/.checkout_stamp

$(HCI_ROOT)/.bender/.checkout_stamp: $(HCI_ROOT)/Bender.lock
	$(BENDER) checkout && \
	date > $@

###########
# Targets #
###########

include $(HCI_ROOT)/rtl/rtl.mk
include $(HCI_ROOT)/target/verif/verif.mk
