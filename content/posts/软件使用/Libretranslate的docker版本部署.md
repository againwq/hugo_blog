---
title: "本地docker部署libretranslate翻译模型并采用CUDA加速"
date: 2024-11-12
series: ["软件使用"]
tags: ["AI", "翻译", "阅读工具", "docker部署"]
ShowToc: true
TocOpen: true
description: Libtranslate的本地部署，并采用CUDA加速
---
## 一、Libretanslate基本介绍

&emsp;&emsp; Libretanslate 是一个开源的，基于AI驱动的翻译软件，[官方网站](https://libretranslate.com/)提供了在线的翻译功能，并且可以申请 api 密钥去调用 api 将翻译能力嵌入到我们自己的程序或者软件中。当然，[官方的github](https://github.com/LibreTranslate/LibreTranslate)有详细的本地部署教程，如果有能力建议根据官方的 README 部署，本文是对可能遇到的一些问题的补充。本文采用的是 docker 部署，当然官方提供了直接通过 pip 包部署，读者可以根据自己的需求选择。效果图如下：

![libretranslate翻译效果](/images/Libretranslate翻译效果.png)

## 二. docker 与 nvidia docker 支持的前置条件

&emsp;&emsp; 首先需要保证你的本地系统已经安装的 docker 环境，建议采用国内的源安装，比如清华源、阿里源等。同时建议配置docker镜像源防止由于网络问题无法拉取镜像。这里不提供安装配置命令，建议读者自行搜索相关资料。`</br>`
&emsp;&emsp; 使用 nvidia 的 docker 加速，需要读者本地拥有 nvidia 的显卡，并安装了显卡驱动。如果没有 nvidia 的显卡支持，可以跳过这一部分，进行 cpu 版本的本地部署。`</br>`
&emsp;&emsp; 首先要在自己的电脑上安装 nvidia docker 支持，参考的[官方地址](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html)。根据你的 linux 发行版复制粘贴命令就行了，debian 发行版的安装命令如下：

```Shell
# 添加 apt 源
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | \
sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg && \
curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
    tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

sudo sed -i -e '/experimental/ s/^#//g' /etc/apt/sources.list.d/nvidia-container-toolkit.list

# 更新源
sudo apt-get update

# 安装nvidia-container-toolkit
sudo apt-get install -y nvidia-container-toolkit
```

&emsp;&emsp; 然后对 docker 进行配置：

```Shell
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker
```

## 三、docker版本的libretranslate的本地部署

&emsp;&emsp; 接下来我们进行部署。首先，我们需要在 github 上下载源码：

```Shell
git clone git@github.com:LibreTranslate/LibreTranslate.git
```

### 1. cpu版本libretranslate的部署

&emsp;&emsp; cpu 版本部署非常简单，在源码根路径下执行下面的命令

```Shell
docker compose -f docker-compose.yml up -d --build
```

&emsp;&emsp; 这个命令会根据 docker/Dockerfile 文件构建 libretranslate 镜像并部署在本地的 5000 端口。- -build 代表重新构建镜像。第一次构建好镜像后下一次可以把 - -build命令去掉，每次创建容器都会从网络上下载指定的翻译模型，因此 5000 端口并不能立即访问，可以通过 `docker stats` 查看容器的网络 IO 状态判断翻译模型是否下载完毕。

### 2. GPU版本libretranslate的部署

&emsp;&emsp; 部署gpu版本的 libretranslate 命令与上面相同，只是将 yml 文件为 docker-compose.cuda.yml。在部署之前，最好修改 docker/cuda.Dockerfile 文件将 cuda 的相关环境变量导出，大概在文件末尾的位置添加下面几行：

```Shell
# Depending on your cuda install you may need to uncomment this line to allow the container to access the cuda libraries
# See: https://docs.nvidia.com/cuda/cuda-installation-guide-linux/index.html#post-installation-actions
# ENV LD_LIBRARY_PATH=/usr/local/cuda/lib:/usr/local/cuda/lib64
ENV LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/usr/local/cuda/lib64
ENV PATH=$PATH:/usr/local/cuda/bin
ENV CUDA_HOME=/usr/local/cuda
```

&emsp;&emsp; 然后通过 `docker compose -f docker-compose.cuda.yml up -d --build`进行构建并部署即可。同样的，构建成功 docker 会启动在本地 5000 端口，每次创建容器都会从网络上下载指定的翻译模型。

## 四、可能遇到的问题

### 1. 构建镜像时apt和pip下载太慢

&emsp;&emsp; apt 和 pip 默认的官方源在国内访问不太稳定，可以在执行 `apt install`和 `pip install`之前更换镜像源为国内源，需要在对应的 Dockerfile中修改：

```Shell
# 更换apt源为清华源
RUN sed -i 's/archive.ubuntu.com/mirrors.tuna.tsinghua.edu.cn/g'  /etc/apt/sources.list

#更换pip源为清华源，应该添加在Dockerfile中pip下载之后的位置
RUN pip3 config set global.index-url https://mirrors.tuna.tsinghua.edu.cn/pypi/web/simple

# cpu版本中Dockerfile采用了venv
RUN ./venv/bin/pip config set global.index-url https://mirrors.tuna.tsinghua.edu.cn/pypi/web/simple
```

### 2. (URLError(ConnectionRefusedError(111, 'Connection refused')),)在 docker 日志中大量出现，无法下载翻译模型

&emsp;&emsp; Libretranslate 是基于 `argos-translate` 这个开源翻译模型开发的项目，内部仍然调用的是 argos-translate，argos-tanslate 下载一个 `index.json` 文件，然后根据你指定的需要支持的语言从 index.json 中获取下载路径。index.json 默认下载到 `~/.local/cache/argos-translate` 翻译模型默认下载保存到当前路径下 `db/session` 下。我出现的问题是从 docker 内部是无法正常下载index.json的，但是主机是可以正常下载的，因此我采用的方法是手动下载 index.json 并将其放到 Libretranslate 源码根目录下，然后在我要构建的 Dockerfile 末尾修改为：

```Shell
# 将主机当前目录的index.json放到容器的/root/.local/cache/argos-translate/下
RUN mkdir -p /root/.local/cache/argos-translate/
RUN mv ./index.json /root/.local/cache/argos-translate/

EXPOSE 5000
# 原本的--host * 不知道为什么我会报错，这里改成 0.0.0.0就没有报错了
# 这里我只需要中英互译就可以了
ENTRYPOINT ["libretranslate", "--host", "0.0.0.0", "--load-only"，"zh,en"]
```

&emsp;&emsp; 这是参考的解决方案的[链接](https://community.libretranslate.com/t/failing-to-download-from-cloudflare-with-connectionrefusederror/960)，这里提供我保存的[index.json文件](/common/index.json)

### 3. 启用 cuda 加速后进行翻译出现内部错误

&emsp;&emsp; 建议先进入 docker 内部使用 python执行 `torch.cuda.is_available()` 查看 CUDA 是否成功支持。`</br>`
&emsp;&emsp; 这里我的问题是我的 **nvidia 驱动版本是 debian12 默认下载的535, CUDA 版本最高支持到 12.2**, 而且我本地的 CUDA 环境是 11.8。**Libretranslate默认构建镜像的 CUDA 版本是 12.4**, 版本过高导致 torch 调用硬件失败。解决的方法是将 Libretranslate 构建时采用的基础镜像从 `FROM nvidia/cuda:12.4.1-devel-ubuntu20.04` 更换为 `FROM nvidia/cuda:12.2.0-devel-ubuntu20.04`。 注意一定要是 12 版本以上的，我之前采用与本地相同的 11.8 启动仍然失败了，`torch.cuda.is_available()` 的返回值是 True，但是运行时会出现动态链接库找不到的问题，当前这个版本好像默认要求 CUDA 版本大于 12。

### 参考文献

> [LibreTranslate的github](https://github.com/LibreTranslate/LibreTranslate) `</br>`
> [翻译模型下载失败参考解决方案](https://community.libretranslate.com/t/failing-to-download-from-cloudflare-with-connectionrefusederror/960) `</br>`
