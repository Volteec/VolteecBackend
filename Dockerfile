# ================================
# Build image
# ================================
FROM swift:6.2-noble AS build

# Install build dependencies
RUN export DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true \
    && apt-get -q update \
    && apt-get -q install -y --no-install-recommends \
      libjemalloc-dev \
    && rm -r /var/lib/apt/lists/*

# Set up a build area
WORKDIR /build

# First just resolve dependencies.
# This creates a cached layer that can be reused
# as long as your Package.swift/Package.resolved
# files do not change.
COPY ./Package.* ./
RUN swift package resolve \
        $([ -f ./Package.resolved ] && echo "--force-resolved-versions" || true)

# Copy entire repo into container
COPY . .

RUN mkdir /staging

# Build metadata (override in CI)
ARG BACKEND_SOFTWARE_VERSION=1.1.0
ARG BACKEND_PROTOCOL_VERSION=1.1
ARG BACKEND_COMMIT=unknown
ARG BACKEND_BUILD_DATE=unknown

# Write build metadata into Sources before compilation
RUN cat > /build/Sources/VolteecBackend/BuildInfo.swift <<EOF
import Foundation

enum BuildInfo {
    static let softwareVersion = "${BACKEND_SOFTWARE_VERSION}"
    static let protocolVersion = "${BACKEND_PROTOCOL_VERSION}"
    static let commit = "${BACKEND_COMMIT}"
    static let buildDate = "${BACKEND_BUILD_DATE}"
}
EOF

# Build the application, with optimizations, with static linking, and using jemalloc
# N.B.: The static version of jemalloc is incompatible with the static Swift runtime.
RUN --mount=type=cache,target=/build/.build \
    swift build -c release \
        --product VolteecBackend \
        --static-swift-stdlib \
        -Xlinker -ljemalloc && \
    # Copy main executable to staging area
    cp "$(swift build -c release --show-bin-path)/VolteecBackend" /staging && \
    # Copy resources bundled by SPM to staging area
    find -L "$(swift build -c release --show-bin-path)" -regex '.*\.resources$' -exec cp -Ra {} /staging \;


# Switch to the staging area
WORKDIR /staging

# Copy static swift backtracer binary to staging area
RUN cp "/usr/libexec/swift/linux/swift-backtrace-static" ./

# Copy any resources from the public directory and views directory if the directories exist
# Ensure that by default, neither the directory nor any of its contents are writable.
RUN [ -d /build/Public ] && { mv /build/Public ./Public && chmod -R a-w ./Public; } || true
RUN [ -d /build/Resources ] && { mv /build/Resources ./Resources && chmod -R a-w ./Resources; } || true

# ================================
# Run image
# ================================
FROM ubuntu:noble

# Install runtime dependencies
RUN export DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true \
    && apt-get -q update \
    && apt-get -q install -y --no-install-recommends \
      libjemalloc2 \
      ca-certificates \
      tzdata \
      curl \
# If your app or its dependencies import FoundationNetworking, also install `libcurl4`.
      # libcurl4 \
# If your app or its dependencies import FoundationXML, also install `libxml2`.
      # libxml2 \
    && rm -r /var/lib/apt/lists/*

# Create a vapor user and group with /app as its home directory
RUN useradd --user-group --create-home --system --skel /dev/null --home-dir /app vapor

# Switch to the new home directory
WORKDIR /app

# Copy built executable and any staged resources from builder
COPY --from=build --chown=vapor:vapor /staging /app

# Provide configuration needed by the built-in crash reporter and some sensible default behaviors.
ENV SWIFT_BACKTRACE=enable=yes,sanitize=yes,threads=all,images=all,interactive=no,swift-backtrace=./swift-backtrace-static

# Ensure all further commands run as the vapor user
USER vapor:vapor

# Let Docker bind to port 8080
EXPOSE 8080

# Healthcheck for container orchestration
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD curl -f http://localhost:8080/health || exit 1

# Start the Vapor service when the image is run, default to listening on 8080 in production environment
ENTRYPOINT ["./VolteecBackend"]
CMD ["serve", "--env", "production", "--hostname", "0.0.0.0", "--port", "8080"]
