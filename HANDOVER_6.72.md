# Google Photos 6.72.0 适配与交接文档 (Handoff Documentation)

## 一、背景与目标
- **目标版本**：Google Photos **6.72.0**（Build `6.72.608184154`，IPA 文件名 `GooglePhotos_6.72.0.ipa`）。
- **运行环境要求**：Mach-O `LC_BUILD_VERSION` 与 `Info.plist` 均声明为 **iOS 15.0**（SDK 17.2）。相较于原有的 7.20.2（iOS 16.1+）与 7.92.0（iOS 18.0+），6.72.0 成为 iOS 15 系列（Dopamine 越狱、TrollStore、LiveContainer 侧载）的基准版本。
- **二进制特性**：arm64 单架构，`cryptid = 0`（完全解密），主程序 6,470 类 / 68,963 方法，ModuleFramework 14,573 类 / 82,924 方法。

---

## 二、已完成的适配与关键修复

### 1. 原生无限存储文案键回退（`UI/GSUnlimitedStorage.m`）
- **现象**：6.72.0 的 `OneGoogle.bundle` 中尚未拆分 `OneGoogleStorageCardUnlimitedTitle`，仅有 `OneGoogleStorageCardUnlimitedSubtitle`（ID `0x78`，内容为 `"Unlimited"` / 日文 `"無制限"` / 中文 `"无限"` 等）。
- **修复**：`GSUnlimitedTitle()` 先查询 `OneGoogleStorageCardUnlimitedTitle`，缺失时自动 fallback 查询 `OneGoogleStorageCardUnlimitedSubtitle`。

### 2. 画质与存储策略 ABI 精确分支（`UI/GSPhotosIntegration.m`）
- **现象**：`PHSServerPhoto.storagePolicy` 在 7.20.2/7.92.0 中为 `C16@0:8`（8 位 `unsigned char`），而在 6.72.0 中为 `i16@0:8`（32 位整型）。
- **修复**：
  - 诊断读取：按 `C16@0:8` 与 `i16@0:8` 分开分支，分别用 `unsigned char` / `%u` 和 `int` / `%d` 调用，确保负数与 `>255` 值不被截断；
  - Stack Hook：6.72.0 无 `PHSOneUpInfoPanelDetailsStackViewModel`，因此 `GSDisplayStoragePolicy` 保持 `C16@0:8` 专属，不挂载到整型方法上。

### 3. 头像点击闪退的核心定位与修复（`UI/GSAccountMenu.m`）
- **崩溃原因深度反汇编（Reverse Engineering）**：
  - 用户反馈“点击右上角头像瞬间闪退”；
  - 打开 Account Menu 时，Google Photos 会先调用 `PHSMyAccountMenuDataSource` 的 `numberOfCustomSectionsForAccountMenuViewController:`，Tweak 返回 `GSSections + 1`，将 GoToHP 设置放置在新增的最后一个分区 `count`；
  - 随后 Google Photos 在准备菜单项时，会对其内部 item 枚举调用 `[self indexPath:path representsItem:3/1/2/0]`；
  - 反汇编 `0x1002d095c`（`-[PHSMyAccountMenuDataSource indexPath:representsItem:]`）发现 Google 自身的严重边界 Bug：
    ```text
    0x1002d0988: mov x22, x0  ; x22 = [path section]
    0x1002d09a4: mov x24, x0  ; x24 = [customSections count]
    0x1002d09b0: cmp x22, x24 ; 比较 section 与 count
    0x1002d09b4: b.le #0x1002d09c0 ; 错误使用了 b.le (<=) 而非 b.lt (<)
    ...
    0x1002d09e4: bl [customSections objectAtIndex:section] ; 发生越界读取！
    ```
  - 当 `section == count`（即 GoToHP 的分区）时，条件 `<= count` 成立，执行 `[customSections objectAtIndex:count]`，立即抛出 `NSRangeException: Index 1 beyond bounds [0 .. 0]` 未捕获异常，导致应用崩溃（`SIGABRT` / `Abort trap: 6`）。
- **修复方案**：
  - 在 `UI/GSAccountMenu.m` 中 Hook `indexPath:representsItem:`（签名 `B32@0:8@16Q24`）；
  - 当 `path.section >= GSSection(object, nil)` 时，说明是 Tweak 自定义分区，直接返回 `NO`，彻底阻断越界访问，确保菜单正常加载。

### 4. 上传时前台自动防息屏机制（`UI/GSBackupLifecycle.m` & `UI/GSUploadMonitor.m`）
- **实现原理**：
  - `GSUploadMonitor.m` 实现 `GSUploadQueueActive()`，检查当前是否有 `pending`、`preparing`、`uploading`、`committing` 状态的任务，并在轮询或前后台切换时发送 `GSUploadMonitorStateDidChangeNotification` 通知；
  - `GSBackupLifecycle.m` 接收状态变化通知及原生前后台生命周期通知；
  - 当前台有正在上传的队列或正在准备批量相册导入（`GSBatchImportSnapshot()[@"active"]`）时，自动在主线程设置 `UIApplication.sharedApplication.idleTimerDisabled = YES`，防止系统自动锁定熄屏中断传输；
  - 任务全部上传完成（队列空闲）、暂停或 App 退至后台时，自动恢复为 `NO`，保证系统正常休眠与节电。


### 5. 队列管理增强：支持清除失败项与清除所有任务（`UI/GSPanel.m` & `internal/service/`）
- **功能特性**：
  - 在 GoToHP 设置面板的「队列管理」分区新增两个操作按钮：
    - **清除失败项 (`clear_failed`)**：一键移除队列中所有处于 `failed` 状态的条目，并清理其对应的暂存目录与文件，避免重复占用磁盘；
    - **清除所有任务 (`clear_all`)**：一键中断当前正在上传的后台 runner 上下文，彻底移除所有待处理、失败与历史记录，并清空所有暂存文件。
  - 全流程支持四种语言（中、英、日、越）本土化显示及完整的 Go 引擎单元测试覆盖。
---

## 三、当前代码改动清单
- `Shared/GSPhotosCompatibility.h`：增加 `6.72.0` 与 `6.72` 至 `GSPhotosHostAudited()`。
- `UI/GSAccountMenu.m`：Hook `indexPath:representsItem:` 防御越界异常。
- `UI/GSUnlimitedStorage.m`：支持 Subtitle 键 fallback。
- `UI/GSPhotosIntegration.m`：`storagePolicy` 精确类型分支读取。
- `docs/analysis/google-photos-6.72.0.md`：详细审计报告。
- `docs/analysis/objc/6.72.0-contracts.json`：6.72.0 的 24 类符号契约清单。
- `tests/`：添加兼容性与 `indexPath:representsItem:` 越界拦截回归测试。
- `.github/workflows/build.yml`：集成 6.72.0 契约测试与循环验证。

---

## 四、编译产物与获取路径
通过 GitHub Actions（Run `36757027556`）编译完成，已下载至 Windows 目录：
- **`G:\Seiry\Downloads\Gunshot-6.72-build\gotohp-tweak-jailed\GunshotJailed.dylib`**（9.2 MB）
- **`G:\Seiry\Downloads\Gunshot-6.72-build\gotohp-tweak-jailed\gotohp-tweak-jailed.deb`**（2.6 MB）

*(注：测试此修复时，请使用上述最新下载的 `GunshotJailed.dylib` 重新注入 IPA 进行测试)*

---

## 五、macOS 环境接力指南（若仍需进一步真机调试）

如果在刷入最新 dylib 后点击头像仍然闪退，切换到 macOS 后接力排查步骤如下：

### 1. 抓取真机 Crash 日志（最优先）
1. iPhone 连接至 Mac，在 Mac 打开 **Console.app（控制台）**；
2. 在左侧选择连接的 iPhone 设备，右上角搜索框输入进程名 `GooglePhotos` 或 subsystem `dev.tqmane`；
3. 点击右上角头像触发崩溃，观察控制台输出的**异常原因（Exception reason / terminating with uncaught exception）**；
4. 或者在 iPhone 上前往：**设置 -> 隐私与安全性 -> 分析与改进 -> 分析数据**，搜索 `GooglePhotos-*.ips`，将其 AirDrop 传到 Mac。打开该 `.ips` 文件，重点查看 `Exception Type` 与 `Thread 0 Crashed` 调用栈。

### 2. macOS 本地构建命令
macOS 下配备 Xcode 命令行工具与 Theos 时，可直接在本地秒级编译排查，无需等待 GitHub Actions：
```bash
cd gunshot-6.72
# 编译 Jailed dylib 和 deb
bash scripts/package.sh jailed
# 产物直接生成在 packages/jailed/GunshotJailed.dylib
```

### 3. 本地单测与 ABI 验证
```bash
# 运行单元测试
python3 scripts/localization.py --check
python3 scripts/prepare-core.py
go test -tags cli ./...

# 运行 Objective-C 契约测试
clang -fobjc-arc -framework Foundation -Itests/menu-shims -Itests/native-shims UI/GSAccountMenu.m tests/account_menu.m -o .build/account-menu-test
.build/account-menu-test
```
