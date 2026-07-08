import http from 'node:http';
import { randomUUID } from 'node:crypto';
import { promises as fs } from 'node:fs';
import path from 'node:path';

const host = process.env.MCP_RUNTIME_HOST || '0.0.0.0';
const port = Number.parseInt(process.env.MCP_RUNTIME_PORT || '37651', 10);
const connections = new Map();
const workspaceRoot = path.resolve(process.env.MCP_RUNTIME_WORKSPACE_ROOT || process.cwd());
const maxTextBytes = Number.parseInt(process.env.MCP_RUNTIME_MAX_TEXT_BYTES || '65536', 10);

function jsonResponse(res, status, payload) {
  const body = JSON.stringify(payload);
  res.writeHead(status, {
    'content-type': 'application/json; charset=utf-8',
    'content-length': Buffer.byteLength(body),
    'cache-control': 'no-store',
  });
  res.end(body);
}

function sendSse(res, event, payload) {
  const data = typeof payload === 'string' ? payload : JSON.stringify(payload);
  res.write('event: ' + event + '\n');
  res.write('data: ' + data + '\n\n');
}

function textResult(payload) {
  return {
    content: [
      {
        type: 'text',
        text: JSON.stringify(payload, null, 2),
      },
    ],
    isError: false,
  };
}

function runtimeInfo() {
  return {
    runtime: 'simichat-node-container',
    dependencyMode: 'container',
    externalProcess: false,
    requiresHostNode: false,
    requiresHostNpx: false,
    nodeVersion: process.version,
    platform: process.platform,
    pid: process.pid,
    mobileDefault: false,
    desktopReady: true,
    transport: 'sse',
    workspaceRoot,
    maxTextBytes,
  };
}

function tools() {
  return [
    {
      name: 'simichat.node_runtime_info',
      description: '返回 SimiChat Node 容器 MCP Runtime 状态。Node 在容器内，不依赖宿主机 node/npx。',
      inputSchema: { type: 'object', properties: {} },
    },
    {
      name: 'simichat.echo',
      description: '回显传入文本，用于验证容器 MCP 工具调用链路。',
      inputSchema: {
        type: 'object',
        properties: {
          text: { type: 'string', description: '需要回显的文本。' },
        },
      },
    },
    {
      name: 'simichat.fs_list',
      description: '列出容器授权工作目录内的文件。路径会被限制在 MCP_RUNTIME_WORKSPACE_ROOT 内。',
      inputSchema: {
        type: 'object',
        properties: {
          path: { type: 'string', description: '相对工作目录的路径，默认 .。' },
          maxEntries: { type: 'integer', description: '最多返回条目数，默认 50，最大 200。' },
        },
      },
    },
    {
      name: 'simichat.fs_read_text',
      description: '读取容器授权工作目录内的 UTF-8 文本文件，自动限制最大字节数。',
      inputSchema: {
        type: 'object',
        properties: {
          path: { type: 'string', description: '相对工作目录的文件路径。' },
          maxBytes: { type: 'integer', description: '最多读取字节数，默认 65536。' },
        },
        required: ['path'],
      },
    },
    {
      name: 'simichat.fetch_text',
      description: '从容器内发起只读 HTTP(S) GET 请求并返回文本摘要，用于替代宿主机 npx fetch 类 MCP。',
      inputSchema: {
        type: 'object',
        properties: {
          url: { type: 'string', description: 'HTTP 或 HTTPS URL。' },
          maxBytes: { type: 'integer', description: '最多返回字节数，默认 65536。' },
        },
        required: ['url'],
      },
    },
  ];
}

function resources() {
  return [
    {
      uri: 'simichat-container://runtime/info',
      name: 'SimiChat Node 容器 Runtime',
      description: 'PC 端 Node MCP 容器侧车运行状态。',
      mimeType: 'application/json',
    },
    {
      uri: 'simichat-container://workspace/info',
      name: 'SimiChat MCP 容器工作目录',
      description: '当前容器授权工作目录与读取限制。',
      mimeType: 'application/json',
    },
  ];
}

function clampInteger(value, fallback, min, max) {
  const parsed = Number.parseInt(value, 10);
  if (!Number.isFinite(parsed)) return fallback;
  return Math.min(Math.max(parsed, min), max);
}

function resolveWorkspacePath(inputPath = '.') {
  const rawPath = String(inputPath || '.');
  if (path.isAbsolute(rawPath)) {
    throw new Error('Only paths relative to MCP_RUNTIME_WORKSPACE_ROOT are allowed');
  }
  const resolved = path.resolve(workspaceRoot, rawPath);
  if (resolved !== workspaceRoot && !resolved.startsWith(workspaceRoot + path.sep)) {
    throw new Error('Path escapes MCP_RUNTIME_WORKSPACE_ROOT');
  }
  return resolved;
}

function relativeWorkspacePath(resolvedPath) {
  const relative = path.relative(workspaceRoot, resolvedPath);
  return relative === '' ? '.' : relative;
}

async function listWorkspaceDirectory(args = {}) {
  const target = resolveWorkspacePath(args.path || '.');
  const maxEntries = clampInteger(args.maxEntries, 50, 1, 200);
  const entries = await fs.readdir(target, { withFileTypes: true });
  return textResult({
    root: workspaceRoot,
    path: relativeWorkspacePath(target),
    truncated: entries.length > maxEntries,
    entries: entries.slice(0, maxEntries).map((entry) => ({
      name: entry.name,
      type: entry.isDirectory() ? 'directory' : entry.isFile() ? 'file' : 'other',
    })),
  });
}

async function readWorkspaceText(args = {}) {
  const target = resolveWorkspacePath(args.path);
  const stat = await fs.stat(target);
  if (!stat.isFile()) {
    throw new Error('Path is not a regular file');
  }
  const limit = clampInteger(args.maxBytes, maxTextBytes, 1, maxTextBytes);
  const file = await fs.open(target, 'r');
  try {
    const buffer = Buffer.alloc(Math.min(limit, stat.size));
    const read = await file.read(buffer, 0, buffer.length, 0);
    return textResult({
      root: workspaceRoot,
      path: relativeWorkspacePath(target),
      sizeBytes: stat.size,
      truncated: stat.size > read.bytesRead,
      text: buffer.subarray(0, read.bytesRead).toString('utf8'),
    });
  } finally {
    await file.close();
  }
}

async function fetchText(args = {}) {
  const url = new URL(String(args.url || ''));
  if (url.protocol !== 'http:' && url.protocol !== 'https:') {
    throw new Error('Only HTTP(S) URLs are allowed');
  }
  const limit = clampInteger(args.maxBytes, maxTextBytes, 1, maxTextBytes);
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 10000);
  try {
    const response = await fetch(url, { method: 'GET', signal: controller.signal });
    const arrayBuffer = await response.arrayBuffer();
    const buffer = Buffer.from(arrayBuffer);
    return textResult({
      url: url.toString(),
      status: response.status,
      ok: response.ok,
      contentType: response.headers.get('content-type') || '',
      sizeBytes: buffer.length,
      truncated: buffer.length > limit,
      text: buffer.subarray(0, limit).toString('utf8'),
    });
  } finally {
    clearTimeout(timeout);
  }
}

async function handleMcp(message) {
  const method = message.method;
  const params = message.params && typeof message.params === 'object' ? message.params : {};

  switch (method) {
    case 'initialize':
      return {
        protocolVersion: '2024-11-05',
        capabilities: { tools: {}, resources: {} },
        serverInfo: { name: 'SimiChat Node Container MCP', version: '1.1.0' },
      };
    case 'tools/list':
      return { tools: tools() };
    case 'resources/list':
      return { resources: resources() };
    case 'resources/read':
      if (params.uri === 'simichat-container://runtime/info') {
        return {
          contents: [
            {
              uri: params.uri,
              mimeType: 'application/json',
              text: JSON.stringify(runtimeInfo(), null, 2),
            },
          ],
        };
      }
      if (params.uri === 'simichat-container://workspace/info') {
        return {
          contents: [
            {
              uri: params.uri,
              mimeType: 'application/json',
              text: JSON.stringify({ root: workspaceRoot, maxTextBytes }, null, 2),
            },
          ],
        };
      }
      return {
        contents: [
          {
            uri: params.uri || '',
            mimeType: 'text/plain',
            text: '未知资源: ' + (params.uri || ''),
          },
        ],
      };
    case 'tools/call':
      if (params.name === 'simichat.node_runtime_info') {
        return textResult(runtimeInfo());
      }
      if (params.name === 'simichat.echo') {
        return textResult({ text: String(params.arguments?.text || '') });
      }
      if (params.name === 'simichat.fs_list') {
        return listWorkspaceDirectory(params.arguments || {});
      }
      if (params.name === 'simichat.fs_read_text') {
        return readWorkspaceText(params.arguments || {});
      }
      if (params.name === 'simichat.fetch_text') {
        return fetchText(params.arguments || {});
      }
      return {
        content: [{ type: 'text', text: '未知工具: ' + (params.name || '') }],
        isError: true,
      };
    default:
      throw new Error('Unsupported MCP method: ' + method);
  }
}

function readJsonBody(req, res, maxBytes = 1024 * 1024) {
  return new Promise((resolve, reject) => {
    let size = 0;
    const chunks = [];
    req.on('data', (chunk) => {
      size += chunk.length;
      if (size > maxBytes) {
        reject(new Error('request body too large'));
        req.destroy();
        return;
      }
      chunks.push(chunk);
    });
    req.on('end', () => {
      try {
        const body = Buffer.concat(chunks).toString('utf8');
        resolve(body.trim() ? JSON.parse(body) : {});
      } catch (error) {
        reject(error);
      }
    });
    req.on('error', reject);
  });
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url || '/', 'http://' + (req.headers.host || ('127.0.0.1:' + port)));

  if (req.method === 'GET' && url.pathname === '/health') {
    return jsonResponse(res, 200, { ok: true, ...runtimeInfo() });
  }

  const sseMatch = url.pathname.match(/^\/mcp\/sse\/([a-zA-Z0-9._-]+)$/);
  if (req.method === 'GET' && sseMatch) {
    const connectionId = randomUUID();
    res.writeHead(200, {
      'content-type': 'text/event-stream; charset=utf-8',
      'cache-control': 'no-cache, no-transform',
      connection: 'keep-alive',
      'x-accel-buffering': 'no',
    });
    res.write(': connected\n\n');
    connections.set(connectionId, { res, serverId: sseMatch[1] });
    sendSse(res, 'endpoint', '/mcp/messages/' + connectionId);
    const keepAlive = setInterval(() => res.write(': keepalive\n\n'), 15000);
    req.on('close', () => {
      clearInterval(keepAlive);
      connections.delete(connectionId);
    });
    return;
  }

  const messageMatch = url.pathname.match(/^\/mcp\/messages\/([a-f0-9-]+)$/);
  if (req.method === 'POST' && messageMatch) {
    const connection = connections.get(messageMatch[1]);
    if (!connection) {
      return jsonResponse(res, 404, { error: 'MCP SSE connection not found' });
    }

    try {
      const message = await readJsonBody(req, res);
      if (message.id !== undefined && message.id !== null) {
        try {
          const result = await handleMcp(message);
          sendSse(connection.res, 'message', {
            jsonrpc: '2.0',
            id: message.id,
            result,
          });
        } catch (error) {
          sendSse(connection.res, 'message', {
            jsonrpc: '2.0',
            id: message.id,
            error: {
              code: -32603,
              message: error instanceof Error ? error.message : String(error),
            },
          });
        }
      }
      return jsonResponse(res, 202, { accepted: true });
    } catch (error) {
      return jsonResponse(res, 400, {
        error: error instanceof Error ? error.message : String(error),
      });
    }
  }

  return jsonResponse(res, 404, { error: 'not found' });
});

server.listen(port, host, () => {
  console.log('SimiChat MCP runtime listening on ' + host + ':' + port);
});
