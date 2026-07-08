# SimiChat MCP Runtime Container

PC 端 Node MCP 容器侧车。容器内自带 Node runtime，App 通过 MCP SSE 连接，避免依赖宿主机 `node` / `npm` / `npx`。默认基镜像为 `node:22-alpine`，也可用 `SIMICHAT_MCP_RUNTIME_BASE_IMAGE` 指向企业镜像源或已预拉取的 Node 镜像。

默认端点：

- Health: `http://127.0.0.1:37651/health`
- MCP SSE: `http://127.0.0.1:37651/mcp/sse/simichat-node`

启动：

```bash
scripts/mcp_runtime_container.sh start
```

完整本地自检（启动容器、访问 `/health`、建立 MCP SSE、调用 `tools/list` 与 `simichat.echo`）：

```bash
scripts/mcp_runtime_container.sh smoke
```

如果 Docker Hub 暂时不可用，可以显式指定已预拉取且包含 Node 的基镜像：

```bash
SIMICHAT_MCP_RUNTIME_BASE_IMAGE=<node-base-image> scripts/mcp_runtime_container.sh smoke
```

内建工具：

- `simichat.node_runtime_info`：容器 Runtime 状态。
- `simichat.echo`：回显验证。
- `simichat.fs_list` / `simichat.fs_read_text`：只访问 `MCP_RUNTIME_WORKSPACE_ROOT` 内的授权工作目录，默认是容器工作目录。
- `simichat.fetch_text`：容器内只读 HTTP(S) GET 文本抓取，避免依赖宿主机 npx fetch。

权限环境变量：

- `MCP_RUNTIME_WORKSPACE_ROOT`：授权文件工作目录。
- `MCP_RUNTIME_MAX_TEXT_BYTES`：单次文本读取 / 抓取最大字节数，默认 65536。
