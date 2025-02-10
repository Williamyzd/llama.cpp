ARG UBUNTU_VERSION=20.04   # 修改为目标版本 # 如果目标版本为20.04，会出现时区问题和cmake版本过低问题，需要单独调整
# This needs to generally match the container host's environment.
ARG CUDA_VERSION=11.5.2  # 修改为目标版本
# Target the CUDA build image
ARG BASE_CUDA_DEV_CONTAINER=nvidia/cuda:${CUDA_VERSION}-devel-ubuntu${UBUNTU_VERSION}  # 确保dockerhub中有该镜像

ARG BASE_CUDA_RUN_CONTAINER=nvidia/cuda:${CUDA_VERSION}-runtime-ubuntu${UBUNTU_VERSION}  # 确保dockerhub中有该镜像
ARG DEBIAN_FRONTEND=noninteractive


FROM ${BASE_CUDA_DEV_CONTAINER} AS build

# CUDA architecture to build for (defaults to all supported archs)
ARG CUDA_DOCKER_ARCH=default
# 版本为20.04时，需要单独调整时区问题，需要调整部分
###########################################
ENV TZ=Etc/UTC
RUN apt-get update && \
     apt-get install -y tzdata wget tar  build-essential  python3 python3-pip git libcurl4-openssl-dev libgomp1 && \
      wget https://github.com/Kitware/CMake/releases/download/v3.31.5/cmake-3.31.5-linux-x86_64.tar.gz  && \
      tar -zxvf cmake-3.31.5-linux-x86_64.tar.gz  && mv cmake-3.31.5-linux-x86_64 /opt/cmake && \ 
      ln -s  /opt/cmake/bin/cmake  /usr/bin/cmake && cmake --version 
###########################################


WORKDIR /app

COPY . .

RUN if [ "${CUDA_DOCKER_ARCH}" != "default" ]; then \
    export CMAKE_ARGS="-DCMAKE_CUDA_ARCHITECTURES=${CUDA_DOCKER_ARCH}"; \
    fi && \
    cmake -B build -DGGML_NATIVE=OFF -DGGML_CUDA=ON -DLLAMA_CURL=ON ${CMAKE_ARGS} -DCMAKE_EXE_LINKER_FLAGS=-Wl,--allow-shlib-undefined . && \
    cmake --build build --config Release -j$(nproc)

RUN mkdir -p /app/lib && \
    find build -name "*.so" -exec cp {} /app/lib \;

RUN mkdir -p /app/full \
    && cp build/bin/* /app/full \
    && cp *.py /app/full \
    && cp -r gguf-py /app/full \
    && cp -r requirements /app/full \
    && cp requirements.txt /app/full \
    && cp .devops/tools.sh /app/full/tools.sh

## Base image
FROM ${BASE_CUDA_RUN_CONTAINER} AS base

RUN apt-get update \
    && apt-get install -y libgomp1 curl\
    && apt autoremove -y \
    && apt clean -y \
    && rm -rf /tmp/* /var/tmp/* \
    && find /var/cache/apt/archives /var/lib/apt/lists -not -name lock -type f -delete \
    && find /var/cache -type f -delete

COPY --from=build /app/lib/ /app

# 此处删除了light full 等不必要的镜像信息，仅留了server信息
### Server, Server only
FROM base AS server

ENV LLAMA_ARG_HOST=0.0.0.0

COPY --from=build /app/full/llama-server /app

WORKDIR /app

HEALTHCHECK CMD [ "curl", "-f", "http://localhost:8080/health" ]

ENTRYPOINT [ "/app/llama-server" ]
