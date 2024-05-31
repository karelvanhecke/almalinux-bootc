# This container build uses some special features of podman that allow
# a process executing as part of a container build to generate a new container
# image "from scratch".
#
# This container build uses nested containerization, so you must build with e.g.
# podman build --security-opt=label=disable --cap-add=all --device /dev/fuse <...>
#
# # Why are we doing this?
#
# Today this base image build process uses rpm-ostree.  There is a lot of things that
# rpm-ostree does when generating a container image...but important parts include:
#
# - auto-updating labels in the container metadata
# - Generating "chunked" content-addressed reproducible image layers (notice
#   how there are ~60 layers in the generated image)
#
# The latter bit in particular is currently impossible to do from Containerfile.
# A future goal is adding some support for this in a way that can be honored by
# buildah (xref https://github.com/containers/podman/discussions/12605)
#
# # Why does this build process require additional privileges?
#
# Because it's generating a base image and uses containerbuildcontextization features itself.
# In the future some of this can be lifted.
FROM docker.io/almalinux:9@sha256:8d722e4cd4c754f1a72364424502d3f3bd63c36aba575fb7039dab26f30ed8b7 as repos

FROM quay.io/centos-bootc/bootc-image-builder@sha256:f94b033c74261cf076d8e4824ef1efe229818f6a37afe9d6247e382ffa4b46a7 as builder
ARG MANIFEST=almalinux-bootc.yaml
COPY --from=repos /etc/dnf/vars /etc/dnf/vars
COPY --from=repos /etc/pki/rpm-gpg/RPM-GPG-KEY-AlmaLinux-* /etc/pki/rpm-gpg
COPY . /src
WORKDIR /src
RUN rm -vf /src/*.repo
COPY --from=repos /etc/yum.repos.d/*.repo /src
RUN --mount=type=cache,target=/workdir --mount=type=bind,rw=true,src=.,dst=/buildcontext,bind-propagation=shared rpm-ostree compose image \
 --image-config almalinux-bootc-config.json --cachedir=/workdir --format=ociarchive --initialize ${MANIFEST} /buildcontext/out.ociarchive

FROM oci-archive:./out.ociarchive
# Need to reference builder here to force ordering. But since we have to run
# something anyway, we might as well cleanup after ourselves.
RUN --mount=type=bind,from=builder,src=.,target=/var/tmp --mount=type=bind,rw=true,src=.,dst=/buildcontext,bind-propagation=shared rm /buildcontext/out.ociarchive
