#!/usr/bin/env node

import { spawn } from 'child_process';

async function testGeminiServer() {
  console.log('🚀 Testing Gemini MCP Server startup...');
  
  return new Promise((resolve) => {
    const server = spawn('node', ['dist/index.js'], { 
      stdio: ['pipe', 'pipe', 'pipe'],
      env: { ...process.env, LOG_LEVEL: 'info' }
    });
    
    let stdout = '';
    let serverStarted = false;
    
    server.stdout.on('data', (data) => {
      const output = data.toString();
      stdout += output;
      console.log('STDOUT:', output);
      
      if (output.includes('Gemini MCP Server is running')) {
        serverStarted = true;
        console.log('✅ Gemini MCP Server started successfully');
        
        // Send a tool list request
        const request = {
          jsonrpc: '2.0',
          id: 1,
          method: 'tools/list',
          params: {}
        };
        server.stdin.write(JSON.stringify(request) + '\n');
      }
      
      try {
        const response = JSON.parse(output);
        if (response.result && response.result.tools) {
          console.log('✅ Received tool list:', response.result.tools.map(t => t.name));
          server.kill('SIGTERM');
        }
      } catch (e) {
        // Not JSON
      }
    });
    
    server.stderr.on('data', (data) => {
      console.error('STDERR:', data.toString());
    });
    
    server.on('close', (code) => {
      if (serverStarted) {
        console.log('✅ Gemini MCP Server stopped cleanly');
        resolve(true);
      } else {
        console.error('❌ Gemini MCP Server failed to start properly');
        resolve(false);
      }
    });
    
    setTimeout(() => {
      if (!serverStarted) {
        console.error('❌ Timeout');
        server.kill('SIGKILL');
        resolve(false);
      }
    }, 10000);
  });
}

testGeminiServer().then(success => process.exit(success ? 0 : 1));
