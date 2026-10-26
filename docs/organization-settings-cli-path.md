# Windows desktop: Unable to load organization settings / 无法加载组织设置

[English](#english) · [中文](#中文)

<a id="english"></a>

## English

### Symptoms and scope

The Windows Codex desktop app stops at **"Unable to load organization settings"**, with Retry, Sign out, and Exit buttons, while Codex CLI still works on the same computer.

One possible cause is a **User-scoped `CODEX_CLI_PATH` override** pointing to an external CLI, such as an npm installation. The desktop app can select that executable instead of its bundled backend; an incompatible backend can then fail during startup policy loading. The dialog's network/proxy wording alone does not establish a network failure.

This is a targeted workaround, not a universal fix. On **2026-10-26**, this repository's owner confirmed recovery after backing up and removing an npm CLI override and restarting Windows. Both Process and User scopes had the override; Machine scope was empty. The result supports this workaround for that installation, but the exact protocol incompatibility was not independently established.

Related firsthand reports and startup log examples: [openai/codex issue #48324](https://github.com/openai/codex/issues/48324). Relevant log strings include `source=override`, `Desktop startup policy read failed`, and `reason=protocol` under `%LOCALAPPDATA%\Codex\Logs`. These are diagnostic clues, not required symptoms in every case.

### 1. Check the override without changing anything

Run in PowerShell; the output uses full strings to avoid truncating long paths:

```powershell
foreach ($scope in 'Process', 'User', 'Machine') {
    $value = [Environment]::GetEnvironmentVariable('CODEX_CLI_PATH', $scope)
    Write-Output ('{0}: {1}' -f $scope, $value)
}
```

The confirmed case had a path resembling:

```text
C:\Users\<user>\AppData\Roaming\npm\node_modules\@openai\codex\node_modules\@openai\codex-win32-x64\vendor\...
```

If User is empty, this User-scoped workaround does not apply. If Machine is populated, or you intentionally manage a custom backend, review that configuration before making changes. A working CLI alone does not prove that desktop and CLI use the same account, executable, or network path.

### 2. Back up and remove the User override

Save your work and fully exit the desktop app. Use the following shared repair snippet only after confirming the User override is unexpected or stale:

```powershell
$oldPath = [Environment]::GetEnvironmentVariable('CODEX_CLI_PATH', 'User')

if ([string]::IsNullOrWhiteSpace($oldPath)) {
    Write-Host 'No User-scoped CODEX_CLI_PATH override found; nothing changed.'
} else {
    $backupDir = Join-Path $env:USERPROFILE 'codex-repair-backups'
    New-Item -ItemType Directory -Path $backupDir -Force -ErrorAction Stop | Out-Null
    $backupName = 'CODEX_CLI_PATH-{0}-{1}.txt' -f (
        Get-Date -Format 'yyyyMMdd-HHmmss'
    ), [guid]::NewGuid().ToString('N')
    $backup = Join-Path $backupDir $backupName
    Set-Content -LiteralPath $backup -Value $oldPath -NoNewline -Encoding UTF8 -ErrorAction Stop

    [Environment]::SetEnvironmentVariable('CODEX_CLI_PATH', $null, 'User')
    [Environment]::SetEnvironmentVariable('CODEX_CLI_PATH', $null, 'Process')

    Write-Host "Original User value saved to: $backup"
    Write-Host 'Override removed. Save your work, then restart Windows.'
}
```

The backup must succeed before the override is removed. Keep the printed backup path for rollback. This changes the persistent **User environment variable** and the **current PowerShell process environment**; it leaves Machine scope unchanged. Removing the User variable alone does not update already-running GUI processes.

The snippet does not uninstall or update the npm CLI, alter `PATH`, edit Codex configuration, or reset chat history or login state. It is separate from `scripts/Repair-CodexRuntime.ps1` and `Repair-CodexRuntime.cmd`; those entry points retain their original behavior.

### 3. Restart and verify

1. Save your work and restart Windows manually.
2. Open a new PowerShell and repeat step 1. For the confirmed case, both Process and User should now be empty, with Machine still empty.
3. Open the desktop app and confirm that the blocking dialog is gone and the normal interface loads.
4. If you also use the CLI, confirm that your usual `codex` command still works.

If the error remains, inspect the desktop startup logs and installed app version before trying another repair. Do not infer runtime cache corruption from this dialog alone. The repository's runtime repair tool applies when its documented incomplete `.staging-*` cache symptoms are present.

### Rollback

Replace the placeholder with the exact backup path printed in step 2, then run:

```powershell
$backup = 'C:\Users\<user>\codex-repair-backups\CODEX_CLI_PATH-<timestamp>-<id>.txt'
$savedPath = Get-Content -LiteralPath $backup -Raw -Encoding UTF8 -ErrorAction Stop
if ([string]::IsNullOrWhiteSpace($savedPath)) {
    throw 'Backup is empty; no environment variable was changed.'
}
[Environment]::SetEnvironmentVariable('CODEX_CLI_PATH', $savedPath, 'User')
[Environment]::SetEnvironmentVariable('CODEX_CLI_PATH', $savedPath, 'Process')
Write-Host 'Original User override restored. Save your work, then restart Windows.'
```

This restores the original User value and makes that value effective in the current PowerShell. Save your work and restart Windows again to refresh GUI processes. If Process originally differed from User, rollback does not recreate that separate process-only value.

---

<a id="中文"></a>

## 中文

### 现象与适用范围

Windows Codex 桌面端启动后提示 **“无法加载组织设置”**，界面只有“重试 / 退出登录 / 退出”；同一台电脑上的 Codex CLI 却能正常使用。

一种可能原因是：**用户级 `CODEX_CLI_PATH` 环境变量指向了外部 CLI**，例如 npm 安装的版本。桌面端因此可能选用外部可执行文件，而不是内置后端；后端不兼容时，启动阶段的策略读取可能失败。弹窗虽然提到网络、代理和防火墙，但仅凭这段提示不能认定网络有问题。

**本仓库作者已于 2026-10-26 验证恢复**：当时 Process 和 User 都指向 npm 安装的 CLI，Machine 为空；备份并清除用户级覆盖变量、重启 Windows 后，桌面端恢复正常。这个结果支持本例的修复方式，具体是哪项协议不兼容并未独立确认，也不代表所有同类弹窗都能这样解决。

相关一手案例与启动日志示例见 [openai/codex issue #48324](https://github.com/openai/codex/issues/48324)。`%LOCALAPPDATA%\Codex\Logs` 中的 `source=override`、`Desktop startup policy read failed`、`reason=protocol` 可作为排查线索，并非每个案例都必须出现。

### 第一步：只读检查

在 PowerShell 运行上方 [英文部分第一步](#1-check-the-override-without-changing-anything) 的检查代码。它会完整打印 Process、User、Machine 三个作用域，避免表格把长路径截断。

本例中的路径类似：

```text
C:\Users\<user>\AppData\Roaming\npm\node_modules\@openai\codex\node_modules\@openai\codex-win32-x64\vendor\...
```

- **User 为空**：不适用这项用户级修复。
- **User 指向意外或过期的外部 CLI，Machine 为空**：与本次已验证案例相符，可以继续。
- **Machine 有值，或外部 CLI 是你有意配置的**：先核对用途，不要照搬清除步骤。

CLI 能用也不意味着桌面端和 CLI 一定使用相同的账户、可执行文件或网络路径。

### 第二步：备份后清除覆盖变量

保存工作并完整退出桌面端，然后执行上方 [英文部分第二步](#2-back-up-and-remove-the-user-override) 的修复代码。中英文说明共用这一份代码，避免两份命令产生差异。

它会先将 User 原值保存到 `%USERPROFILE%\codex-repair-backups` 下的独立文本文件，**只有备份成功才会继续**，随后清除 User 和当前 PowerShell 的 Process 值。请保留终端打印的备份路径。

这一步会修改持久化的用户环境变量，不修改 Machine；仅清除当前 PowerShell 的变量也无法更新已经运行的桌面进程。它不卸载或更新 npm CLI，不改 `PATH`、Codex 配置、聊天记录或登录状态。

原有 `scripts/Repair-CodexRuntime.ps1` 和 `Repair-CodexRuntime.cmd` 不执行这项修复，行为保持不变。

### 第三步：重启并验证

1. 保存工作，手动重启 Windows。
2. 新开一个 PowerShell，再执行只读检查。本例预期 Process 和 User 都为空，Machine 仍为空。
3. 打开 Codex 桌面端，确认“无法加载组织设置”弹窗消失，正常界面能够加载。
4. 如果日常也使用 CLI，再确认平常的 `codex` 命令仍能使用。

如果仍然报错，继续查看桌面端启动日志和安装版本。这个弹窗本身不足以证明 runtime 缓存损坏；只有同时存在原 README 描述的 `.staging-*` 半成品等症状时，才考虑对应的 runtime 修复流程。

### 如何回退

执行上方 [Rollback](#rollback) 的代码，将 `$backup` 替换成第二步实际打印的备份路径。代码会读取备份，恢复原 User 值，并在当前 PowerShell 中使用该值；随后保存工作并再次重启 Windows，使桌面进程获取恢复后的环境变量。

如果修复前 Process 与 User 原本不同，这个回退步骤只恢复原 User 值，不重建当时单独设置的 Process 值。
