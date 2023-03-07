FROM debian:bullseye-slim

# Ref https://github.com/openresty/docker-openresty/blob/master/alpine/Dockerfile
ARG OPENRESTY_CONFIG_OPTIONS="\
	--with-http_ssl_module \
	--with-http_realip_module \
	--with-http_addition_module \
	--with-http_sub_module \
	--with-http_dav_module \
	--with-http_flv_module \
	--with-http_mp4_module \
	--with-http_gunzip_module \
	--with-http_gzip_static_module \
	--with-http_random_index_module \
	--with-http_secure_link_module \
	--with-http_stub_status_module \
	--with-http_auth_request_module \
	--with-http_xslt_module=dynamic \
	--with-http_image_filter_module=dynamic \
	--with-http_geoip_module=dynamic \
	--with-http_perl_module=dynamic \
	--with-threads \
	--with-stream \
	--with-stream_ssl_module \
	--with-stream_ssl_preread_module \
	--with-stream_realip_module \
	--with-stream_geoip_module=dynamic \
	--with-http_slice_module \
	--with-mail \
	--with-mail_ssl_module \
	--with-compat \
	--with-file-aio \
	--with-http_v2_module \
        --with-pcre-jit \
        --with-openssl=/usr/local/src/openssl \
        --add-dynamic-module=./ngx_brotli \
    "

# Set environment
ENV OPENRESTY_VERSION=1.21.4.1 \
    OPENRESTY_PREFIX=/usr/local/openresty \
    LUAROCKS_VERSION=3.9.2 \
    LAPIS_VERSION=1.13.1
ENV PATH=${OPENRESTY_PREFIX}/bin:${OPENRESTY_PREFIX}/nginx/sbin:${PATH}

# Set Persistent Deps
ENV BUILD_DEPS \
        build-essential \
        git-core \
        unzip \
        m4 \
        wget

# Install depandency packages
RUN set -xe && \
        # create nginx user/group first, to be consistent throughout docker variants
        addgroup --system --gid 101 nginx \
        && adduser --system --disabled-login --ingroup nginx --no-create-home --home /nonexistent --gecos "nginx user" --shell /bin/false --uid 101 nginx \
        && \
        apt-get update -y && apt-get install -y --no-install-recommends --no-install-suggests \
            ${BUILD_DEPS} \
            ca-certificates \
            libpcre3-dev \
            #libssl-dev \
            zlib1g-dev \
            libxslt1-dev \
            libgd-dev \
            libgeoip-dev \
            libperl-dev \
        && \
	# Install OpenSSL
	# Source from https://github.com/openssl/openssl/releases/download/openssl-3.0.8/openssl-3.0.8.tar.gz
        pushd ${BUILDDIR} \
        && curl -sL -O https://github.com/openssl/openssl/releases/download/openssl-3.0.8/openssl-3.0.8.tar.gz \
        && tar zxvf openssl-3.0.8.tar.gz \
        && cp -r openssl-3.0.8 /usr/local/src/openssl \
        && cd /usr/local/src/openssl \
        && ./config --prefix=/usr/local/openssl \
        && make && make install \
	&& popd && \
        # Install OpenResty
        wget https://openresty.org/download/openresty-${OPENRESTY_VERSION}.tar.gz && \
        tar xf openresty-${OPENRESTY_VERSION}.tar.gz && rm -f openresty-${OPENRESTY_VERSION}.tar.gz && \
        cd openresty-${OPENRESTY_VERSION} && \
        wget https://github.com/google/ngx_brotli/archive/refs/heads/master.tar.gz && \
        tar xf master.tar.gz && rm -f master.tar.gz && \
        mv ngx_brotli-master ngx_brotli && \
        ./configure \
            ${OPENRESTY_CONFIG_OPTIONS} \
        && \
        make -j $(getconf _NPROCESSORS_ONLN) && make install && \
        cd / && rm -rf openresty-${OPENRESTY_VERSION} && \
        # Create link
        [ -e /usr/local/bin/luajit ] || ln -sf /usr/local/openresty/luajit/bin/luajit /usr/local/bin/luajit && \
        # Install LuaRocks
        wget https://luarocks.org/releases/luarocks-${LUAROCKS_VERSION}.tar.gz && \
        tar zxf luarocks-${LUAROCKS_VERSION}.tar.gz && rm -f luarocks-${LUAROCKS_VERSION}.tar.gz && \
        cd luarocks-${LUAROCKS_VERSION} && \
        ./configure \
            --with-lua=${OPENRESTY_PREFIX}/luajit \
            --with-lua-include=${OPENRESTY_PREFIX}/luajit/include/luajit-2.1 \
            --with-lua-lib=${OPENRESTY_PREFIX}/lualib \
        && \
        make -j $(getconf _NPROCESSORS_ONLN) build && make install && \
        cd / && rm -rf luarocks-${LUAROCKS_VERSION} && \
        # Install Lapis
        luarocks install cqueues && \
        luarocks install http && \
        luarocks install lapis ${LAPIS_VERSION} && \
        luarocks install moonscript \
        && mkdir -p /var/run/openresty \
        && ln -sf /dev/stdout /usr/local/openresty/nginx/logs/access.log \
        && ln -sf /dev/stderr /usr/local/openresty/nginx/logs/error.log \
        # Remove build deps
        && \
        apt-get remove --purge -y ${BUILD_DEPS} && apt-get autoremove --purge -y && rm -r /var/lib/apt/lists/*

EXPOSE 80

# Use SIGQUIT instead of default SIGTERM to cleanly drain requests
# See https://github.com/openresty/docker-openresty/blob/master/README.md#tips--pitfalls
STOPSIGNAL SIGQUIT

CMD ["openresty", "-g", "daemon off;"]
