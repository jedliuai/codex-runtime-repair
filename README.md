> **Chatgpt代充：[aishopvip.com](https://aishopvip.com)**

<h1 align="center">Codex 修复工具箱 · Codex Repair Toolbox</h1>

<p align="center">
  <strong>Windows 版 Codex 桌面端「打不开」和「登录报 os error 10013」的一键修复工具。</strong><br>
  One-click fixes for the two most common Codex desktop failures on Windows: <em>won't open</em> and <em>sign-in fails with os error 10013</em>.
</p>

<p align="center">
  <img alt="Platform" src="https://img.shields.io/badge/platform-Windows%2010%20%2F%2011-0078D4?style=for-the-badge&logo=windows&logoColor=white">
  <img alt="PowerShell" src="https://img.shields.io/badge/PowerShell-5.1-5391FE?style=for-the-badge&logo=powershell&logoColor=white">
  <img alt="No install" src="https://img.shields.io/badge/no_install-double--click-success?style=for-the-badge">
  <img alt="Reversible" src="https://img.shields.io/badge/changes-backed_up_%26_reversible-8A2BE2?style=for-the-badge">
</p>

<p align="center">
  <a href="#中文">中文</a> · <a href="#english">English</a>
</p>

<p align="center">
  <img alt="Codex 修复工具箱界面" src="docs/images/toolbox.png" width="820">
</p>

---

<a id="中文"></a>

## 它能解决什么问题？

只解决两个问题，对号入座：

<table>
<tr>
<th width="50%">问题一：Codex 打不开</th>
<th width="50%">问题二：Codex 登录失败（os error 10013）</th>
</tr>
<tr>
<td valign="top">

安装或<strong>自动更新后</strong>，Codex 桌面端：

- 点开后没有窗口，或窗口空白、无标题、未响应
- 任务管理器里有 `ChatGPT.exe` 进程，但就是打不开
- `%LOCALAPPDATA%\OpenAI\Codex\runtimes\cua_node` 里不断冒出 `.staging-*` 目录

👉 点 **「一键修复」**

</td>
<td valign="top">

登录或<strong>切换账号时</strong>，浏览器弹不出来，Codex 提示：

```text
登录失败：failed to start login server:
以一种访问权限不允许的方式做了一个访问套接字的尝试。
(os error 10013)
```

英文系统是 `An attempt was made to access a socket in a way forbidden by its access permissions. (os error 10013)`

👉 打开 **「登录模式」开关**，登录完再关掉

</td>
</tr>
</table>

> 不是这两个问题？例如桌面端提示「无法加载组织设置」，请看 [CODEX_CLI_PATH 排障指南](docs/organization-settings-cli-path.md#中文)。网络、账号、模型不可用等问题，这个工具帮不上忙。

## 三步使用

1. 点页面右上角 **Code → Download ZIP** 下载并解压（或 `git clone`）。
2. 双击根目录里的 **`CodexRepairToolbox.cmd`**。
3. 弹出权限提示时点 **「是」**（登录修复需要管理员权限），然后按窗口里的 ①②③ 操作。

不需要安装任何东西，只用 Windows 自带的 PowerShell。

### 问题一：一键修复

点 **「一键修复」**，确认后工具会：关闭 Codex → 备份未完成的 `.staging` 目录 → 从 Codex 安装包重建 runtime 缓存并校验 → 重新打开 Codex。

不确定要不要修？先点 **「只检查，不改文件」**，只看不改。

<p align="center"><img alt="修复完成" src="docs/images/toolbox-repaired.png" width="640"></p>

### 问题二：登录模式开关

1. 打开 **登录模式** 开关
2. 回到 Codex，点「继续登录」，在浏览器里完成登录
3. 登录成功后，把开关 **关掉**

<p align="center"><img alt="登录模式已开启" src="docs/images/toolbox-login-on.png" width="640"></p>

窗口一打开就会检测登录端口 1455，直接告诉你它是 **被系统保留**（正是 10013 的原因）、**可用**，还是 **被某个程序占用**（会写出程序名）。

忘了关也没关系：开关打开 **10 分钟后自动恢复**，**关闭窗口时也会自动恢复**。

## 为什么会出这两个问题？

**打不开：** 部分电脑上，Microsoft Store / MSIX 安装包里的 runtime 文件带有 Windows EFS 加密属性。Codex 启动时要把这些文件复制到本地缓存，但加密属性没法正确保留，复制失败后不断重试，每次都生成一个新的 `.staging-*` 半成品目录，永远进不了界面。工具改为逐字节复制，写出的是普通文件，问题就解决了。

**登录 10013：** Codex 登录时会在本机 `127.0.0.1:1455` 启动一个回调服务器。Windows 的 **WinNAT** 服务（Docker、WSL2、Hyper-V 的网络会用到）有时会把包含 1455 的一段端口保留下来，回调服务器就起不来了。临时停止 WinNAT 可以释放这段端口，登录完再启动 WinNAT 即可。登录模式开关就是做这件事：

| 开关 | 实际执行 |
|---|---|
| 打开 | `net stop winnat` |
| 关掉 / 10 分钟超时 / 关闭窗口 | `net start winnat` |

## 安全吗？

| | 问题一：一键修复 | 问题二：登录模式 |
|---|---|---|
| 改动范围 | 只改 `%LOCALAPPDATA%\OpenAI\Codex\runtimes\cua_node` | 只停止 / 启动 WinNAT 服务 |
| 能否回滚 | 旧目录移到带时间戳的备份目录，**不删除任何文件** | 关掉开关即恢复；窗口被强制结束时，下次打开会自动恢复 |
| 执行前 | 弹窗确认；也可以只检查不修改 | 先检测端口，再决定是否需要 |
| 副作用 | 会关闭 Codex（只关 `OpenAI.Codex` 包里的进程） | 开关打开期间，Docker / WSL2 的网络可能暂时中断 |

两个功能都 **不会**：删除聊天记录、重置 Codex 账号或登录状态、修改 `%APPDATA%\Codex`、卸载或重装 Codex、修改注册表、清理无关缓存、关闭无关程序。

## 命令行用法（可选）

喜欢命令行，或者需要在脚本里使用：

```powershell
# 问题一：Codex 打不开
.\scripts\Repair-CodexRuntime.ps1                 # 只检查（dry-run），不做任何修改
.\scripts\Repair-CodexRuntime.ps1 -Apply          # 修复（会要求输入 YES 确认）
.\scripts\Repair-CodexRuntime.ps1 -Apply -NoLaunch   # 修复后不自动启动 Codex

# 问题二：登录 10013（-On / -Off 需要以管理员身份运行 PowerShell）
.\scripts\Set-CodexLoginMode.ps1                  # 只查看状态
.\scripts\Set-CodexLoginMode.ps1 -On              # 停止 WinNAT，然后去 Codex 登录
.\scripts\Set-CodexLoginMode.ps1 -Off             # 登录成功后，重新启动 WinNAT
```

根目录的 `Repair-CodexRuntime.cmd` 仍然保留，双击即可用命令行方式修复问题一。

## 常见问题

**点了「一键修复」，提示目前不需要修复？**
说明没有发现未完成的 `.staging` 目录。先打开一次 Codex，等它卡住，再回来点修复。

**打开开关后还是登录失败？**
看窗口里的端口状态。如果显示「被某个程序占用」，先关掉那个程序（通常是上一次没退出的登录进程）再试。

**弹出权限提示时点了「否」？**
一键修复照样能用；登录模式开关需要管理员权限，重新双击启动器并点「是」即可。

**开关忘了关，Docker / WSL2 断网了？**
开关打开 10 分钟后会自动恢复。也可以重新打开工具箱，或者在管理员 PowerShell 里运行 `net start winnat`。

## 文件说明

| 文件 | 作用 |
|---|---|
| `CodexRepairToolbox.cmd` | 双击启动图形界面 |
| `scripts/CodexRepairToolbox.ps1` | 图形界面（PowerShell 5.1 + WPF） |
| `scripts/Repair-CodexRuntime.ps1` | 问题一的修复脚本（图形界面也调用它） |
| `scripts/Set-CodexLoginMode.ps1` | 问题二的命令行版 |
| `scripts/lib/CodexLoginMode.ps1` | 登录修复的共用函数 |
| `Repair-CodexRuntime.cmd` | 双击用命令行方式修复问题一 |
| `docs/organization-settings-cli-path.md` | 「无法加载组织设置」排障指南 |

---

<a id="english"></a>

## English

### What does it fix?

Exactly two things on the **Windows Codex desktop app**:

| Problem 1: Codex won't open | Problem 2: Sign-in fails with os error 10013 |
|---|---|
| After install or an **automatic update**, no usable window appears (blank, untitled or not responding), a `ChatGPT.exe` process keeps running, and `%LOCALAPPDATA%\OpenAI\Codex\runtimes\cua_node` fills with `.staging-*` folders. | When signing in or **switching accounts**, the browser never opens and Codex shows `failed to start login server: An attempt was made to access a socket in a way forbidden by its access permissions. (os error 10013)` |
| 👉 Click **一键修复 (Repair)** | 👉 Turn the **login mode** switch on, sign in, then turn it off |

Desktop stuck on "Unable to load organization settings" instead? See the [CODEX_CLI_PATH troubleshooting guide](docs/organization-settings-cli-path.md#english).

### Quick start

1. **Code → Download ZIP** and extract it (or `git clone`).
2. Double-click **`CodexRepairToolbox.cmd`**.
3. Click **Yes** on the UAC prompt (the login fix needs admin rights), then follow steps ①②③ in the window.

Nothing to install: it uses the built-in Windows PowerShell 5.1 and WPF.

### How it works

- **Won't open:** on some machines the runtime files inside the Microsoft Store / MSIX package carry the Windows EFS encrypted attribute. Codex cannot copy them into its local cache, so it keeps retrying and creating new `.staging-*` folders. The repair backs up the incomplete folders, copies the bundled runtime byte by byte as plain files, verifies file count, size and manifest, then relaunches Codex. Use **只检查 (check only)** for a read-only dry-run first.
- **Sign-in 10013:** Codex starts a local callback server on `127.0.0.1:1455`. The **WinNAT** service (used by Docker, WSL2 and Hyper-V networking) sometimes reserves a TCP port range that includes 1455. The switch runs the equivalent of `net stop winnat` while you sign in, and `net start winnat` when you turn it off, after 10 minutes, or when you close the window. The window tests port 1455 up front and tells you whether it is reserved, free, or used by another program.

### Safety

- Runtime repair only touches `%LOCALAPPDATA%\OpenAI\Codex\runtimes\cua_node`. Old folders are moved to timestamped backups; nothing is deleted. Only `ChatGPT.exe` processes from the `OpenAI.Codex` package are closed.
- Login mode only stops and starts the WinNAT service, plus a marker file at `%LOCALAPPDATA%\codex-runtime-repair\login-mode.json`. If the window is killed while WinNAT is stopped, the next launch restores it. Docker / WSL2 NAT networking may pause while the switch is on.
- Neither fix touches chat history, login state, `%APPDATA%\Codex`, the registry, or unrelated apps.

### Command line

```powershell
.\scripts\Repair-CodexRuntime.ps1            # dry-run, changes nothing
.\scripts\Repair-CodexRuntime.ps1 -Apply     # repair (asks you to type YES)
.\scripts\Set-CodexLoginMode.ps1             # login port / WinNAT status
.\scripts\Set-CodexLoginMode.ps1 -On         # elevated: stop WinNAT, then sign in
.\scripts\Set-CodexLoginMode.ps1 -Off        # elevated: start WinNAT again
```

### Topics

```text
codex windows powershell wpf desktop-app repair-tool runtime-cache winnat os-error-10013 openai msix efs
```
