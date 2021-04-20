# Newest version now supports multi-arch builds.
# FROM jwilder/nginx-proxy:latest

# Testing specific PR of NGINX_PROXY_VERSION w/ branch for supporting path based routing
FROM arm32v7/nginx 

LABEL maintainer="Paulo Truta paulo@edgebox.io"

# Install wget and install/updates certificates
RUN apt-get update \
 && apt-get install -y -q --no-install-recommends \
    ca-certificates \
    wget \
    git \
 && apt-get clean \
 && rm -r /var/lib/apt/lists/*


# Configure Nginx and apply fix for very long server names
RUN echo "daemon off;" >> /etc/nginx/nginx.conf \
 && sed -i 's/^http {/&\n    server_names_hash_bucket_size 128;/g' /etc/nginx/nginx.conf


# Install Forego
RUN wget https://bin.equinox.io/c/ekMN3bCZFUn/forego-stable-linux-arm.tgz \
 && tar xvf forego-stable-linux-arm.tgz -C /usr/local/bin \
 && rm forego-stable-linux-arm.tgz

# Install docker-gen
# RUN wget https://github.com/jwilder/docker-gen/releases/download/0.7.4/docker-gen-linux-armhf-0.7.4.tar.gz \
#  && tar -C /usr/local/bin -xvzf docker-gen-linux-armhf-0.7.4.tar.gz \
#  && rm docker-gen-linux-armhf-0.7.4.tar.gz

# Install custom build of docker-gen
COPY ./docker-gen /usr/local/bin/docker-gen

ENV NGINX_PROXY_VERSION "main"
RUN git clone --branch ${NGINX_PROXY_VERSION} https://github.com/AlexanderLieret/nginx-proxy /app

WORKDIR /app/

ENV DOCKER_HOST unix:///tmp/docker.sock

VOLUME ["/etc/nginx/certs", "/etc/nginx/dhparam"]

ENTRYPOINT ["/app/docker-entrypoint.sh"]
CMD ["forego", "start", "-r"]
