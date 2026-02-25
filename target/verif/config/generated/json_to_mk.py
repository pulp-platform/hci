#!/usr/bin/env python3
"""
JSON to Makefile Converter using Templates

Converts JSON configuration files to Makefile format using Python templates.
Templates are automatically discovered based on the config type argument.
"""

import json
import argparse
import sys
from pathlib import Path
from string import Template

def load_json_config(filename):
    """Load and return JSON configuration."""
    try:
        with open(filename, 'r') as f:
            return json.load(f)
    except FileNotFoundError:
        print(f"ERROR: Configuration file not found: {filename}", file=sys.stderr)
        sys.exit(1)
    except json.JSONDecodeError as e:
        print(f"ERROR: Invalid JSON in {filename}: {e}", file=sys.stderr)
        sys.exit(1)

def load_template(filename):
    """Load and return template content."""
    try:
        with open(filename, 'r') as f:
            return f.read()
    except FileNotFoundError:
        print(f"ERROR: Template file not found: {filename}", file=sys.stderr)
        sys.exit(1)


def flatten_dict(d, prefix=''):
    """Flatten nested dictionary for template substitution."""
    items = []
    for k, v in d.items():
        new_key = f"{prefix}{k}" if prefix else k
        if isinstance(v, dict):
            items.extend(flatten_dict(v, f"{new_key}_").items())
        else:
            items.append((new_key, v))
    return dict(items)

def parse_args(argv=None):
    parser = argparse.ArgumentParser(
        description="Convert JSON configuration to Makefile fragment using templates."
    )
    parser.add_argument(
        "config_type",
        choices=["hardware", "testbench"],
        help="Configuration type to generate.",
    )
    parser.add_argument(
        "config_dir",
        type=Path,
        help="Directory containing source-of-truth JSON files.",
    )
    parser.add_argument(
        "generated_dir",
        type=Path,
        help="Directory containing mk templates and generated outputs.",
    )
    return parser.parse_args(argv)


def main():
    args = parse_args()
    config_type = args.config_type
    config_dir = args.config_dir.resolve()
    generated_dir = args.generated_dir.resolve()

    # Construct file paths based on config_type argument
    json_file = config_dir / f"{config_type}.json"
    template_file = generated_dir / f"{config_type}.mk.tpl"

    # Load JSON config
    config = load_json_config(json_file)

    # Load template
    template_content = load_template(template_file)

    # Flatten the parameters dict for template substitution
    template_data = flatten_dict(config['parameters'])

    # Apply template substitution
    template = Template(template_content)
    try:
        result = template.substitute(template_data)
    except KeyError as e:
        print(f"ERROR: Missing template variable: {e}", file=sys.stderr)
        sys.exit(1)

    # Output to stdout
    print(result)

if __name__ == '__main__':
    main()
