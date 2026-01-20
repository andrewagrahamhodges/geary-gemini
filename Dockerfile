# Geary-Gemini Build Environment
# Build Geary from source and produce a .deb package
#
# Usage:
#   docker-compose run --rm build        # Build the application
#   docker-compose run --rm package      # Build .deb package
#   docker-compose run --rm test         # Run tests
#   docker-compose run --rm shell        # Interactive shell

FROM ubuntu:25.10

LABEL maintainer="Andrew Hodges"
LABEL description="Geary-Gemini build environment with all dependencies"

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC

# Install build dependencies (from BUILDING.md for Ubuntu/Debian)
RUN apt-get update && apt-get install -y \
    # Build essentials (meson installed via pip for newer version)
    ninja-build \
    python3-pip \
    pipx \
    build-essential \
    valac \
    valadoc \
    # Desktop/i18n tools
    desktop-file-utils \
    iso-codes \
    gettext \
    itstool \
    # Core libraries
    libenchant-2-dev \
    libfolks-dev \
    libgcr-3-dev \
    libgcr-4-dev \
    libgck-2-dev \
    libgee-0.8-dev \
    libglib2.0-dev \
    libgmime-3.0-dev \
    libgoa-1.0-dev \
    libgspell-1-dev \
    libgsound-dev \
    libgtk-3-dev \
    libjson-glib-dev \
    libhandy-1-dev \
    libicu-dev \
    libpeas-dev \
    libpeas-2-dev \
    gir1.2-peas-2 \
    libsecret-1-dev \
    libsqlite3-dev \
    libstemmer-dev \
    libunwind-dev \
    libwebkit2gtk-4.1-dev \
    libxml2-dev \
    libytnef0-dev \
    # Ubuntu Messaging Menu (optional)
    libmessaging-menu-dev \
    # Debian packaging tools
    dpkg-dev \
    debhelper \
    devscripts \
    dh-make \
    fakeroot \
    lintian \
    # Utilities
    git \
    curl \
    wget \
    file \
    && rm -rf /var/lib/apt/lists/*

# Install Meson 1.8.x via pip (Ubuntu 24.04 ships with 1.3.2, Geary needs >= 1.7)
# Note: Meson 1.10.0 has a DirectoryLock bug, so we pin to 1.8.x
RUN pip3 install --break-system-packages "meson>=1.7,<1.10"

# Create build user (avoid running as root)
RUN useradd -m -s /bin/bash builder
RUN mkdir -p /src /build /output && chown -R builder:builder /src /build /output

# Set working directory
WORKDIR /src

# Source is mounted at runtime via docker-compose volume, not copied
# This ensures fresh source code every build with no Docker layer caching

USER builder

# Default command
CMD ["bash"]
