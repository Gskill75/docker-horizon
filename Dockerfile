FROM ubuntu:24.04@sha256:4fdf0125919d24aec972544669dcd7d6a26a8ad7e6561c73d5549bd6db258ac2 AS base

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends ubuntu-cloud-keyring
COPY <<EOF /etc/apt/sources.list.d/cloudarchive.list
deb http://ubuntu-cloud.archive.canonical.com/ubuntu noble-updates/flamingo main
EOF
FROM base AS python-base

ENV PATH=/var/lib/openstack/bin:$PATH
RUN \
    apt-get update -qq && \
    apt-get install -qq -y --no-install-recommends \
        ca-certificates \
        libpython3.12 \
        lsb-release \
        libpcre3 \
        python3-setuptools \
        curl \
        sudo && \
    apt-get clean && \
    rm -rf '/var/lib/apt/lists/*'
FROM python-base AS venv-openstack 

RUN curl -L -o /upper-constraints.txt https://opendev.org/openstack/requirements/raw/branch/stable/2025.2/upper-constraints.txt
RUN \
    apt-get update -qq && \
    apt-get install -qq -y --no-install-recommends \
        build-essential \
        git \
        libldap2-dev \
        libpcre3-dev \
        libsasl2-dev \
        libssl-dev \
        lsb-release \
        openssh-client \
        python3 \
        python3-dev && \
    apt-get clean && \
    rm -rf '/var/lib/apt/lists/*'
COPY --from=ghcr.io/astral-sh/uv:latest@sha256:15f68a476b768083505fe1dbfcc998344d0135f0ca1b8465c4760b323904f05a /uv /uvx /bin/
RUN <<EOF bash -xe
uv venv --system-site-packages /var/lib/openstack
uv pip install \
    --constraint /upper-constraints.txt \
        confluent-kafka \
        cryptography \
        pymysql \
        python-binary-memcached \
        python-memcached \
        uwsgi
EOF
FROM docker.io/alpine/git:latest@sha256:d86f367afb53d022acc4377741e7334bc20add161bb10234272b91b459b4b7d8 AS sources

RUN set -eux; \
    git clone --branch stable/2025.2 --depth 1 --single-branch https://opendev.org/openstack/horizon.git /horizon; \
    git clone --branch stable/2025.2 --depth 1 --single-branch https://opendev.org/openstack/heat-dashboard.git /heat-dashboard; \
    git clone --branch stable/2025.2 --depth 1 --single-branch https://opendev.org/openstack/designate-dashboard.git /designate-dashboard; \
    git clone --branch stable/2025.2 --depth 1 --single-branch https://opendev.org/openstack/ironic-ui.git /ironic-ui; \
    git clone --branch stable/2025.2 --depth 1 --single-branch https://opendev.org/openstack/magnum-ui.git /magnum-ui; \
    git clone --branch stable/2025.2 --depth 1 --single-branch https://opendev.org/openstack/neutron-fwaas-dashboard.git /neutron-fwaas-dashboard; \
    git clone --branch stable/2025.2 --depth 1 --single-branch https://opendev.org/openstack/neutron-vpnaas-dashboard.git /neutron-vpnaas-dashboard; \
    git clone --branch stable/2025.2 --depth 1 --single-branch https://opendev.org/openstack/octavia-dashboard.git /octavia-dashboard; \
    git clone --branch stable/2025.2 --depth 1 --single-branch https://opendev.org/openstack/masakari-dashboard.git /masakari-dashboard
FROM venv-openstack AS horizon-build

COPY --from=sources /horizon /horizon
COPY --from=sources /heat-dashboard /heat-dashboard
COPY --from=sources /designate-dashboard /designate-dashboard
COPY --from=sources /ironic-ui /ironic-ui
COPY --from=sources /magnum-ui /magnum-ui
COPY --from=sources /neutron-fwaas-dashboard /neutron-fwaas-dashboard
COPY --from=sources /neutron-vpnaas-dashboard /neutron-vpnaas-dashboard
COPY --from=sources /octavia-dashboard /octavia-dashboard
COPY --from=sources /masakari-dashboard /masakari-dashboard

RUN <<EOF bash -xe
uv pip install \
  --constraint /upper-constraints.txt \
  /horizon \
  /heat-dashboard \
  /designate-dashboard \
  /ironic-ui \
  /magnum-ui \
  /neutron-fwaas-dashboard \
  /neutron-vpnaas-dashboard \
  /octavia-dashboard \
  /masakari-dashboard \
  pymemcache
EOF

FROM python-base
RUN \
    groupadd -g 42424 horizon && \
    useradd -u 42424 -g 42424 -M -d /var/lib/horizon -s /usr/sbin/nologin -c "Horizon User" horizon && \
    mkdir -p /etc/horizon /var/log/horizon /var/lib/horizon /var/cache/horizon && \
    chown -Rv horizon:horizon /etc/horizon /var/log/horizon /var/lib/horizon /var/cache/horizon
RUN <<EOF bash -xe
apt-get update -qq
apt-get install -qq -y --no-install-recommends \
    apache2 gettext libapache2-mod-wsgi-py3
apt-get clean
rm -rf /var/lib/apt/lists/*
EOF
COPY --from=horizon-build --link /var/lib/openstack /var/lib/openstack

