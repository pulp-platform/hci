# Select desired test configuration
SELECT_TEST ?= test_1


MASTERS_CONFIG_PATH := config/hardware_config/masters_config
HCI_CONFIG_PATH := config/hardware_config
SIM_CONFIG_PATH := config/sim_config
SELECT_TEST_MK := $(SELECT_TEST).mk
-include $(MASTERS_CONFIG_PATH)/*.mk
include $(SIM_CONFIG_PATH)/$(SELECT_TEST_MK)
include $(HCI_CONFIG_PATH)/hci_config.mk