> **Chatgpt代充：[aishopvip.com](https://aishopvip.com)**

# Codex Runtime Repair

<p align="center">
  <strong>A conservative Windows repair tool for Codex desktop startup failures caused by broken runtime cache extraction.</strong>
</p>

<p align="center">
  <a href="#english">English</a> · <a href="#中文">中文</a>
</p>

<p align="center">
  <img alt="Platform" src="https://img.shields.io/badge/platform-Windows-0078D4?style=for-the-badge&logo=windows&logoColor=white">
  <img alt="PowerShell" src="https://img.shields.io/badge/PowerShell-5%2B-5391FE?style=for-the-badge&logo=powershell&logoColor=white">
  <img alt="Safety" src="https://img.shields.io/badge/default-dry--run-success?style=for-the-badge">
  <img alt="Scope" src="https://img.shields.io/badge/scope-runtime_cache_only-8A2BE2?style=for-the-badge">
</p>

---

<a id="english"></a>

## English

### What problem does this fix?

Some Windows builds of the Codex desktop app can get stuck on startup after installation or after an automatic update.

Typical symptoms:

- Codex appears to open, but no usable window appears.
- A `ChatGPT.exe` / Codex process exists in Task Manager.
- The main window is blank, untitled, or not responding.
- `%LOCALAPPDATA%\OpenAI\Codex\runtimes\cua_node` keeps filling with incomplete `.staging-*` folders.
- Restarting Codex creates another `.staging-*` folder, but the app still does not open.

This tool repairs the local Codex runtime cache by rebuilding it from the runtime bundled inside the installed Codex package.

### Why it happens

On affected machines, files inside the Microsoft Store / MSIX package can carry Windows EFS encrypted file attributes. Codex then tries to copy or extract its bundled runtime into a local cache folder, but the copy can fail or loop because the encrypted attribute cannot be preserved correctly in the target location.

The app keeps retrying with new `.staging-*` folders, and startup never reaches the normal UI.

### What this tool does

`codex-runtime-repair` performs a narrow, reversible repair:

1. Detects the currently installed `OpenAI.Codex` package.
2. Detects the active runtime hash from `.staging-*` cache folders.
3. Backs up incomplete staging folders instead of deleting them.
4. Copies the bundled runtime file-by-file using byte streams.
5. Writes clean local files without preserving EFS encrypted attributes.
6. Verifies the copied runtime by file count, size, and manifest.
7. Launches Codex for a quick startup check.

### What it does not touch

This project is intentionally scoped to avoid collateral damage.

It does **not**:

- Delete your chat history.
- Reset your Codex account or login state.
- Modify `%APPDATA%\Codex`.
- Uninstall or reinstall Codex.
- Change Windows settings.
- Modify registry keys.
- Clean random caches.
- Kill unrelated apps.

It only works inside:

```text
%LOCALAPPDATA%\OpenAI\Codex\runtimes\cua_node
```

### Safety model

The script is designed to be cautious by default:

- Default PowerShell mode is `dry-run`.
- Apply mode requires confirmation unless `-Yes` is explicitly passed.
- Existing folders are moved to timestamped backups, not deleted.
- Only `ChatGPT.exe` processes from the `OpenAI.Codex` package are closed.
- The target runtime is verified after copying.

### Quick start

Download or clone this repository, then run:

```powershell
.\scripts\Repair-CodexRuntime.ps1
```

That performs a dry-run only. It prints the installed Codex version, packaged runtime, detected staging folders, and the exact cache path it would repair.

To actually repair:

```powershell
.\scripts\Repair-CodexRuntime.ps1 -Apply
```

You will be asked to type `YES` before any changes are made.

For one-click usage on Windows, double-click:

```text
Repair-CodexRuntime.cmd
```

The `.cmd` launcher runs the script in apply mode, but the PowerShell script still asks for confirmation.

### Advanced usage

Repair without launching Codex afterward:

```powershell
.\scripts\Repair-CodexRuntime.ps1 -Apply -NoLaunch
```

Repair without interactive confirmation:

```powershell
.\scripts\Repair-CodexRuntime.ps1 -Apply -Yes
```

Use `-Yes` only if you have already reviewed the dry-run output.

### When should I use this?

Use it when Codex desktop repeatedly fails to open after installation or update, and you see incomplete runtime staging folders under:

```text
%LOCALAPPDATA%\OpenAI\Codex\runtimes\cua_node
```

Do not use it for unrelated Codex issues such as network login failures, account errors, model availability, or project permission problems.

### Repository topics

Recommended GitHub topics:

```text
codex windows powershell desktop-app repair-tool runtime-cache openai msix efs
```

---

<a id="中文"></a>

## 中文

### 这个项目解决什么问题？

某些 Windows 环境下，Codex 桌面端在安装后或自动更新后可能卡在启动阶段。

常见表现：

- 点开 Codex 后没有可用窗口。
- 任务管理器里能看到 `ChatGPT.exe` / Codex 进程。
- 主窗口空白、无标题，或显示未响应。
- `%LOCALAPPDATA%\OpenAI\Codex\runtimes\cua_node` 里不断出现未完成的 `.staging-*` 目录。
- 重启 Codex 后又生成新的 `.staging-*`，但仍然打不开。

这个工具会从已安装的 Codex 包里提取内置 runtime，并重建本地 runtime 缓存，从而恢复启动。

### 为什么会坏？

在受影响的机器上，Microsoft Store / MSIX 安装包里的部分 runtime 文件可能带有 Windows EFS 加密属性。Codex 启动时会尝试把这些 runtime 文件复制或解包到本地缓存目录，但复制过程中可能因为加密属性无法正确保留而失败或反复重试。

结果就是：Codex 不断创建新的 `.staging-*` 半成品目录，启动流程却无法进入正常界面。

### 这个工具做了什么？

`codex-runtime-repair` 只做一件事：安全、可回滚地修复 Codex 本地 runtime 缓存。

具体步骤：

1. 自动识别当前安装的 `OpenAI.Codex` 版本。
2. 从 `.staging-*` 目录识别当前 runtime hash。
3. 把未完成的 staging 目录移动到带时间戳的备份目录。
4. 从 Codex 安装包内置 runtime 逐文件读取字节并写入本地缓存。
5. 写出的文件不保留 EFS 加密属性。
6. 通过文件数量、大小和 manifest 校验复制结果。
7. 修复完成后启动 Codex 做快速验证。

### 它不会动什么？

这个项目的范围非常窄，尽量避免造成新的问题。

它**不会**：

- 删除你的聊天记录。
- 重置你的 Codex 账号或登录状态。
- 修改 `%APPDATA%\Codex`。
- 卸载或重装 Codex。
- 修改 Windows 设置。
- 修改注册表。
- 清理无关缓存。
- 关闭无关程序。

它只操作这个目录：

```text
%LOCALAPPDATA%\OpenAI\Codex\runtimes\cua_node
```

### 安全设计

脚本默认尽量保守：

- PowerShell 主脚本默认是 dry-run，不会改任何文件。
- 真正修复需要 `-Apply`。
- 修复模式下默认仍要求你手动输入 `YES`。
- 旧目录只移动到备份，不直接删除。
- 只关闭来自 `OpenAI.Codex` 包的 `ChatGPT.exe` 进程。
- 复制完成后会校验 runtime 是否完整。

### 使用方法

下载或克隆这个仓库后，先执行 dry-run：

```powershell
.\scripts\Repair-CodexRuntime.ps1
```

dry-run 只会打印当前 Codex 版本、内置 runtime、检测到的 staging 目录，以及将要修复的缓存路径，不会进行任何修改。

确认无误后执行修复：

```powershell
.\scripts\Repair-CodexRuntime.ps1 -Apply
```

脚本会要求你输入 `YES` 后才继续。

如果你只是想双击运行，可以双击根目录里的：

```text
Repair-CodexRuntime.cmd
```

这个启动器会进入修复模式，但主脚本仍然会要求确认。

### 高级用法

修复后不自动启动 Codex：

```powershell
.\scripts\Repair-CodexRuntime.ps1 -Apply -NoLaunch
```

跳过交互确认：

```powershell
.\scripts\Repair-CodexRuntime.ps1 -Apply -Yes
```

建议只有在你已经看过 dry-run 输出后，才使用 `-Yes`。

### 什么时候该用？

当 Codex 桌面端安装或更新后反复打不开，并且你看到下面目录里不断出现 `.staging-*` 半成品目录时，可以使用这个工具：

```text
%LOCALAPPDATA%\OpenAI\Codex\runtimes\cua_node
```

如果你的问题是网络登录失败、账号异常、模型不可用、项目权限问题等，这个工具不是对应的修复方案。

### GitHub 标签建议

建议给仓库添加这些 topics：

```text
codex windows powershell desktop-app repair-tool runtime-cache openai msix efs
```
