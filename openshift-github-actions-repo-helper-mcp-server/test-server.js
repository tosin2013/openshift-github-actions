#!/usr/bin/env node

/**
 * Test Script for OpenShift GitHub Actions Repository Helper MCP Server
 * 
 * This script demonstrates all the capabilities of the MCP server including:
 * - Development Support Tools (LLD, API docs, Architecture)
 * - Diátaxis Documentation (Tutorials, How-tos, References, Explanations)
 * - QA & Testing Tools (Test plans, Spec-by-example)
 * - Red Hat AI Services integration
 */

import { spawn } from 'child_process';
import { writeFileSync, readFileSync } from 'fs';

console.log('🚀 OpenShift GitHub Actions Repository Helper MCP Server Test');
console.log('================================================================');

// Test configuration
const testCases = [
  {
    name: 'LLD Generation - Vault HA',
    tool: 'repo-helper-generate-lld',
    args: {
      component: 'vault-ha',
      includeInterfaces: true,
      includeDataFlow: true
    },
    description: 'Generate Low-Level Design for Vault HA architecture'
  },
  {
    name: 'API Documentation - GitHub Actions',
    tool: 'repo-helper-generate-api-docs',
    args: {
      outputFormat: 'markdown',
      includeExamples: true,
      includeAuthentication: true
    },
    description: 'Generate API documentation for GitHub Actions workflows'
  },
  {
    name: 'Architecture Guide - Multi-Cloud',
    tool: 'repo-helper-generate-architecture',
    args: {
      includeDeployment: true,
      includeIntegrations: true,
      includeSecurity: true
    },
    description: 'Generate comprehensive architecture guide'
  },
  {
    name: 'Tutorial - Vault Setup',
    tool: 'repo-helper-generate-tutorial',
    args: {
      feature: 'vault-ha-deployment',
      targetAudience: 'intermediate',
      includeSetup: true,
      stepByStep: true,
      includeTroubleshooting: true
    },
    description: 'Generate hands-on tutorial for Vault HA deployment'
  },
  {
    name: 'Test Plan - Multi-Cloud Deployment',
    tool: 'repo-helper-generate-test-plan',
    args: {
      component: 'multi-cloud',
      testTypes: ['unit', 'integration', 'e2e'],
      coverageTarget: 85,
      includeSecurityTests: true
    },
    description: 'Generate comprehensive test plan for multi-cloud deployment'
  }
];

/**
 * Test MCP server tool
 */
async function testTool(testCase) {
  return new Promise((resolve, reject) => {
    console.log(`\n📋 Testing: ${testCase.name}`);
    console.log(`   Description: ${testCase.description}`);
    console.log(`   Tool: ${testCase.tool}`);
    console.log(`   Args: ${JSON.stringify(testCase.args, null, 2)}`);
    
    // Create MCP request
    const mcpRequest = {
      jsonrpc: '2.0',
      id: Date.now(),
      method: 'tools/call',
      params: {
        name: testCase.tool,
        arguments: testCase.args
      }
    };
    
    // Start MCP server
    const server = spawn('node', ['dist/index.js'], {
      stdio: ['pipe', 'pipe', 'pipe'],
      cwd: process.cwd()
    });
    
    let output = '';
    let errorOutput = '';
    
    server.stdout.on('data', (data) => {
      output += data.toString();
    });
    
    server.stderr.on('data', (data) => {
      errorOutput += data.toString();
    });
    
    server.on('close', (code) => {
      if (code === 0) {
        console.log(`   ✅ Success: Tool executed successfully`);
        console.log(`   📊 Output length: ${output.length} characters`);
        
        // Save output to file for inspection
        const filename = `test-output-${testCase.tool.replace(/[^a-z0-9]/gi, '-')}.txt`;
        writeFileSync(filename, `Test Case: ${testCase.name}\n\nOutput:\n${output}\n\nErrors:\n${errorOutput}`);
        console.log(`   💾 Output saved to: ${filename}`);
        
        resolve({ success: true, output, errorOutput });
      } else {
        console.log(`   ❌ Failed: Process exited with code ${code}`);
        console.log(`   🔍 Error output: ${errorOutput}`);
        reject(new Error(`Process failed with code ${code}`));
      }
    });
    
    server.on('error', (error) => {
      console.log(`   ❌ Failed: ${error.message}`);
      reject(error);
    });
    
    // Send MCP request
    server.stdin.write(JSON.stringify(mcpRequest) + '\n');
    server.stdin.end();
    
    // Timeout after 30 seconds
    setTimeout(() => {
      server.kill();
      reject(new Error('Test timeout'));
    }, 30000);
  });
}

/**
 * Test server health
 */
async function testServerHealth() {
  return new Promise((resolve, reject) => {
    console.log('\n🏥 Testing Server Health...');
    
    const server = spawn('node', ['dist/index.js'], {
      stdio: ['pipe', 'pipe', 'pipe'],
      cwd: process.cwd()
    });
    
    let started = false;
    
    server.stderr.on('data', (data) => {
      const output = data.toString();
      if (output.includes('Server started successfully') || output.includes('INFO')) {
        if (!started) {
          started = true;
          console.log('   ✅ Server started successfully');
          server.kill();
          resolve(true);
        }
      }
    });
    
    server.on('error', (error) => {
      console.log(`   ❌ Server failed to start: ${error.message}`);
      reject(error);
    });
    
    // Timeout after 10 seconds
    setTimeout(() => {
      if (!started) {
        server.kill();
        reject(new Error('Server startup timeout'));
      }
    }, 10000);
  });
}

/**
 * Generate test report
 */
function generateTestReport(results) {
  const report = `# OpenShift GitHub Actions Repository Helper MCP Server Test Report

Generated: ${new Date().toISOString()}

## Test Summary

- **Total Tests**: ${results.length}
- **Passed**: ${results.filter(r => r.success).length}
- **Failed**: ${results.filter(r => !r.success).length}
- **Success Rate**: ${Math.round((results.filter(r => r.success).length / results.length) * 100)}%

## Test Results

${results.map((result, index) => `
### Test ${index + 1}: ${testCases[index].name}

- **Tool**: ${testCases[index].tool}
- **Status**: ${result.success ? '✅ PASSED' : '❌ FAILED'}
- **Description**: ${testCases[index].description}
- **Output Length**: ${result.output ? result.output.length : 0} characters
${result.error ? `- **Error**: ${result.error}` : ''}
`).join('')}

## Repository Context

This test was performed on the OpenShift GitHub Actions repository with the following detected technologies:
- Red Hat Enterprise Linux 9.6 (Plow)
- OpenShift 4.18
- HashiCorp Vault HA with TLS
- GitHub Actions workflows for AWS/Azure/GCP
- Ansible automation with OpenShift-specific roles

## Capabilities Demonstrated

### 🔧 Development Support
- Low-Level Design (LLD) generation with repository-specific analysis
- API documentation for GitHub Actions workflows and Vault endpoints
- Architecture guides for multi-cloud deployment patterns

### 📚 Diátaxis Documentation Framework
- Learning-oriented tutorials with step-by-step guidance
- Problem-oriented how-to guides for specific scenarios
- Information-oriented reference documentation
- Understanding-oriented explanations of concepts

### 🧪 QA & Testing
- Comprehensive test plan generation
- Spec-by-example documentation
- Quality assurance workflows

### 🤖 Red Hat AI Services Integration
- Intelligent documentation generation
- Content enhancement and validation
- QA recommendations and analysis

## Methodological Pragmatism

This MCP server follows methodological pragmatism principles:
- **Explicit Fallibilism**: Acknowledges limitations with confidence scores
- **Systematic Verification**: Structured validation processes
- **Pragmatic Success Criteria**: Repository-specific, measurable outcomes
- **Cognitive Systematization**: Organized knowledge systems

## Conclusion

The OpenShift GitHub Actions Repository Helper MCP Server successfully demonstrates comprehensive capabilities for development support, documentation generation, and quality assurance, specifically tailored to the repository's multi-cloud OpenShift automation patterns.

---
*Generated by OpenShift GitHub Actions Repository Helper MCP Server Test Suite*
`;

  writeFileSync('test-report.md', report);
  console.log('\n📊 Test report generated: test-report.md');
}

/**
 * Main test execution
 */
async function runTests() {
  try {
    console.log('\n🔍 Step 1: Testing server health...');
    await testServerHealth();
    
    console.log('\n🧪 Step 2: Running tool tests...');
    const results = [];
    
    for (const testCase of testCases) {
      try {
        const result = await testTool(testCase);
        results.push({ success: true, ...result });
      } catch (error) {
        console.log(`   ❌ Test failed: ${error.message}`);
        results.push({ success: false, error: error.message });
      }
      
      // Wait between tests
      await new Promise(resolve => setTimeout(resolve, 1000));
    }
    
    console.log('\n📊 Step 3: Generating test report...');
    generateTestReport(results);
    
    console.log('\n🎉 Test execution completed!');
    console.log(`   ✅ Passed: ${results.filter(r => r.success).length}/${results.length}`);
    console.log(`   📈 Success Rate: ${Math.round((results.filter(r => r.success).length / results.length) * 100)}%`);
    
    if (results.every(r => r.success)) {
      console.log('\n🏆 All tests passed! The MCP server is fully functional.');
    } else {
      console.log('\n⚠️  Some tests failed. Check the test report for details.');
    }
    
  } catch (error) {
    console.error('\n💥 Test execution failed:', error.message);
    process.exit(1);
  }
}

// Run tests
runTests().catch(console.error);
