---
title: "docker容器访问宿主机的docker环境"
date: 2025-03-17
series: ["软件使用"]
tags: ["docker", "网络", "Linux"]
ShowToc: true
TocOpen: true
description: docker容器访问宿主机的docker环境
---

## 一、问题描述

&emsp;&emsp; 当我们使用docker容器的时候，有时候我们需要访问宿主机的docker环境，比如我们需要在容器中访问宿主机的docker服务，或者我们需要在容器中访问宿主机的docker网络。这时候我们就需要进行一些配置。

## 二、docker容器访问宿主机的docker环境

&emsp;&emsp; 要想让docker容器访问宿主机器的docker环境，并可以在docker容器中使用docker命令，我们需要在docker容器中挂载宿主机的**docker.sock文件和docker程序**。docker.sock 文件是docker的socket文件，docker的api通过这个文件来进行通信。docker程序是docker的命令行程序，我们可以通过这个程序来操作docker，比如启动容器，停止容器等。在启动docker容器的时候，我们可以通过`-v`参数来挂载这两个文件，示例如下：

```Shell
docker run -d --name controller --privileged 
-v /usr/bin/docker:/usr/bin/docker # 挂载docker程序
-v /var/run/docker.sock:/var/run/docker.sock # 挂载docker socket文件
-t ubuntu:latest
```

&emsp;&emsp; 注意，这里我们使用了`--privileged`参数，这个参数是为了让docker容器拥有更高的权限，这样我们才能在docker容器中使用docker命令。如果不加这个参数，我们在docker容器中使用docker命令的时候会报错，提示权限不够。</br>
&emsp;&emsp; 还需要注意的是，这里必须保证宿主机操作系统的**glibc版本**和容器运行的镜像的glibc版本相同，否则在容器中执行docker命令会出现glibc版本冲突的问题。因此容器和宿主机最好采用相同的linux发行版本。

## 三、在docker容器内部访问其他容器的网络命名空间

### 1. Linux网络命名空间

&emsp;&emsp;Linux 的网络命名空间（Network Namespace）是一种内核提供的资源隔离机制，它为系统中的网络资源提供了独立的上下文环境，网络命名空间允许在同一物理主机上创建多个相互隔离的网络环境。每个网络命名空间都有自己独立的网络设备（如网卡）、IP 地址、路由表、防火墙规则等网络资源。不同网络命名空间中的网络配置相互独立，互不影响。例如，在一个命名空间中配置的 IP 地址，在其他命名空间中不会冲突，也无法直接访问。**这就像是在同一台主机上虚拟出了多台独立的网络设备，每个设备都有自己的网络栈**。</br>
&emsp;&emsp; 通过刚刚的配置我们可以在容器内部使用docker network去配置容器的网络，但有时候我们需要更加复杂的网络配置，比如为两个容器创建**veth pair**。这就需要我们在容器内部访问其他容器的**Linux 网络命名空间**。

### 2. 配置方法

&emsp;&emsp; 一般的容器，如何没有使用host网络模式，都会有自己的网络命名空间，但是docker服务并没有把他们挂载到`/var/run/netns`目录下，因此使用`ip netns`等命令是无法访问到这些网络命名空间的。我们通常使用`docker inspect`获取容器的进程号，然后通过`/proc/$pid/ns/net`文件来访问容器的网络命名空间，因此我们可以通过挂载`/proc`目录来访问容器的网络命名空间。示例如下:

```Shell
docker run -d --name controller --privileged 
-v /usr/bin/docker:/usr/bin/docker
-v /var/run/docker.sock:/var/run/docker.sock 
-v /proc:/host_proc # 挂载宿主机的/proc
-t ubuntu:latest
```

&emsp;&emsp; 为了防止`/proc`与容器内部的`/proc`目录冲突，这里我将其挂载为`/host_proc`。之后我们在容器内部将其他容器的命名空间链接到`/var/run/netns`目录下，就可以使用容器的pid直接访问容器的命名空间，而不需要输入完整的路径。比如我有一个pid为123的容器，示例命令如下

```Shell
ln -s /host_proc/123/ns/net /var/run/netns/123
```

### 3. host网络模式

&emsp;&emsp; 通过上面的配置我们已经让容器可以访问其他容器的命令空间了。但是我们想要进行为两个容器创建veth pair或者使用linux bridge去连接容器，建议使用**host网络模式**。host网络模式是docker的一种网络模式，使用host网络模式的容器会和宿主机共享网络命名空间，这样容器就可以直接访问宿主机的网络设备，这样当我们使用`ip link`或者`brctl`等命令创建网络设备的时候，保证我们是在宿主机上创建的，而不是在容器内部创建的。

## 四、注意事项

- 容器和宿主机最好采用相同的linux发行版本，以避免glibc版本冲突的问题。
- 使用`--privileged`参数让docker容器拥有更高的权限，这样我们才能在docker容器中使用docker命令。
- 使用`host`网络模式，可以让容器和宿主机共享网络命名空间，这样容器就可以直接访问宿主机的网络设备。
- 如果想要创建veth pair或者使用linux bridge去连接容器，然后使用ping等命令测试网络连通性，记得需要在你的特权容器中进行如下配置，否则可能会出现网络连通性问题：

```Shell
sysctl -w net.bridge.bridge-nf-call-iptables=0 # 关闭iptables的bridge-nf功能
sysctl -w net.ipv4.icmp_echo_ignore_all=0  # 开启icmp响应
```

- 上面的这些配置会破坏docker的隔离性，在生产环境中请慎重使用。
