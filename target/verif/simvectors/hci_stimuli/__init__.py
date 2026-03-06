"""
HCI Stimuli Generator Package

This package provides classes and functions for generating test stimuli
for the HCI verification environment.
"""

from .generator import StimuliGenerator
from .processor import pad_txt_files

__all__ = ['StimuliGenerator', 'pad_txt_files']
