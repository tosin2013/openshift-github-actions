#!/usr/bin/env python3
"""
Template renderer for Vault deployment scripts.
This script renders Jinja2 templates using environment variables.
"""

import os
import sys
import json
from jinja2 import Environment, FileSystemLoader

def render_template(template_path, output_path, variables=None):
    """
    Render a Jinja2 template with the provided variables or environment variables.
    
    Args:
        template_path: Path to the Jinja2 template
        output_path: Path where the rendered template should be saved
        variables: Dictionary of variables to use for rendering (optional)
                  If not provided, all environment variables will be used
    """
    # Get the template directory and filename
    template_dir = os.path.dirname(template_path)
    template_file = os.path.basename(template_path)
    
    # Create Jinja2 environment
    env = Environment(loader=FileSystemLoader(template_dir))
    template = env.get_template(template_file)
    
    # Use provided variables or environment variables
    if variables is None:
        variables = dict(os.environ)
        
        # Convert string 'true'/'false' to boolean for Jinja2
        for key, value in variables.items():
            if value.lower() == 'true':
                variables[key] = True
            elif value.lower() == 'false':
                variables[key] = False
    
    # Render the template
    rendered_content = template.render(**variables)
    
    # Save the rendered content
    with open(output_path, 'w') as f:
        f.write(rendered_content)
    
    print(f"Template rendered successfully: {output_path}")

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: render_template.py <template_path> <output_path> [variables_json]")
        sys.exit(1)
    
    template_path = sys.argv[1]
    output_path = sys.argv[2]
    
    variables = None
    if len(sys.argv) > 3:
        variables_json = sys.argv[3]
        variables = json.loads(variables_json)
    
    render_template(template_path, output_path, variables)
