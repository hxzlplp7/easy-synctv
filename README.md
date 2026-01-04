# Easy-SyncTV

一键部署 [SyncTV](https://github.com/synctv-org/synctv) 的 Bash 脚本，支持多种平台和环境。

## ✨ 特性

- 🖥️ **多平台支持**: Linux (Debian/Ubuntu/CentOS/Alpine) + FreeBSD/Serv00/HostUno
- 🔧 **多模式安装**: root 系统级 + 非 root 用户级
- 🚀 **智能检测**: 自动识别 OS、架构、微架构(v1-v4)、服务管理系统
- 📦 **完整管理**: 安装/升级/启动/停止/重启/卸载一站式操作
- 🌐 **NAT VPS**: 支持自定义端口配置
- ⚡ **代理加速**: 支持 GitHub 代理下载

## 📋 支持平台

| 平台 | 服务管理 | 安装目录 |
|------|---------|---------|
| Ubuntu/Debian/CentOS | systemd | `/usr/bin/synctv` |
| Alpine Linux | OpenRC | `/usr/bin/synctv` |
| FreeBSD/Serv00/HostUno | daemon | `~/synctv/` |

## 🚀 快速开始

### 一键安装

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/hxzlplp7/easy-synctv/main/synctv.sh)
```

**使用代理加速 (国内用户):**
```bash
GH_PROXY="https://ghfast.top/" bash <(curl -fsSL https://raw.githubusercontent.com/hxzlplp7/easy-synctv/main/synctv.sh)
```

### 本地运行

```bash
curl -fsSL https://raw.githubusercontent.com/hxzlplp7/easy-synctv/main/synctv.sh -o synctv.sh
chmod +x synctv.sh
./synctv.sh
```

## 📖 使用方法

### 交互式菜单

运行脚本后会显示管理菜单:

```
========================================
       SyncTV 管理面板
========================================

  1. 安装/重装 SyncTV
  2. 升级 SyncTV
  3. 启动服务
  4. 停止服务
  5. 重启服务
  6. 查看状态
  7. 查看日志
  8. 设置开机自启
  9. 配置端口 (NAT VPS)
 10. 卸载 SyncTV
  0. 退出
```

### 命令行模式

```bash
./synctv.sh install      # 安装最新版
./synctv.sh install v0.9.15  # 安装指定版本
./synctv.sh upgrade      # 升级到最新版
./synctv.sh start        # 启动服务
./synctv.sh stop         # 停止服务
./synctv.sh restart      # 重启服务
./synctv.sh status       # 查看状态
./synctv.sh logs         # 查看日志
./synctv.sh uninstall    # 卸载
```

## 🔐 默认账号

安装成功后访问 `http://服务器IP:8080`

| 项目 | 值 |
|-----|-----|
| 用户名 | `root` |
| 密码 | `root` |

> ⚠️ **安全提示**: 请首次登录后立即修改默认密码！

## 🛠️ 环境变量

| 变量 | 说明 | 示例 |
|-----|------|-----|
| `GH_PROXY` | GitHub 代理地址 | `https://ghfast.top/` |

## 📁 文件位置

### Root 用户
- 二进制: `/usr/bin/synctv`
- 数据目录: `/opt/synctv`
- 服务文件: `/etc/systemd/system/synctv.service`

### 非 Root 用户 (FreeBSD/Serv00)
- 二进制: `~/synctv/bin/synctv`
- 数据目录: `~/synctv/data`
- 启动脚本: `~/synctv/start.sh`

## 📜 License

MIT License

## 🙏 致谢

- [SyncTV](https://github.com/synctv-org/synctv) - 原项目
