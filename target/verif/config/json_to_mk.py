#!/usr/bin/env python3
"""
JSON to Makefile Converter using Templates

Converts JSON configuration files to Makefile format using Python templates.
Templates are automatically discovered based on the config type argument.
"""

import json
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

def main():
    if len(sys.argv) != 2:
        print("Usage: python json_to_mk.py <config_type>", file=sys.stderr)
        print("Where <config_type> corresponds to <config_type>.json and <config_type>.mk.tpl", file=sys.stderr)
        print("Supported config types: hardware, testbench", file=sys.stderr)
        sys.exit(1)

    config_type = sys.argv[1]
    config_dir = Path(__file__).parent

    # Construct file paths based on config_type argument
    json_file = config_dir / f"{config_type}.json"
    template_file = config_dir / f"{config_type}.mk.tpl"

    # Load JSON config
    config = load_json_config(json_file)

    # Load template
    template_content = load_template(template_file)

    # Process data - only hardware and testbench generate Makefiles
    # Workload config is only used by Python scripts, not Makefiles
    if config_type not in ['hardware', 'testbench']:
        print(f"ERROR: Config type '{config_type}' does not generate a Makefile. Use: hardware or testbench", file=sys.stderr)
        sys.exit(1)
    
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