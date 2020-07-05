##################################
# Define our build-time globals  #
##################################
ARG ALPINE_VERSION=3.9
ARG HELM_VERSION=2.16.1
ARG GO_VERSION=1.9.3
ARG CLOUD_SDK_VERSION=258.0.0
ARG GOOGLE_APPLICATION_CREDENTIALS=/root/.gcloud.json

####################################
# Builder image (easier on ubuntu) #
####################################
FROM ubuntu:latest as installer

# Import our args from global
ARG HELM_VERSION
ARG GO_VERSION

# Pre-install, must install all build utils
RUN apt-get -y update && apt-get -y install curl git openssl build-essential

# Install kubernetes (always grab latest stable)
RUN curl -LO https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl 
RUN chmod a+x kubectl

# Install helm
RUN echo ${HELM_VERSION}
RUN curl https://storage.googleapis.com/kubernetes-helm/helm-v${HELM_VERSION}-linux-amd64.tar.gz > /tmp/helm-v${HELM_VERSION}-linux-amd64.tar.gz
RUN cd /tmp && tar --strip-components=1 -xf helm-v${HELM_VERSION}-linux-amd64.tar.gz && chmod a+x helm && mv helm /usr/local/bin/

# Install Go for compiling helm plugins
RUN curl -LO https://dl.google.com/go/go${GO_VERSION}.linux-amd64.tar.gz
RUN tar -C /usr/local -xzf go${GO_VERSION}.linux-amd64.tar.gz
RUN export PATH=$PATH:/root/go/bin

# Install helm plugins
RUN mkdir -p ~/.helm/plugins
RUN helm plugin install https://github.com/hypnoglow/helm-s3.git --version master
RUN helm plugin install https://github.com/databus23/helm-diff --version master
# Clean up after these messy plugins, removing build-specific stuff so only the binary gets copied
RUN find /root/.helm/cache/plugins/https-github.com-databus23-helm-diff/. -maxdepth 1 -not -name "bin" -not -name "plugin.yaml" -not -name "." -not -name ".." -exec rm -Rf {} \;
RUN find /root/.helm/cache/plugins/https-github.com-hypnoglow-helm-s3.git/. -maxdepth 1 -not -name "bin" -not -name "plugin.yaml" -not -name "." -not -name ".." -exec rm -Rf {} \;

# Install aws iam authenticator
RUN curl https://amazon-eks.s3-us-west-2.amazonaws.com/1.12.7/2019-03-27/bin/linux/amd64/aws-iam-authenticator -o /usr/local/bin/aws-iam-authenticator && \
    chmod a+x /usr/local/bin/aws-iam-authenticator


#############################################
# Builder image (for alpine-specific stuff) #
#############################################

# Running for building krane (needs to be alpine)
FROM alpine:${ALPINE_VERSION} as installer-alpine
RUN apk -v --update add ruby ruby-dev alpine-sdk ruby-rdoc
RUN gem install rake && gem install krane
# This is a dependancy for Krane that isn't auto-installed on Alpine for some reason, go figure
RUN gem install bigdecimal

################################################################################
# NOTE: The above steps are intentionally not being forced into one big run,   #
# because they are not as part of the pushed layer cache to the docker         #
# repository.  This is for ease of development and iteration and shortening it #
# does not speed up the build process.  Only the below image is what matters   #
# to be minimized and clean                                                    #
################################################################################

################
# Runner image #
################
FROM alpine:${ALPINE_VERSION}

# Import our args from global
ARG ALPINE_VERSION
ARG HELM_VERSION
ARG GO_VERSION
ARG CLOUD_SDK_VERSION
ARG GOOGLE_APPLICATION_CREDENTIALS

# Setting/saving our build args as env vars, so we "know" easily in the container which version
ENV CLOUD_SDK_VERSION=${CLOUD_SDK_VERSION}
ENV PATH /google-cloud-sdk/bin:$PATH
ENV ALPINE_VERSION=${ALPINE_VERSION}
ENV HELM_VERSION=${HELM_VERSION}
ENV GO_VERSION=${GO_VERSION}
ENV GOOGLE_APPLICATION_CREDENTIALS=${GOOGLE_APPLICATION_CREDENTIALS}

# Install dependencies
RUN apk -v --update add \
    bash \
    curl \
    docker \
    git \
    groff \
    gnupg \
    less \
    libc6-compat \
    mailcap \
    openssh-client \
    py-crcmod \
    py-pip \
    python \
    tree \
    ruby && \
  # Install TFEnv for multiple versions of Terraform support
    git clone https://github.com/tfutils/tfenv.git ~/.tfenv && \
    ln -s /root/.tfenv/bin/terraform /usr/local/bin/ && \
    ln -s /root/.tfenv/bin/tfenv /usr/local/bin/ && \
    tfenv install 0.12.13 && tfenv use 0.12.13 && tfenv install 0.12.24 && \
  # Install AWSCLI, S3CMD, and file-type detection
    pip install --upgrade awscli==1.18.93 s3cmd==2.1.0 python-magic && \
  # Install Google Cloud CLI/SDK
    curl -O https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-sdk-${CLOUD_SDK_VERSION}-linux-x86_64.tar.gz && \
    tar xzf google-cloud-sdk-${CLOUD_SDK_VERSION}-linux-x86_64.tar.gz && \
    rm google-cloud-sdk-${CLOUD_SDK_VERSION}-linux-x86_64.tar.gz && \
    gcloud config set core/disable_usage_reporting true && \
    gcloud config set component_manager/disable_update_check true && \
    gcloud config set metrics/environment github_docker_image && \
    gcloud --version && \
    apk -v --purge del py-pip && \
  # Clean up and remove apk caches to minimize image size
    rm /var/cache/apk/*

# Copy desired contents from our builder for Kubectl, Helm, and AWS-IAM-Authenticator (for eks)
COPY --from=installer kubectl /usr/local/bin/kubectl
COPY --from=installer /usr/local/bin/helm /usr/local/bin/helm
COPY --from=installer /root/.helm /root/.helm
COPY --from=installer /usr/local/bin/aws-iam-authenticator /usr/local/bin/aws-iam-authenticator
# Install Krane (with required gems) from builder image
COPY --from=installer-alpine /usr/lib/ruby /usr/lib/ruby
COPY --from=installer-alpine /usr/bin/krane /usr/bin/krane

# For kubectl perms overriding
VOLUME /root/.kube
# For importing AWS perms/config
VOLUME /root/.aws
# For GCloud perms, mount the service account 
VOLUME /root/.gcloud.json
