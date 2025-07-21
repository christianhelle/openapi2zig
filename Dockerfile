# Use a minimal base image
FROM alpine:latest

# Install necessary runtime dependencies
RUN apk add --no-cache \
    ca-certificates \
    curl

# Create a non-root user
RUN addgroup -g 1001 -S openapi2zig && \
    adduser -S -D -H -u 1001 -s /sbin/nologin openapi2zig -G openapi2zig

# Copy the binary from the build artifacts
COPY artifacts/openapi2zig /usr/local/bin/openapi2zig

# Make the binary executable
RUN chmod +x /usr/local/bin/openapi2zig

# Switch to non-root user
USER openapi2zig

# Set the working directory
WORKDIR /app

# Expose a port if needed (adjust based on your application)
# EXPOSE 8080

# Set the entrypoint
ENTRYPOINT ["/usr/local/bin/openapi2zig"]

# Default command
CMD ["--help"]
