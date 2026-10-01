# Gunshot 6.72 Agent Memory & Guidelines

## 1. 产物下载与覆盖规范 (Artifact Download Rules)
- **下载前必须先删除旧文件/旧目录**：
  `gh run download` 如果目标路径已存在同名文件，会报 `error extracting ...: openat ...: file exists` 导致解压失败退出。
  每次执行下载或更新产物前，**必须先清空或删除旧的目标文件与目录**（例如 `rm -rf /tmp/staging/*` 或删除旧的 `.deb` / `.dylib` 文件），切勿直接原地覆盖。

## 2. 系统下载路径规范 (Artifact Destination Paths)
下载最新产物时，需同步放置到以下路径：
1. **Windows 系统下载目录（用户日常使用主路径）**：
   - 目标路径：`/mnt/c/Users/Seiry/Downloads/`
   - 根目录下直接放置常用产物：
     - `GunshotJailed.dylib`
     - `gotohp-tweak-jailed.deb`
     - `dev.tqmane.gunshot_0.2.6_iphoneos-arm64.deb`（rootless 越狱包）
     - `dev.tqmane.gunshot_0.2.6_iphoneos-arm.deb`（rootful 越狱包）
     - `ThirdPartyNotices.txt`
   - 完整分类子目录：`/mnt/c/Users/Seiry/Downloads/gunshot-6.72/`（含各 scheme 及 settings-ui-smoke 截图）
2. **Linux 用户下载目录（WSL 镜像备份）**：
   - 目标路径：`/home/seiry/Downloads/`
3. **仓库本地产物目录**：
   - 目标路径：`download/`
