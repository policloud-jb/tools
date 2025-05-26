FROM debian:12.9

# Install any dependencies your script needs
RUN apt-get update && apt-get install -y \
    bash \
    curl \
    wget \
    # add other packages as needed
    && rm -rf /var/lib/apt/lists/*

# Copy your script
COPY setup-controller.sh /app/
WORKDIR /app

# Make it executable
RUN chmod +x setup-controller.sh

# Default command
CMD ["./setup-controller.sh"]
