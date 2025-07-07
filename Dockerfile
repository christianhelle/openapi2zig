FROM ubuntu:latest
RUN apt update && apt install -y wget xz-utils
RUN wget https://ziglang.org/download/0.14.1/zig-linux-x86_64-0.14.1.tar.xz
RUN tar -xf zig-linux-x86_64-0.14.1.tar.xz
RUN mv zig-linux-x86_64-0.14.1 /opt/zig
ENV PATH="/opt/zig:$PATH"
WORKDIR /app
COPY . .
RUN zig build test
