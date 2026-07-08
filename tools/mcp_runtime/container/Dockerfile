ARG SIMICHAT_MCP_RUNTIME_BASE_IMAGE=node:22-alpine
FROM ${SIMICHAT_MCP_RUNTIME_BASE_IMAGE}

ENV NODE_ENV=production \
    MCP_RUNTIME_HOST=0.0.0.0 \
    MCP_RUNTIME_PORT=37651

USER root
WORKDIR /opt/simichat-mcp-runtime
COPY package.json runtime-server.mjs ./
RUN chown -R node:node /opt/simichat-mcp-runtime

USER node
EXPOSE 37651
ENTRYPOINT []
CMD ["node", "runtime-server.mjs"]
