"""Processor helpers: pad stimuli files to equal length."""


def pad_txt_files(folder_path, IW, DATA_WIDTH, ADD_WIDTH, HWPE_WIDTH_FACT):
    """No-op: padding stimuli files to a common length is not needed.

    Each application_driver self-terminates when its transaction queue is
    exhausted, and later-phase drivers are held in reset via clear_i until
    their dependencies assert end_req_o. Cross-file length alignment would
    only add unnecessary idle cycles at the end of early-phase files.
    """
    pass
