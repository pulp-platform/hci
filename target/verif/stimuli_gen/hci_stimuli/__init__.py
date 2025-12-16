"""
HCI Stimuli Generator Package

This package provides classes and functions for generating test stimuli
for the HCI verification environment.
"""

from .generator import StimuliGenerator
from .processor import unfold_raw_txt, pad_txt_files

__all__ = ['StimuliGenerator', 'unfold_raw_txt', 'pad_txt_files']

