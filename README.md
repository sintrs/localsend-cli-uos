# localsend-cli-uos

[LocalSend](https://github.com/localsend/localsend) 命令行客户端的多平台构建产物仓。

上游只发布全平台大包，而这个仓库只做一件事：**把 CLI 单独编出来，按目标系统的 glibc 分档发**。

## 与上游的关系

- 源码 100% 来自上游 [`localsend/localsend`](https://github.com/localsend/localsend) 的 `main` 分支，**不做任何修改**
- 每天 UTC 20:07（北京 04:07）构建一次，**tag 带当天日期**：`v1.19.0-20261123`
- 今天这个 tag 已经发过 → 跳过；还没发过 → 构建并发布
- 想当天再构建一次：Actions → Build & Release → Run workflow → 勾选 `force`（覆盖同名 tag 的资产）

**为什么 tag 带日期**：上游 CLI 的版本号（`cli/Cargo.toml`）一个多月才动一次，如果用纯版本号做 tag，今天构建的和一个月前的会完全相同，下游也就无从判断有没有新包。带上日期后每天都是一个独立 release，按 tag 比一次就知道要不要更新。

版本号仍然只来自上游 `cli/Cargo.toml`，tag 和资产名里的版本部分与程序 `--version` 输出完全一致，构建过程不改写任何源码。日期部分只用来区分「哪天的构建」，不参与版本语义。

## 产物

每次发布 4 个 Linux CLI 包，文件名里的 `<ver>-<date>` 与 tag 对应（例如 `v1.19.0-20261123` 对应 `1.19.0-20261123`）：

| 文件 | 需要什么 |
|---|---|
| `LocalSend-CLI-<ver>-<date>-linux-x86-64.tar.gz` | glibc ≥ 2.34（Ubuntu 22.04+ / Debian 12+） |
| `LocalSend-CLI-<ver>-<date>-linux-arm-64.tar.gz` | 同上，aarch64 |
| `LocalSend-CLI-<ver>-<date>-uos20-x86-64.tar.gz` | **glibc 2.28**（UOS 20 / Debian 10+，兼容老旧系统） |
| `LocalSend-CLI-<ver>-<date>-uos20-arm-64.tar.gz` | 同上，aarch64 |

`uos20` 两个包在 `debian:10` 容器里编译，链到 glibc 2.28。在不支持新 glibc 的国产系统上装 `linux-*` 版会报 `GLIBC_2.34 not found`，这时用 `uos20-*` 版。

Windows 安装包（`build-windows.yml`）**默认不参与发布**：构建链路本身是通的（未签名的 MSIX + Inno 的 `/DSkipSignTool` 都验证过），但一次要跑 20 分钟，产出的是 GUI 安装包，对 CLI 用途没有增益。需要时在 Actions 里手动触发 `Build Windows exe`。

安装：

```bash
tar -xzf LocalSend-CLI-<ver>-<date>-uos20-x86-64.tar.gz -C ~/.local/bin
localsend-cli --version
```

## 为什么不用 fork

这个仓库最初是为了绕过 GitHub 的一条限制：

> When a public repository is forked, scheduled workflows are disabled by default.

也就是 **fork 里的 cron 永远不会被调度**（`gh workflow enable` 也不行，实测三次窗口 0 次触发）。而工作流想每天自动检查上游、自动发版，就必须有可用的 cron。

所以改成「独立的非 fork 仓库 + 直接从上游构建」，好处是：

- cron 正常调度，不需要本机定时器兜底
- 不需要任何 PAT / secret，全部用仓库自带的 `GITHUB_TOKEN`（读上游是公开仓库）
- 产物和上游彻底解耦，上游怎么改 `.github` 都不影响这里

## 文件

```
.github/workflows/
  release.yml        定时检查上游版本 → 调用下面两个 → 发布
  build-linux.yml    4 个 Linux CLI 产物（含 uos20 / glibc 2.28）
  build-windows.yml  Windows x64 安装包（默认不参与发布，仅手动触发）
  keepalive.yml      每月 commit 一次，防止 60 天无活动导致 cron 被禁用
setup.sh             建仓库 + 推送（一次性）
```

## 已知取舍

- **Windows 包默认不发布**：构建已验证可用（见上），但耗时 20 分钟且只产出 GUI 安装包，默认从发布链里摘掉。构建未签名（上游用付费的 Azure Trusted Signing，这里改用 `.iss` 里预留的 `/DSkipSignTool`），手动触发时首次运行会有 SmartScreen 提示。
- **只按版本号触发**：上游改了 CLI 代码但没改 `Cargo.toml` 版本，这里不会重建。需要时手动 `force`。
- **Flutter 版本跟随上游**：构建时从上游的 `build_windows_exe.yml` 里读 `FLUTTER_VERSION`，读不到则用 `3.41.9`。
- **没有 deb / rpm / AppImage**：上游已有，这里只补 CLI。
