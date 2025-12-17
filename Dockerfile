# Multi-stage build for VerneMQ production container
# Stage 1: Build stage with Erlang/OTP and build tools
FROM erlang:26.2-slim as builder

# Install build dependencies
RUN apt-get update && apt-get install -y \
    git \
    make \
    gcc \
    g++ \
    libc6-dev \
    libssl-dev \
    libncurses-dev \
    libatomic1 \
    libsnappy-dev \
    wget \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /build

# Download and install rebar3
RUN wget https://github.com/erlang/rebar3/releases/download/3.23.0/rebar3 && \
    chmod +x rebar3 && \
    mv rebar3 /usr/local/bin/

# Copy necessary files for building
COPY rebar.config rebar.lock ./
COPY Makefile ./
COPY vars.config ./
COPY files/ ./files/
COPY apps/ ./apps/
COPY 3rd-party-licenses.txt ./

# Get git version for build
RUN git describe --tags --always || echo "no-git-version"

# Build the release using rebar3
RUN rebar3 release

# Stage 2: Minimal runtime stage
FROM erlang:26.2-slim as runtime

# Create vernemq user and group
RUN groupadd -r vernemq && useradd -r -g vernemq vernemq

# Install minimal runtime dependencies
RUN apt-get update && apt-get install -y \
    libatomic1 \
    libncurses6 \
    libssl3 \
    libsnappy1v5 \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

# Set working directory
WORKDIR /opt/vernemq

# Copy the built release from builder stage
COPY --from=builder /build/_build/default/rel/vernemq/ /opt/vernemq/

# Create necessary directories
RUN mkdir -p /opt/vernemq/data/broker \
    /opt/vernemq/data/msgstore \
    /opt/vernemq/log/sasl \
    /opt/vernemq/etc/conf.d \
    && chown -R vernemq:vernemq /opt/vernemq

# Switch to non-root user
USER vernemq

# Set environment variables
ENV HOME=/opt/vernemq \
    PATH=/opt/vernemq/bin:$PATH \
    RELEASE_ROOT_DIR=/opt/vernemq \
    VERNEMQ_PATH=/opt/vernemq

# Expose ports
EXPOSE 1883 8883 8080 8083 44053 8888

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD /opt/vernemq/bin/vmq-admin cluster status || exit 1

# Use the vernemq runner script as entrypoint
ENTRYPOINT ["/opt/vernemq/bin/vernemq"]