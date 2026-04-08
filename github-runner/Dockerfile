FROM myoung34/github-runner:latest

# Install 1Password CLI for secret injection in deploy.sh
RUN curl -sS https://downloads.1password.com/linux/keys/1password.asc | \
    gpg --dearmor > /usr/share/keyrings/1password-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/1password-archive-keyring.gpg] https://downloads.1password.com/linux/debian/$(dpkg --print-architecture) stable main" | \
    tee /etc/apt/sources.list.d/1password.list && \
    apt-get update && \
    apt-get install -y 1password-cli && \
    rm -rf /var/lib/apt/lists/*
