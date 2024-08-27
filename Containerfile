ARG DRIVER_TOOLKIT_IMAGE="quay.io/smgglrs-ai/driver-toolkit:latest"
ARG BASE_IMAGE="quay.io/fedora/fedora-bootc:40"

FROM ${DRIVER_TOOLKIT_IMAGE} AS builder

USER root

RUN export DISTRO=$(grep '^ID=' /etc/os-release | cut -d '=' -f 2 | sed 's/"//g') \
    && export BUILD_ARCH=$(arch) \
    && export TARGET_ARCH=$(echo "${BUILD_ARCH}" | sed 's/+64k//') \
    && cp /tmp/repos.d/${DISTRO}/${TARGET_ARCH}/*.repo /etc/yum.repos.d/ \
    && cp /tmp/repos.d/${DISTRO}/${TARGET_ARCH}/RPM-GPG-KEY-AMD-ROCM /etc/pki/rpm-gpg/RPM-GPG-KEY-AMD-ROCM \
    && rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-AMD-ROCM \
    && dnf install -y amdgpu-dkms \
    && dnf clean all

FROM ${BASE_IMAGE}

COPY build/usr /usr

RUN --mount=type=bind,from=builder,source=/,destination=/tmp/builder,ro \
    export KERNEL_VERSION=$(rpm -q --qf '%{VERSION}-%{RELEASE}.%{ARCH}' kernel-core) \
    && rm -f /lib/modules/${KERNEL_VERSION}/kernel/drivers/gpu/drm/amd/amdgpu/amdgpu.ko.xz \
    && cp -r /tmp/builder/lib/modules/${KERNEL_VERSION}/extra /lib/modules/${KERNEL_VERSION}/extra \
    && cp -r /tmp/builder/lib/firmware/updates/amdgpu /lib/firmware/amdgpu \
    && depmod ${KERNEL_VERSION}

RUN export DISTRO=$(grep '^ID=' /etc/os-release | cut -d '=' -f 2 | sed 's/"//g') \
    && export BUILD_ARCH=$(arch) \
    && export TARGET_ARCH=$(echo "${BUILD_ARCH}" | sed 's/+64k//') \
    && cp /tmp/repos.d/${DISTRO}/${TARGET_ARCH}/*.repo /etc/yum.repos.d/ \
    && cp /tmp/repos.d/${DISTRO}/${TARGET_ARCH}/RPM-GPG-KEY-AMD-ROCM /etc/pki/rpm-gpg/RPM-GPG-KEY-AMD-ROCM \
    && rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-AMD-ROCM \
    && mv /etc/selinux /etc/selinux.tmp \ 
    && dnf update -y --exclude=kernel* \
    && dnf install -y \
        amd-smi \
        cloud-init \
        pciutils \
        rsync \
        skopeo \
        tmux \
    && dnf clean all \
    && mv /etc/selinux.tmp /etc/selinux \
    && ln -s ../cloud-init.target /usr/lib/systemd/system/default.target.wants

ARG SSHPUBKEY

# The --build-arg "SSHPUBKEY=$(cat ~/.ssh/id_rsa.pub)" option inserts your
# public key into the image, allowing root access via ssh.
RUN if [ -n "${SSHPUBKEY}" ]; then \
    set -eu; mkdir -p /usr/ssh && \
        echo 'AuthorizedKeysFile /usr/ssh/%u.keys .ssh/authorized_keys .ssh/authorized_keys2' >> /etc/ssh/sshd_config.d/30-auth-system.conf && \
            echo ${SSHPUBKEY} > /usr/ssh/root.keys && chmod 0600 /usr/ssh/root.keys; \
fi

# Setup /usr/lib/containers/storage as an additional store for images.
# Remove once the base images have this set by default.
RUN grep -q /usr/lib/containers/storage /etc/containers/storage.conf || \
    sed -i -e '/additionalimage.*/a "/usr/lib/containers/storage",' \
        /etc/containers/storage.conf

# Added for running as an OCI Container to prevent Overlay on Overlay issues.
VOLUME /var/lib/containers

LABEL description="Bootc for AMD ROCm provides a container runtime for AMD ROCm accelerated workloads" \
      name="bootc-amd-rocm" \
      org.opencontainers.image.name="bootc-amd-rocm" \
      vcs-ref="${VCS_REF}"
