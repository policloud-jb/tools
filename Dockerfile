FROM debian:12.9

# Install basic dependencies for testing
RUN apt-get update && apt-get install -y \
    sudo \
    curl \
    wget \
    git \
    systemd \
    openssh-client \
    && rm -rf /var/lib/apt/lists/*

# Create a working directory
WORKDIR /test

# Copy the setup script
COPY setup-system.sh /test/
RUN chmod +x /test/setup-system.sh

# Default command to run the script with test parameters
CMD ["./setup-system.sh", \
     "--ops-user", "ops", \
     "--github-user", "policloud-ops", \
     "--git-user", "ops", \
     "--git-email", "ops@policloud.com", \
     "--repo", "tools"]
