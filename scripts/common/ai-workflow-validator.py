#!/usr/bin/env python3
"""
AI-Powered GitHub Actions Workflow Validator and Fixer
Uses Red Hat Granite AI to detect and fix common workflow issues

Author: Tosin Akinosho
"""

import os
import sys
import json
import yaml
import argparse
import requests
import urllib3
from pathlib import Path
from typing import Dict, List, Tuple, Optional

# Disable SSL warnings for development
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

class GraniteAIClient:
    """Client for Red Hat Granite AI Services"""
    
    def __init__(self, api_url: str, api_key: str):
        self.api_url = api_url.rstrip('/')
        self.api_key = api_key
        self.headers = {'Authorization': f'Bearer {api_key}'}
    
    def complete(self, prompt: str, max_tokens: int = 500, temperature: float = 0.1) -> str:
        """Generate completion using Granite AI"""
        try:
            response = requests.post(
                url=f"{self.api_url}/v1/completions",
                json={
                    "model": "granite-8b-code-instruct-128k",
                    "prompt": prompt,
                    "max_tokens": max_tokens,
                    "temperature": temperature
                },
                headers=self.headers,
                timeout=30,
                verify=False  # For development only
            )
            response.raise_for_status()
            result = response.json()
            return result['choices'][0]['text'].strip()
        except Exception as e:
            print(f"❌ AI completion failed: {e}")
            return ""

class WorkflowValidator:
    """GitHub Actions workflow validator with AI assistance"""
    
    def __init__(self, ai_client: GraniteAIClient):
        self.ai_client = ai_client
        self.required_fields = ['name', 'on', 'jobs']
        self.issues_found = []
    
    def validate_yaml_syntax(self, file_path: str) -> Tuple[bool, Optional[Dict]]:
        """Validate YAML syntax and return parsed data"""
        try:
            with open(file_path, 'r', encoding='utf-8') as f:
                data = yaml.safe_load(f)
            return True, data
        except yaml.YAMLError as e:
            self.issues_found.append(f"YAML syntax error in {file_path}: {e}")
            return False, None
        except Exception as e:
            self.issues_found.append(f"File error in {file_path}: {e}")
            return False, None
    
    def validate_workflow_structure(self, data: Dict, file_path: str) -> bool:
        """Validate GitHub Actions workflow structure"""
        valid = True
        
        # Check required top-level fields
        missing_fields = [field for field in self.required_fields if field not in data]
        if missing_fields:
            self.issues_found.append(f"Missing required fields in {file_path}: {missing_fields}")
            valid = False
        
        # Check for boolean keys (common YAML parsing issue)
        for key in data.keys():
            if isinstance(key, bool):
                self.issues_found.append(f"Boolean key detected in {file_path}: {key} (likely 'on' parsed as True)")
                valid = False
        
        # Validate jobs structure
        if 'jobs' in data and isinstance(data['jobs'], dict):
            for job_name, job_config in data['jobs'].items():
                if not isinstance(job_config, dict):
                    continue
                
                # Check if this is a reusable workflow job (has 'uses' key)
                is_reusable_workflow = 'uses' in job_config
                
                if not is_reusable_workflow and 'runs-on' not in job_config:
                    self.issues_found.append(f"Job '{job_name}' missing 'runs-on' in {file_path}")
                    valid = False
                
                if not is_reusable_workflow and 'steps' not in job_config:
                    self.issues_found.append(f"Job '{job_name}' missing 'steps' in {file_path}")
                    valid = False
        
        return valid
    
    def clean_ai_response(self, ai_response: str) -> str:
        """Clean AI response to extract pure YAML content"""
        if not ai_response:
            return ""
        
        # Remove markdown code blocks
        lines = ai_response.strip().split('\n')
        start_idx = 0
        end_idx = len(lines)
        
        # Find start of YAML content (skip code block markers)
        for i, line in enumerate(lines):
            if line.strip().startswith('```yaml') or line.strip().startswith('````yaml'):
                start_idx = i + 1
                break
            elif line.strip().startswith('```') or line.strip().startswith('````'):
                start_idx = i + 1
                break
        
        # Find end of YAML content (skip code block markers)
        for i in range(len(lines) - 1, -1, -1):
            if lines[i].strip().startswith('```') or lines[i].strip().startswith('````'):
                end_idx = i
                break
        
        # Extract clean YAML content
        yaml_content = '\n'.join(lines[start_idx:end_idx])
        
        # Additional cleanup - remove any leading/trailing whitespace
        return yaml_content.strip()

    def ai_analyze_workflow(self, file_path: str, file_content: str) -> str:
        """Use AI to analyze workflow and suggest fixes"""
        prompt = f"""You are a GitHub Actions workflow expert. Analyze this workflow file and identify issues:

File: {file_path}
Content:
```yaml
{file_content[:2000]}  # Limit content for prompt
```

Common issues to check:
1. YAML syntax errors
2. Missing required fields: name, on, jobs
3. Boolean 'on' key (should be quoted as "on")
4. Missing 'runs-on' in jobs
5. Missing 'steps' in jobs
6. Indentation issues
7. Invalid trigger configurations

Provide a concise analysis and specific fixes needed:"""

        return self.ai_client.complete(prompt, max_tokens=300)
    
    def ai_fix_workflow(self, file_content: str, issues: List[str]) -> str:
        """Use AI to generate fixed workflow content"""
        issues_text = "\n".join(f"- {issue}" for issue in issues)
        
        prompt = f"""Fix this GitHub Actions workflow YAML. The following issues were detected:

Issues to fix:
{issues_text}

Original YAML:
```yaml
{file_content[:1500]}  # Limit for prompt
```

Provide the corrected YAML with proper syntax and structure. Focus on:
1. Quoting 'on' key if it's being parsed as boolean
2. Ensuring proper indentation
3. Adding missing required fields
4. Fixing job structure

Return only the corrected YAML:"""

        return self.ai_client.complete(prompt, max_tokens=800)
    
    def validate_file(self, file_path: str, auto_fix: bool = False) -> bool:
        """Validate a single workflow file"""
        print(f"🔍 Validating: {file_path}")
        
        # Read file content
        try:
            with open(file_path, 'r', encoding='utf-8') as f:
                content = f.read()
        except Exception as e:
            self.issues_found.append(f"Cannot read {file_path}: {e}")
            return False
        
        # Validate YAML syntax
        is_valid_yaml, data = self.validate_yaml_syntax(file_path)
        
        if not is_valid_yaml:
            if auto_fix:
                print("🤖 Using AI to analyze and fix issues...")
                ai_analysis = self.ai_analyze_workflow(file_path, content)
                print(f"📋 AI Analysis: {ai_analysis}")
                
                fixed_content = self.ai_fix_workflow(content, self.issues_found[-1:])
                if fixed_content:
                    # Clean AI response to extract pure YAML
                    cleaned_content = self.clean_ai_response(fixed_content)
                    if cleaned_content:
                        backup_path = f"{file_path}.backup"
                        if not os.path.exists(backup_path):
                            os.rename(file_path, backup_path)
                        
                        with open(file_path, 'w', encoding='utf-8') as f:
                            f.write(cleaned_content)
                    
                    print(f"✅ Fixed workflow saved. Backup: {backup_path}")
                    # Re-validate
                    return self.validate_file(file_path, auto_fix=False)
            return False
        
        # Validate structure
        is_valid_structure = self.validate_workflow_structure(data, file_path)
        
        if not is_valid_structure and auto_fix:
            print("🤖 Using AI to fix structural issues...")
            ai_fix = self.ai_fix_workflow(content, self.issues_found[-3:])
            if ai_fix:
                # Clean AI response to extract pure YAML
                cleaned_fix = self.clean_ai_response(ai_fix)
                if cleaned_fix:
                    backup_path = f"{file_path}.backup"
                    if not os.path.exists(backup_path):
                        os.rename(file_path, backup_path)
                    
                    with open(file_path, 'w', encoding='utf-8') as f:
                        f.write(cleaned_fix)
                
                print(f"✅ Fixed workflow saved. Backup: {backup_path}")
                return True
        
        if is_valid_yaml and is_valid_structure:
            print(f"✅ {file_path} is valid")
            return True
        
        return False
    
    def validate_directory(self, directory: str, auto_fix: bool = False) -> bool:
        """Validate all workflow files in a directory"""
        workflow_dir = Path(directory)
        if not workflow_dir.exists():
            print(f"❌ Directory not found: {directory}")
            return False
        
        workflow_files = []
        for pattern in ['*.yml', '*.yaml']:
            workflow_files.extend(workflow_dir.glob(pattern))
        
        if not workflow_files:
            print(f"ℹ️  No workflow files found in {directory}")
            return True
        
        print(f"🔍 Found {len(workflow_files)} workflow files")
        
        all_valid = True
        for file_path in workflow_files:
            if not self.validate_file(str(file_path), auto_fix):
                all_valid = False
        
        return all_valid
    
    def get_report(self) -> Dict:
        """Generate validation report"""
        return {
            "total_issues": len(self.issues_found),
            "issues": self.issues_found,
            "status": "passed" if len(self.issues_found) == 0 else "failed"
        }

def main():
    parser = argparse.ArgumentParser(description="AI-Powered GitHub Actions Workflow Validator")
    parser.add_argument("path", help="Path to workflow file or directory")
    parser.add_argument("--auto-fix", action="store_true", help="Automatically fix issues using AI")
    parser.add_argument("--api-url", default="https://granite-8b-code-instruct-maas-apicast-production.apps.prod.rhoai.rh-aiservices-bu.com:443", help="Granite AI API URL")
    parser.add_argument("--api-key", help="Granite AI API key (or set REDHAT_AI_API_KEY env var)")
    parser.add_argument("--output", help="Output report to JSON file")
    
    args = parser.parse_args()
    
    # Get API key
    api_key = args.api_key or os.getenv('REDHAT_AI_API_KEY')
    if not api_key:
        print("❌ API key required. Use --api-key or set REDHAT_AI_API_KEY environment variable")
        sys.exit(1)
    
    # Initialize AI client and validator
    ai_client = GraniteAIClient(args.api_url, api_key)
    validator = WorkflowValidator(ai_client)
    
    # Validate
    path = Path(args.path)
    if path.is_file():
        success = validator.validate_file(str(path), args.auto_fix)
    elif path.is_dir():
        success = validator.validate_directory(str(path), args.auto_fix)
    else:
        print(f"❌ Path not found: {args.path}")
        sys.exit(1)
    
    # Generate report
    report = validator.get_report()
    
    if args.output:
        with open(args.output, 'w') as f:
            json.dump(report, f, indent=2)
        print(f"📄 Report saved to {args.output}")
    
    # Print summary
    if report["total_issues"] > 0:
        print(f"\n❌ Validation failed with {report['total_issues']} issues:")
        for issue in report["issues"]:
            print(f"  • {issue}")
        sys.exit(1)
    else:
        print("\n✅ All validations passed!")
        sys.exit(0)

if __name__ == "__main__":
    main()
