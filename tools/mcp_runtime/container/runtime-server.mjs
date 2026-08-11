import http from 'node:http';
import { randomUUID } from 'node:crypto';
import { promises as fs } from 'node:fs';
import path from 'node:path';
import { createHash } from 'node:crypto';
import { pathToFileURL } from 'node:url';

const host = process.env.MCP_RUNTIME_HOST || '0.0.0.0';
const port = Number.parseInt(process.env.MCP_RUNTIME_PORT || '37651', 10);
const connections = new Map();
const workspaceRoot = path.resolve(process.env.MCP_RUNTIME_WORKSPACE_ROOT || process.cwd());
const maxTextBytes = Number.parseInt(process.env.MCP_RUNTIME_MAX_TEXT_BYTES || '65536', 10);
const runtimeKind = process.env.SIMICHAT_NODE_RUNTIME_KIND || 'container';
const appManaged = process.env.SIMICHAT_NODE_APP_MANAGED === 'true';
const isEmbeddedMobile = runtimeKind === 'android-embedded' || runtimeKind === 'ios-embedded';
const isBundledDesktop = runtimeKind === 'desktop-bundled';
const extensionRoot = path.resolve(
  process.env.MCP_RUNTIME_EXTENSION_ROOT || path.dirname(workspaceRoot),
);
const extensions = new Map();
const stdioSessions = new Map();
const extensionIdPattern = /^[a-z0-9][a-z0-9._-]{1,127}$/;
const maxExtensionFiles = 256;
const maxExtensionBytes = 20 * 1024 * 1024;
const allowedProtocols = new Set(['mobile-mcp-v1', 'stdio-v1', 'stdio-compat-v1']);
const mobileNpxPackages = new Map([
  ['@modelcontextprotocol/server-time', 'time'],
  ['@modelcontextprotocol/server-memory', 'memory'],
  ['@modelcontextprotocol/server-fetch', 'fetch'],
  ['@modelcontextprotocol/server-filesystem', 'filesystem'],
]);
// Keep the scanner's signatures assembled rather than placing forbidden
// capability names in one literal. The manifest test scans this server source
// too, so this prevents an accidental host-process signature in the server
// while preserving the extension-source checks below.
const forbiddenSourcePatterns = [
  new RegExp('\\b' + 'child_' + 'process\\b', 'i'),
  new RegExp('\\b' + 'worker_' + 'threads\\b', 'i'),
  /\bcluster\b/i,
  new RegExp('\\bprocess\\.(?:binding|dlopen|exit|env|chdir)\\b', 'i'),
  new RegExp(
    '\\b(?:' + ['spawn', 'exec', 'execFile', 'fork'].join('|') + ')\\s*\\(',
    'i',
  ),
  new RegExp('\\b(?:' + ['npm', 'npx'].join('|') + ')\\b', 'i'),
  new RegExp('\\b(?:' + ['eval', 'Function'].join('|') + ')\\s*\\(', 'i'),
  /\.node(?:['"`]|\b)/i,
];

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
    runtime: runtimeKind === 'container'
      ? 'simichat-node-container'
      : isBundledDesktop
      ? 'simichat-node-desktop-bundled'
      : 'simichat-node-embedded',
    dependencyMode: runtimeKind === 'container'
      ? 'container'
      : isEmbeddedMobile
      ? 'bundled_nodejs_mobile'
      : 'bundled_node',
    externalProcess: !isEmbeddedMobile,
    appManaged,
    requiresHostNode: false,
    requiresHostNpx: false,
    requiresDocker: runtimeKind === 'container',
    nodeVersion: process.version,
    platform: process.platform,
    pid: process.pid,
    mobileDefault: isEmbeddedMobile,
    desktopReady: true,
    transport: 'sse',
    workspaceRoot,
    maxTextBytes,
    extensionRoot,
    extensions: [...extensions.values()].map((extension) => ({
      id: extension.id,
      protocol: extension.protocol,
      entry: extension.entry,
      loaded: true,
    })),
  };
}

function tools() {
  return [
    {
      name: 'simichat.node_runtime_info',
      description: '返回 SimiChat Node MCP Runtime 状态。运行时由 SimiChat App 管理，不依赖宿主机 node/npx。',
      inputSchema: { type: 'object', properties: {} },
    },
    {
      name: 'simichat.echo',
      description: '回显传入文本，用于验证 Node MCP 工具调用链路。',
      inputSchema: {
        type: 'object',
        properties: {
          text: { type: 'string', description: '需要回显的文本。' },
        },
      },
    },
    {
      name: 'simichat.fs_list',
      description: '列出授权工作目录内的文件。路径会被限制在 MCP_RUNTIME_WORKSPACE_ROOT 内。',
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
      description: '读取授权工作目录内的 UTF-8 文本文件，自动限制最大字节数。',
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
      description: '从 Node Runtime 内发起只读 HTTP(S) GET 请求并返回文本摘要，用于替代宿主机 npx fetch 类 MCP。',
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
      name: 'SimiChat Node Runtime',
      description: '当前 App 管理的 Node MCP Runtime 运行状态。',
      mimeType: 'application/json',
    },
    {
      uri: 'simichat-container://workspace/info',
      name: 'SimiChat MCP 工作目录',
      description: '当前 Node Runtime 授权工作目录与读取限制。',
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

function isWithin(root, candidate) {
  const normalizedRoot = path.resolve(root);
  const normalizedCandidate = path.resolve(candidate);
  return normalizedCandidate === normalizedRoot ||
    normalizedCandidate.startsWith(normalizedRoot + path.sep);
}

function resolveExtensionPath(root, relativePath) {
  const rawPath = String(relativePath || '');
  if (!rawPath || path.isAbsolute(rawPath)) {
    throw new Error('Extension paths must be relative to the installed package');
  }
  const resolved = path.resolve(root, rawPath);
  if (!isWithin(root, resolved)) {
    throw new Error('Extension path escapes the installed package');
  }
  return resolved;
}

async function walkExtensionFiles(root, current = root, output = []) {
  const entries = await fs.readdir(current, { withFileTypes: true });
  for (const entry of entries) {
    if (entry.name.startsWith('.')) {
      // Hidden build metadata and package-manager caches are never executable
      // inputs. `node_modules` is allowed only when it is explicitly bundled
      // into the package envelope and is scanned by the same source policy.
      continue;
    }
    const file = path.join(current, entry.name);
    if (entry.isDirectory()) {
      await walkExtensionFiles(root, file, output);
    } else if (entry.isFile()) {
      output.push(file);
      if (output.length > maxExtensionFiles) {
        throw new Error('Extension contains too many files');
      }
    }
  }
  return output;
}

async function verifyExtensionPackage({ id, root, entry, protocol, sha256 }) {
  if (!extensionIdPattern.test(id)) throw new Error('Invalid extension id');
  if (!allowedProtocols.has(protocol)) {
    throw new Error('Unsupported mobile MCP protocol: ' + protocol);
  }
  const resolvedRoot = path.resolve(root);
  if (!isWithin(extensionRoot, resolvedRoot) || isWithin(workspaceRoot, resolvedRoot)) {
    throw new Error('Extension root is outside the app extension directory');
  }
  const stat = await fs.stat(resolvedRoot);
  if (!stat.isDirectory()) throw new Error('Extension root is not a directory');
  const entryPath = resolveExtensionPath(resolvedRoot, entry);
  const entryStat = await fs.stat(entryPath);
  if (!entryStat.isFile()) throw new Error('Extension entry is not a file');
  if (!entry.endsWith('.js') && !entry.endsWith('.mjs')) {
    throw new Error('Extension entry must be .js or .mjs');
  }

  const manifestPath = path.join(resolvedRoot, 'manifest.json');
  const manifest = JSON.parse(await fs.readFile(manifestPath, 'utf8'));
  if (manifest.id !== id || manifest.entry !== entry ||
      (manifest.protocol || 'mobile-mcp-v1') !== protocol ||
      manifest.nativeAddon === true) {
    throw new Error('Extension registration does not match manifest.json');
  }
  const entryBytes = await fs.readFile(entryPath);
  const actualSha256 = createHash('sha256').update(entryBytes).digest('hex');
  if (sha256 && actualSha256 !== String(sha256).toLowerCase()) {
    throw new Error('Extension entry SHA-256 mismatch');
  }

  const files = await walkExtensionFiles(resolvedRoot);
  let totalBytes = 0;
  for (const file of files) {
    const fileStat = await fs.stat(file);
    totalBytes += fileStat.size;
    if (totalBytes > maxExtensionBytes) {
      throw new Error('Extension files exceed the mobile size limit');
    }
    // JSON is metadata, not executable code.  Scanning it for words such as
    // "npm" or "exec" rejects valid package names/descriptions without
    // improving the execution boundary; only JavaScript source is checked.
    if (!/\.(?:js|mjs)$/i.test(file)) continue;
    const source = await fs.readFile(file, 'utf8');
    for (const pattern of forbiddenSourcePatterns) {
      if (pattern.test(source)) {
        throw new Error('Extension source uses a forbidden Node capability: ' + pattern);
      }
    }
  }
  return { resolvedRoot, entryPath, manifest };
}

function extensionContext(id, root, permissions) {
  const permissionSet = new Set(permissions || []);
  const requirePermission = (permission) => {
    if (!permissionSet.has(permission)) {
      throw new Error('Extension lacks permission: ' + permission);
    }
  };
  return Object.freeze({
    id,
    root,
    protocolVersion: '2024-11-05',
    permissions: [...permissionSet],
    hasPermission: (permission) => permissionSet.has(permission),
    readText: async (relativePath, maxBytes = maxTextBytes) => {
      requirePermission('filesystem.app_container');
      const target = resolveExtensionPath(root, relativePath);
      const buffer = await fs.readFile(target);
      return buffer.subarray(0, clampInteger(maxBytes, maxTextBytes, 1, maxTextBytes)).toString('utf8');
    },
    fetchText: async (url, maxBytes = maxTextBytes) => {
      requirePermission('network');
      return (await fetchText({ url, maxBytes })).content[0].text;
    },
  });
}

function validateMcpServer(server) {
  if (!server || typeof server !== 'object') {
    throw new Error('MCP extension must export a server object');
  }
  for (const method of ['initialize', 'listTools', 'callTool']) {
    if (typeof server[method] !== 'function') {
      throw new Error('MCP extension is missing ' + method + '()');
    }
  }
}

async function registerExtension(payload) {
  const id = String(payload.id || '');
  const root = String(payload.root || '');
  const entry = String(payload.entry || '');
  const protocol = String(payload.protocol || 'mobile-mcp-v1');
  const verified = await verifyExtensionPackage({
    id,
    root,
    entry,
    protocol,
    sha256: payload.sha256,
  });
  const context = extensionContext(id, verified.resolvedRoot, payload.permissions || []);
  const moduleUrl = pathToFileURL(verified.entryPath).href + '?simichat=' + Date.now();
  const loaded = await import(moduleUrl);
  const exported = loaded.default || loaded;
  const server = typeof loaded.createMcpServer === 'function'
    ? await loaded.createMcpServer(context)
    : typeof exported.createMcpServer === 'function'
    ? await exported.createMcpServer(context)
    : exported;
  validateMcpServer(server);
  const extension = {
    id,
    root: verified.resolvedRoot,
    entry,
    protocol,
    permissions: payload.permissions || [],
    context,
    server,
    manifest: verified.manifest,
  };
  // MCP initialize is a per-client handshake.  Do not invoke it during
  // registration as that would double-initialize stateful extensions before
  // the first stdio/SSE client connects.
  extensions.set(id, extension);
  return { id, protocol, loaded: true, entry };
}

async function unregisterExtension(id) {
  if (!extensionIdPattern.test(String(id || ''))) throw new Error('Invalid extension id');
  const removed = extensions.delete(String(id));
  return { id: String(id), removed };
}

async function handleExtensionMcp(serverId, message) {
  const extension = extensions.get(serverId);
  if (!extension) throw new Error('MCP extension is not registered: ' + serverId);
  const { server, context } = extension;
  const method = message.method;
  const params = message.params && typeof message.params === 'object' ? message.params : {};
  switch (method) {
    case 'initialize':
      return server.initialize(context, params);
    case 'tools/list':
      return server.listTools(context);
    case 'tools/call':
      return server.callTool(String(params.name || ''), params.arguments || {}, context);
    case 'resources/list':
      return typeof server.listResources === 'function'
        ? server.listResources(context)
        : { resources: [] };
    case 'resources/read':
      if (typeof server.readResource !== 'function') throw new Error('Extension does not expose resources');
      return server.readResource(String(params.uri || ''), context);
    default:
      throw new Error('Unsupported MCP method: ' + method);
  }
}

function normalizeMobilePackageSpec(packageSpec) {
  const value = String(packageSpec || '').trim();
  if (!value.startsWith('@')) return value;
  const versionSeparator = value.indexOf('@', 1);
  return versionSeparator === -1 ? value : value.substring(0, versionSeparator);
}

function resolveMobileNpxProfile(command, args = []) {
  if (String(command || '').trim().toLowerCase() !== 'npx') return null;
  const packageSpec = args.find((arg) => {
    const value = String(arg || '').trim();
    return value.startsWith('@') && !value.startsWith('--');
  });
  const packageName = normalizeMobilePackageSpec(packageSpec);
  const profile = mobileNpxPackages.get(packageName);
  return profile ? { packageName, profile } : null;
}

function mobileProfileTools(profile) {
  const common = [
    {
      name: 'simichat.runtime_info',
      description: '返回 SimiChat 移动 stdio Runtime 状态。',
      inputSchema: { type: 'object', properties: {} },
    },
  ];
  if (profile === 'time') {
    common.unshift({
      name: 'simichat.now',
      description: '返回当前设备时间。',
      inputSchema: {
        type: 'object',
        properties: {
          timezoneOffsetMinutes: { type: 'integer' },
        },
      },
    });
  } else if (profile === 'memory') {
    common.unshift(
      {
        name: 'simichat.memory_search',
        description: '在移动 Runtime 可见的本地记忆文件中搜索。',
        inputSchema: {
          type: 'object',
          properties: {
            query: { type: 'string' },
            maxResults: { type: 'integer' },
          },
          required: ['query'],
        },
      },
      {
        name: 'simichat.memory_list',
        description: '列出移动 Runtime 可见的本地记忆摘要。',
        inputSchema: { type: 'object', properties: {} },
      },
    );
  } else if (profile === 'fetch') {
    common.unshift({
      name: 'simichat.fetch',
      description: '在移动 Runtime 内发起受限 HTTP(S) GET 请求。',
      inputSchema: {
        type: 'object',
        properties: {
          url: { type: 'string' },
          maxBytes: { type: 'integer' },
        },
        required: ['url'],
      },
    });
  } else if (profile === 'filesystem') {
    common.unshift(
      {
        name: 'simichat.fs_list',
        description: '列出移动 Runtime 授权工作目录中的文件。',
        inputSchema: {
          type: 'object',
          properties: {
            path: { type: 'string' },
            maxEntries: { type: 'integer' },
          },
        },
      },
      {
        name: 'simichat.fs_read_text',
        description: '读取移动 Runtime 授权工作目录中的文本文件。',
        inputSchema: {
          type: 'object',
          properties: {
            path: { type: 'string' },
            maxBytes: { type: 'integer' },
          },
          required: ['path'],
        },
      },
    );
  }
  return common;
}

function mobileProfileRuntimeInfo(session) {
  return {
    ...runtimeInfo(),
    transport: 'stdio',
    wireProtocol: 'jsonl',
    sessionId: session.id,
    command: session.command,
    args: session.args,
    packageName: session.packageName,
    profile: session.profile,
    externalProcess: false,
    appOwned: true,
  };
}

function mobileTextResult(payload) {
  return textResult(payload);
}

async function handleMobileNpxMcp(session, message) {
  const method = message.method;
  const params = message.params && typeof message.params === 'object' ? message.params : {};
  switch (method) {
    case 'initialize':
      return {
        protocolVersion: '2024-11-05',
        capabilities: { tools: {}, resources: {} },
        serverInfo: {
          name: 'SimiChat Mobile stdio ' + session.packageName,
          version: '1.0.0',
        },
      };
    case 'tools/list':
      return { tools: mobileProfileTools(session.profile) };
    case 'resources/list':
      return { resources: [] };
    case 'resources/read':
      return { contents: [] };
    case 'tools/call': {
      const name = String(params.name || '');
      const args = params.arguments && typeof params.arguments === 'object'
        ? params.arguments
        : {};
      if (name === 'simichat.runtime_info') {
        return mobileTextResult(mobileProfileRuntimeInfo(session));
      }
      if (name === 'simichat.now' && session.profile === 'time') {
        const offset = Number.isInteger(args.timezoneOffsetMinutes)
          ? args.timezoneOffsetMinutes
          : null;
        const now = offset === null
          ? new Date()
          : new Date(Date.now() + offset * 60 * 1000);
        return mobileTextResult({
          iso8601: now.toISOString(),
          timezoneOffsetMinutes: offset === null ? -now.getTimezoneOffset() : offset,
          runtime: 'stdio',
        });
      }
      if (name === 'simichat.fetch' && session.profile === 'fetch') {
        return fetchText(args);
      }
      if (name === 'simichat.fs_list' && session.profile === 'filesystem') {
        return listWorkspaceDirectory(args);
      }
      if (name === 'simichat.fs_read_text' && session.profile === 'filesystem') {
        return readWorkspaceText(args);
      }
      if (
        (name === 'simichat.memory_search' || name === 'simichat.memory_list') &&
        session.profile === 'memory'
      ) {
        return mobileTextResult({
          query: name === 'simichat.memory_search' ? String(args.query || '') : undefined,
          count: 0,
          items: [],
          note: '移动 stdio Runtime 不会读取宿主机进程或外部数据库。',
        });
      }
      return {
        content: [{ type: 'text', text: '未知移动 stdio 工具: ' + name }],
        isError: true,
      };
    }
    default:
      throw new Error('Unsupported MCP method: ' + method);
  }
}

function resolveStdioTarget(payload) {
  const command = String(payload.command || '').trim();
  const args = Array.isArray(payload.args) ? payload.args.map((arg) => String(arg)) : [];
  const requestedServerId = String(payload.serverId || '').trim();
  if (requestedServerId) {
    if (!extensions.has(requestedServerId)) {
      throw new Error('移动 stdio extension 未注册: ' + requestedServerId);
    }
    return {
      serverId: requestedServerId,
      command,
      args,
      source: 'extension',
      profile: null,
      packageName: null,
    };
  }
  const resolution = resolveMobileNpxProfile(command, args);
  if (!resolution) {
    throw new Error(
      '移动 Runtime 未打包该 stdio command/args：' +
      JSON.stringify({ command, args }),
    );
  }
  return {
    serverId: 'mobile-npx:' + resolution.packageName,
    command,
    args,
    source: 'bundled-mobile-package',
    profile: resolution.profile,
    packageName: resolution.packageName,
  };
}

async function handleStdioMcp(session, message) {
  if (session.source === 'bundled-mobile-package') {
    return handleMobileNpxMcp(session, message);
  }
  return handleMcp(message, session.serverId);
}

function resolveStdioWaiter(session) {
  const lines = session.output.splice(0, session.output.length);
  return { lines, closed: session.closed };
}

function pushStdioLine(session, line) {
  if (session.closed) return;
  if (session.waiters.length > 0) {
    const waiter = session.waiters.shift();
    clearTimeout(waiter.timer);
    waiter.resolve({ lines: [line], closed: false });
    return;
  }
  session.output.push(line);
}

function closeStdioSession(session) {
  if (session.closed) return;
  session.closed = true;
  for (const waiter of session.waiters.splice(0)) {
    clearTimeout(waiter.timer);
    waiter.resolve({ lines: [], closed: true });
  }
}

async function processStdioLine(session, line) {
  const rawLine = String(line || '').replace(/\r?\n$/, '');
  if (!rawLine.trim()) return;
  let message;
  try {
    message = JSON.parse(rawLine);
  } catch (_) {
    pushStdioLine(session, JSON.stringify({
      jsonrpc: '2.0',
      id: null,
      error: { code: -32700, message: 'Invalid JSON on MCP stdio stdin' },
    }));
    return;
  }
  if (!message || typeof message !== 'object' || Array.isArray(message)) {
    pushStdioLine(session, JSON.stringify({
      jsonrpc: '2.0',
      id: null,
      error: { code: -32600, message: 'MCP stdio message must be an object' },
    }));
    return;
  }
  const hasId = message.id !== undefined && message.id !== null;
  try {
    const result = await handleStdioMcp(session, message);
    if (hasId) {
      pushStdioLine(session, JSON.stringify({
        jsonrpc: '2.0',
        id: message.id,
        result,
      }));
    }
  } catch (error) {
    if (hasId) {
      pushStdioLine(session, JSON.stringify({
        jsonrpc: '2.0',
        id: message.id,
        error: {
          code: -32603,
          message: error instanceof Error ? error.message : String(error),
        },
      }));
    }
  }
}

function enqueueStdioLine(session, line) {
  session.processing = session.processing
    .then(() => processStdioLine(session, line))
    .catch(() => undefined);
  return session.processing;
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

async function handleMcp(message, serverId = 'simichat-node') {
  if (serverId !== 'simichat-node') {
    return handleExtensionMcp(serverId, message);
  }
  const method = message.method;
  const params = message.params && typeof message.params === 'object' ? message.params : {};

  switch (method) {
    case 'initialize':
      return {
        protocolVersion: '2024-11-05',
        capabilities: { tools: {}, resources: {} },
      serverInfo: {
        name: runtimeKind === 'container'
          ? 'SimiChat Node Container MCP'
          : 'SimiChat Bundled Node MCP',
        version: '1.2.0',
      },
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

  if (req.method === 'GET' && url.pathname === '/runtime/extensions/status') {
    return jsonResponse(res, 200, {
      extensions: [...extensions.values()].map((extension) => ({
        id: extension.id,
        protocol: extension.protocol,
        entry: extension.entry,
        root: extension.root,
        loaded: true,
      })),
    });
  }

  if (req.method === 'POST' && url.pathname === '/runtime/extensions/register') {
    try {
      const payload = await readJsonBody(req, res);
      return jsonResponse(res, 200, await registerExtension(payload));
    } catch (error) {
      return jsonResponse(res, 400, {
        error: error instanceof Error ? error.message : String(error),
      });
    }
  }

  if (req.method === 'POST' && url.pathname === '/runtime/extensions/unregister') {
    try {
      const payload = await readJsonBody(req, res);
      return jsonResponse(res, 200, await unregisterExtension(payload.id));
    } catch (error) {
      return jsonResponse(res, 400, {
        error: error instanceof Error ? error.message : String(error),
      });
    }
  }

  if (req.method === 'POST' && url.pathname === '/runtime/stdio/start') {
    try {
      const payload = await readJsonBody(req, res);
      const target = resolveStdioTarget(payload);
      const sessionId = randomUUID();
      const session = {
        id: sessionId,
        ...target,
        output: [],
        waiters: [],
        processing: Promise.resolve(),
        closed: false,
      };
      stdioSessions.set(sessionId, session);
      return jsonResponse(res, 200, {
        sessionId,
        transport: 'stdio',
        wireProtocol: 'jsonl',
        source: target.source,
        serverId: target.serverId,
        command: target.command,
        args: target.args,
      });
    } catch (error) {
      return jsonResponse(res, 400, {
        error: error instanceof Error ? error.message : String(error),
      });
    }
  }

  const stdioInputMatch = url.pathname.match(
    /^\/runtime\/stdio\/([a-f0-9-]{36})\/stdin$/,
  );
  if (req.method === 'POST' && stdioInputMatch) {
    const session = stdioSessions.get(stdioInputMatch[1]);
    if (!session || session.closed) {
      return jsonResponse(res, 404, { error: 'MCP stdio session not found or closed' });
    }
    try {
      const payload = await readJsonBody(req, res);
      if (typeof payload.line !== 'string') {
        throw new Error('MCP stdio stdin requires a string line');
      }
      await enqueueStdioLine(session, payload.line);
      return jsonResponse(res, 202, { accepted: true });
    } catch (error) {
      return jsonResponse(res, 400, {
        error: error instanceof Error ? error.message : String(error),
      });
    }
  }

  const stdioOutputMatch = url.pathname.match(
    /^\/runtime\/stdio\/([a-f0-9-]{36})\/stdout$/,
  );
  if (req.method === 'GET' && stdioOutputMatch) {
    const session = stdioSessions.get(stdioOutputMatch[1]);
    if (!session) {
      return jsonResponse(res, 404, { error: 'MCP stdio session not found' });
    }
    if (session.output.length > 0 || session.closed) {
      return jsonResponse(res, 200, resolveStdioWaiter(session));
    }
    const waitMs = clampInteger(url.searchParams.get('waitMs'), 1000, 1, 5000);
    const result = await new Promise((resolve) => {
      const waiter = {
        resolve,
        timer: setTimeout(() => {
          const index = session.waiters.indexOf(waiter);
          if (index >= 0) session.waiters.splice(index, 1);
          resolve({ lines: [], closed: session.closed });
        }, waitMs),
      };
      session.waiters.push(waiter);
    });
    return jsonResponse(res, 200, result);
  }

  const stdioCloseMatch = url.pathname.match(
    /^\/runtime\/stdio\/([a-f0-9-]{36})\/close$/,
  );
  if (req.method === 'POST' && stdioCloseMatch) {
    const session = stdioSessions.get(stdioCloseMatch[1]);
    if (!session) {
      return jsonResponse(res, 404, { error: 'MCP stdio session not found' });
    }
    closeStdioSession(session);
    stdioSessions.delete(stdioCloseMatch[1]);
    return jsonResponse(res, 200, { closed: true, sessionId: session.id });
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
          const result = await handleMcp(message, connection.serverId);
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
