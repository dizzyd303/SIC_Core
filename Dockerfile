#===============================================================================
# Dockerfile — SIC Platform (Scarface Intelligence Core)
# Version: 1.3.0
# Multi-stage build: pre-pull models in builder, ship minimal runtime
#
# Build:
#   docker build -t sic-platform:latest .
#
# Run:
#   docker run -it --rm -v sic-models:/root/.ollama sic-platform:latest \
#     SIC_Security.sh "recon example.com"
#
#   With Visa compliance:
#   docker run -it --rm -e VISA_MODE=1 -e H1_USERNAME=your_handle \
#     -v sic-models:/root/.ollama sic-platform:latest \
#     SIC_Security.sh "scan visa.com"
#
#   Cloud security audit:
#   docker run -it --rm -e CLOUD_PROVIDER=aws \
#     -v ~/.aws:/root/.aws:ro \
#     -v sic-models:/root/.ollama sic-platform:latest \
#     SIC_Cloud_Security.sh "audit AWS production"
#
#   Market analysis:
#   docker run -it --rm -v sic-models:/root/.ollama sic-platform:latest \
#     SIC_Stocks.sh "analyze AAPL"
#===============================================================================

# ── Stage 1: Builder — install tools + pre-pull models ──
FROM ollama/ollama:latest AS builder

# Install build tools
RUN apt-get update -qq && apt-get install -y -qq \
    nmap whatweb curl wget whois dnsutils \
    python3 python3-pip \
    git ca-certificates unzip \
    && rm -rf /var/lib/apt/lists/*

# Install nuclei (Go binary)
RUN curl -sL "https://github.com/projectdiscovery/nuclei/releases/latest/download/nuclei_linux_amd64.zip" \
    -o /tmp/nuclei.zip && \
    unzip -q /tmp/nuclei.zip -d /usr/local/bin/ && \
    rm /tmp/nuclei.zip && \
    chmod +x /usr/local/bin/nuclei

# Install ffuf
RUN curl -sL "https://github.com/ffuf/ffuf/releases/latest/download/ffuf_linux_amd64.tar.gz" \
    -o /tmp/ffuf.tar.gz && \
    tar -xzf /tmp/ffuf.tar.gz -C /usr/local/bin/ ffuf && \
    rm /tmp/ffuf.tar.gz

# Install testssl.sh
RUN git clone --depth 1 https://github.com/drwetter/testssl.sh.git /opt/testssl && \
    ln -s /opt/testssl/testssl.sh /usr/local/bin/testssl

# Install Python deps for SIC_Stocks
RUN pip3 install --quiet --break-system-packages yfinance pandas numpy 2>/dev/null || \
    pip3 install --quiet yfinance pandas numpy

# Pre-pull default Ollama models
# Override at build time: docker build --build-arg MODELS="model1 model2" .
ARG MODELS="huihui_ai/Hermes-3-Llama-3.2-abliterated:3b stable-code:latest sec-coder:latest paramhshah19gpt/claudecode1:latest smollm:1.7b"

RUN ollama serve & \
    SERVER_PID=$!; \
    sleep 3; \
    for model in $MODELS; do \
        echo "Pulling $model..."; \
        ollama pull "$model" || echo "Warning: failed to pull $model"; \
    done; \
    kill $SERVER_PID 2>/dev/null; \
    wait $SERVER_PID 2>/dev/null; \
    echo "Model pre-pull complete"

# ── Stage 2: Runtime ──
FROM ollama/ollama:latest

# Install runtime tools
RUN apt-get update -qq && apt-get install -y -qq \
    nmap whatweb curl wget whois dnsutils \
    python3 python3-pip \
    ca-certificates jq \
    && rm -rf /var/lib/apt/lists/*

# Install Python deps for SIC_Stocks in runtime image
RUN pip3 install --quiet --break-system-packages yfinance pandas numpy 2>/dev/null || \
    pip3 install --quiet yfinance pandas numpy

# Copy binaries from builder
COPY --from=builder /usr/local/bin/nuclei  /usr/local/bin/
COPY --from=builder /usr/local/bin/ffuf    /usr/local/bin/
COPY --from=builder /usr/local/bin/testssl /usr/local/bin/
COPY --from=builder /opt/testssl           /opt/testssl

# Copy pre-pulled models
COPY --from=builder /root/.ollama /root/.ollama

# Copy SIC platform — core lib (read-only) + all module scripts (executable)
COPY sic_core.sh          /usr/local/lib/sic_core.sh
COPY rapidapi_helper.sh   /usr/local/lib/rapidapi_helper.sh
COPY SIC_Security.sh      /usr/local/bin/
COPY SIC_Skip.sh          /usr/local/bin/
COPY SIC_Diagnostics.sh   /usr/local/bin/
COPY SIC_COPE.sh          /usr/local/bin/
COPY SIC_Cloud_Security.sh /usr/local/bin/
COPY SIC_Stocks.sh        /usr/local/bin/

# FIX v1.3.0: sic_core.sh is a library (644), modules are executables (755)
RUN chmod 644 /usr/local/lib/sic_core.sh /usr/local/lib/rapidapi_helper.sh && \
    chmod 755 /usr/local/bin/SIC_*.sh

# Copy entrypoint
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 11434

ENTRYPOINT ["/entrypoint.sh"]
CMD ["SIC_Security.sh"]
