[CmdletBinding()]
param(
    # 登录模式打开后，多少分钟自动恢复 WinNAT。
    [ValidateRange(1, 120)]
    [int]$AutoRestoreMinutes = 10,

    # 不自动申请管理员权限（登录修复开关将不可用）。
    [switch]$NoElevate,

    # 开发用：把界面渲染成 PNG 后退出，不显示窗口、不修改任何东西。
    [string]$RenderPreview,
    [ValidateSet('Detected', 'LoginOn', 'Repaired', 'Live')]
    [string]$PreviewState = 'Detected'
)

# Codex 修复工具箱：Codex 打不开（runtime 缓存）+ Codex 登录失败（os error 10013）。
# 运行环境：Windows PowerShell 5.1（WPF），无需安装任何依赖。

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

. (Join-Path $PSScriptRoot 'lib\CodexLoginMode.ps1')
$RepairScript = Join-Path $PSScriptRoot 'Repair-CodexRuntime.ps1'

# ---------------------------------------------------------------- 管理员权限
$script:IsAdmin = Test-IsAdministrator
if (-not $script:IsAdmin -and -not $NoElevate -and -not $RenderPreview) {
    $arguments = @(
        '-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden',
        '-File', ('"{0}"' -f $PSCommandPath),
        '-AutoRestoreMinutes', $AutoRestoreMinutes
    )
    try {
        Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $arguments | Out-Null
        exit 0
    } catch {
        # 用户在 UAC 里点了「否」：以普通权限继续，登录修复开关会提示需要管理员。
    }
}

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

# ---------------------------------------------------------------- 界面
[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Codex 修复工具箱" Width="1040" Height="680"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        ResizeMode="CanMinimize" WindowStartupLocation="CenterScreen"
        FontFamily="Microsoft YaHei UI, Segoe UI" Foreground="#141413"
        UseLayoutRounding="True" TextOptions.TextFormattingMode="Display">
  <Window.Resources>
    <FontFamily x:Key="Serif">Noto Serif SC, Source Han Serif SC, Source Han Serif CN, 思源宋体, STZhongsong, 华文中宋, SimSun</FontFamily>
    <FontFamily x:Key="Mono">Cascadia Mono, Consolas</FontFamily>

    <Style x:Key="BigPill" TargetType="Button">
      <Setter Property="Width" Value="220"/>
      <Setter Property="Height" Value="112"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Grid>
              <Border x:Name="Bd" CornerRadius="56" Background="{TemplateBinding Background}"
                      BorderBrush="#141413" BorderThickness="2">
                <Border.Effect>
                  <DropShadowEffect Color="#141413" Direction="315" ShadowDepth="5" BlurRadius="0" Opacity="1"/>
                </Border.Effect>
              </Border>
              <ContentPresenter Margin="2" HorizontalAlignment="Stretch" VerticalAlignment="Stretch"/>
            </Grid>
            <ControlTemplate.Triggers>
              <Trigger Property="IsPressed" Value="True">
                <Setter TargetName="Bd" Property="Effect">
                  <Setter.Value>
                    <DropShadowEffect Color="#141413" Direction="315" ShadowDepth="2" BlurRadius="0" Opacity="1"/>
                  </Setter.Value>
                </Setter>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter Property="Opacity" Value="0.55"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="LinkButton" TargetType="Button">
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Foreground" Value="#8A3313"/>
      <Setter Property="FontSize" Value="13"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border Background="Transparent" Padding="0,4">
              <TextBlock Text="{Binding Content, RelativeSource={RelativeSource TemplatedParent}}" TextDecorations="Underline"/>
            </Border>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="ChromeButton" TargetType="Button">
      <Setter Property="Width" Value="40"/>
      <Setter Property="Height" Value="32"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Foreground" Value="#4D4C48"/>
      <Setter Property="FontSize" Value="14"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Bd" Background="Transparent" CornerRadius="6">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="#E8E6DC"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="Tag" TargetType="Border">
      <Setter Property="Background" Value="#FAF9F5"/>
      <Setter Property="BorderBrush" Value="#141413"/>
      <Setter Property="BorderThickness" Value="1.5"/>
      <Setter Property="CornerRadius" Value="14"/>
      <Setter Property="Padding" Value="12,3"/>
    </Style>
  </Window.Resources>

  <Border CornerRadius="14" BorderBrush="#141413" BorderThickness="1.5" Background="#FAF9F5">
    <Grid>
      <Grid.RowDefinitions>
        <RowDefinition Height="66"/>
        <RowDefinition Height="*"/>
        <RowDefinition Height="40"/>
      </Grid.RowDefinitions>

      <!-- 顶栏 -->
      <Border x:Name="TitleBar" Grid.Row="0" Background="#FAF9F5" CornerRadius="13,13,0,0"
              BorderBrush="#141413" BorderThickness="0,0,0,1.5" Padding="28,0,14,0">
        <DockPanel LastChildFill="False">
          <StackPanel DockPanel.Dock="Left" Orientation="Horizontal" VerticalAlignment="Center">
            <TextBlock Text="Codex 修复工具箱" FontFamily="{StaticResource Serif}" FontSize="22" FontWeight="Black" VerticalAlignment="Center"/>
            <TextBlock Text="两个常见问题，各一个按钮解决" FontSize="13" Foreground="#4D4C48" Margin="14,4,0,0" VerticalAlignment="Center"/>
          </StackPanel>
          <StackPanel DockPanel.Dock="Right" Orientation="Horizontal" VerticalAlignment="Center">
            <Border Style="{StaticResource Tag}" Padding="10,2" Margin="0,0,12,0" VerticalAlignment="Center">
              <TextBlock x:Name="AdminText" Text="管理员" FontSize="12" FontWeight="Bold"/>
            </Border>
            <Button x:Name="MinButton" Style="{StaticResource ChromeButton}" Content="—" ToolTip="最小化"/>
            <Button x:Name="CloseButton" Style="{StaticResource ChromeButton}" Content="✕" ToolTip="关闭"/>
          </StackPanel>
        </DockPanel>
      </Border>

      <Grid Grid.Row="1">
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="*"/>
        </Grid.ColumnDefinitions>

        <!-- 问题一：Codex 打不开 -->
        <Border Grid.Column="0" Background="#EBDBBC" Padding="32,24,32,22">
          <Grid>
            <Grid.RowDefinitions>
              <RowDefinition Height="Auto"/>
              <RowDefinition Height="Auto"/>
              <RowDefinition Height="Auto"/>
              <RowDefinition Height="*"/>
              <RowDefinition Height="Auto"/>
              <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>
            <StackPanel Grid.Row="0" Orientation="Horizontal">
              <Border Style="{StaticResource Tag}">
                <TextBlock Text="问题 一" FontFamily="{StaticResource Serif}" FontSize="14" FontWeight="Black"/>
              </Border>
              <TextBlock Text="runtime cache" FontFamily="{StaticResource Mono}" FontSize="12" Foreground="#4D4C48" Margin="10,0,0,0" VerticalAlignment="Center"/>
            </StackPanel>
            <TextBlock Grid.Row="1" Text="Codex 打不开" FontFamily="{StaticResource Serif}" FontSize="42" FontWeight="Black" Margin="0,14,0,0"/>
            <TextBlock Grid.Row="2" Text="安装或更新后点开没窗口、卡在启动、空白或未响应。" FontSize="14" Foreground="#3D3D3A" TextWrapping="Wrap" Margin="0,8,0,0"/>

            <StackPanel Grid.Row="3" Orientation="Horizontal" VerticalAlignment="Center">
              <Button x:Name="RepairButton" Style="{StaticResource BigPill}" Background="#A3401A" Foreground="#FAF9F5"
                      AutomationProperties.Name="一键修复 Codex 启动问题">
                <TextBlock x:Name="RepairLabel" Text="一键修复" FontFamily="{StaticResource Serif}" FontSize="32" FontWeight="Black"
                           HorizontalAlignment="Center" VerticalAlignment="Center"/>
              </Button>
              <StackPanel Margin="26,0,0,0" VerticalAlignment="Center" MaxWidth="190">
                <TextBlock x:Name="RepairStatus" Text="正在检测…" FontSize="14" FontWeight="Bold" Foreground="#8A3313" TextWrapping="Wrap"/>
                <TextBlock x:Name="RepairDetail" Text="" FontSize="14" Foreground="#3D3D3A" TextWrapping="Wrap" Margin="0,4,0,0"/>
                <Button x:Name="CheckButton" Style="{StaticResource LinkButton}" Content="只检查，不改文件 →" HorizontalAlignment="Left" Margin="0,4,0,0"/>
              </StackPanel>
            </StackPanel>

            <UniformGrid Grid.Row="4" Columns="3" Margin="0,0,-12,0">
              <Border BorderBrush="#141413" BorderThickness="0,1.5,0,0" Padding="0,10,0,0" Margin="0,0,12,0">
                <StackPanel>
                  <TextBlock Text="①" FontFamily="{StaticResource Serif}" FontSize="18" FontWeight="Black" Foreground="#A3401A"/>
                  <TextBlock Text="点「一键修复」" FontSize="13" Margin="0,4,0,0"/>
                </StackPanel>
              </Border>
              <Border BorderBrush="#141413" BorderThickness="0,1.5,0,0" Padding="0,10,0,0" Margin="0,0,12,0">
                <StackPanel>
                  <TextBlock Text="②" FontFamily="{StaticResource Serif}" FontSize="18" FontWeight="Black" Foreground="#A3401A"/>
                  <TextBlock Text="等待重建完成" FontSize="13" Margin="0,4,0,0"/>
                </StackPanel>
              </Border>
              <Border BorderBrush="#141413" BorderThickness="0,1.5,0,0" Padding="0,10,0,0" Margin="0,0,12,0">
                <StackPanel>
                  <TextBlock Text="③" FontFamily="{StaticResource Serif}" FontSize="18" FontWeight="Black" Foreground="#A3401A"/>
                  <TextBlock Text="Codex 自动重新打开" FontSize="13" Margin="0,4,0,0"/>
                </StackPanel>
              </Border>
            </UniformGrid>
            <TextBlock Grid.Row="5" Text="只重建 runtime 缓存，旧文件先备份；不动聊天记录和登录状态。" FontSize="12" Foreground="#4D4C48" TextWrapping="Wrap" Margin="0,12,0,0"/>
          </Grid>
        </Border>

        <!-- 问题二：Codex 登录失败 -->
        <Border Grid.Column="1" Background="#2D4A3E" BorderBrush="#141413" BorderThickness="1.5,0,0,0" Padding="32,24,32,22"
                TextElement.Foreground="#F7F1E3">
          <Grid>
            <Grid.RowDefinitions>
              <RowDefinition Height="Auto"/>
              <RowDefinition Height="Auto"/>
              <RowDefinition Height="Auto"/>
              <RowDefinition Height="*"/>
              <RowDefinition Height="Auto"/>
              <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>
            <StackPanel Grid.Row="0" Orientation="Horizontal">
              <Border Style="{StaticResource Tag}">
                <TextBlock Text="问题 二" FontFamily="{StaticResource Serif}" FontSize="14" FontWeight="Black" Foreground="#141413"/>
              </Border>
              <TextBlock Text="os error 10013" FontFamily="{StaticResource Mono}" FontSize="12" Foreground="#D3DDD0" Margin="10,0,0,0" VerticalAlignment="Center"/>
            </StackPanel>
            <TextBlock Grid.Row="1" Text="Codex 登录失败" FontFamily="{StaticResource Serif}" FontSize="42" FontWeight="Black" Margin="0,14,0,0"/>
            <TextBlock Grid.Row="2" Text="切换账号时提示 failed to start login server，浏览器弹不出来。" FontSize="14" Foreground="#D3DDD0" TextWrapping="Wrap" Margin="0,8,0,0"/>

            <StackPanel Grid.Row="3" Orientation="Horizontal" VerticalAlignment="Center">
              <Button x:Name="LoginToggle" Style="{StaticResource BigPill}" Background="#4A6B5C"
                      AutomationProperties.Name="登录模式开关">
                <Grid>
                  <Ellipse x:Name="ToggleKnob" Width="92" Height="92" Fill="#FAF9F5" Stroke="#141413" StrokeThickness="2"
                           HorizontalAlignment="Left" VerticalAlignment="Center" Margin="6,0,6,0"/>
                  <TextBlock x:Name="ToggleLabel" Text="关" FontFamily="{StaticResource Serif}" FontSize="44" FontWeight="Black"
                             Foreground="#F7F1E3" HorizontalAlignment="Right" VerticalAlignment="Center" Margin="30,0,32,4"/>
                </Grid>
              </Button>
              <StackPanel Margin="26,0,0,0" VerticalAlignment="Center" MaxWidth="190">
                <TextBlock x:Name="LoginStatus" Text="正在检测…" FontSize="14" FontWeight="Bold" Foreground="#F2C56B" TextWrapping="Wrap"/>
                <TextBlock x:Name="LoginDetail" Text="" FontSize="14" Foreground="#D3DDD0" TextWrapping="Wrap" Margin="0,4,0,0"/>
              </StackPanel>
            </StackPanel>

            <UniformGrid Grid.Row="4" Columns="3" Margin="0,0,-12,0">
              <Border BorderBrush="#F7F1E3" BorderThickness="0,1.5,0,0" Padding="0,10,0,0" Margin="0,0,12,0">
                <StackPanel>
                  <TextBlock Text="①" FontFamily="{StaticResource Serif}" FontSize="18" FontWeight="Black" Foreground="#F2C56B"/>
                  <TextBlock Text="打开开关" FontSize="13" Margin="0,4,0,0"/>
                </StackPanel>
              </Border>
              <Border BorderBrush="#F7F1E3" BorderThickness="0,1.5,0,0" Padding="0,10,0,0" Margin="0,0,12,0">
                <StackPanel>
                  <TextBlock Text="②" FontFamily="{StaticResource Serif}" FontSize="18" FontWeight="Black" Foreground="#F2C56B"/>
                  <TextBlock Text="去 Codex 继续登录" FontSize="13" TextWrapping="Wrap" Margin="0,4,0,0"/>
                </StackPanel>
              </Border>
              <Border BorderBrush="#F7F1E3" BorderThickness="0,1.5,0,0" Padding="0,10,0,0" Margin="0,0,12,0">
                <StackPanel>
                  <TextBlock Text="③" FontFamily="{StaticResource Serif}" FontSize="18" FontWeight="Black" Foreground="#F2C56B"/>
                  <TextBlock Text="登录成功后关掉" FontSize="13" Margin="0,4,0,0"/>
                </StackPanel>
              </Border>
            </UniformGrid>
            <TextBlock x:Name="LoginNote" Grid.Row="5" FontSize="12" Foreground="#D3DDD0" TextWrapping="Wrap" Margin="0,12,0,0"
                       Text="暂停期间 Docker / WSL2 网络可能中断；关掉开关、超时或退出程序都会自动恢复。"/>
          </Grid>
        </Border>
      </Grid>

      <!-- 底栏：最新一条工作记录 -->
      <Border Grid.Row="2" Background="#FAF9F5" CornerRadius="0,0,13,13" BorderBrush="#141413" BorderThickness="0,1.5,0,0" Padding="28,0,22,0">
        <DockPanel>
          <Button x:Name="LogButton" DockPanel.Dock="Right" Style="{StaticResource LinkButton}" Content="查看完整记录" FontSize="12" VerticalAlignment="Center"/>
          <TextBlock x:Name="FooterLog" Text="" FontFamily="{StaticResource Mono}" FontSize="12" Foreground="#3D3D3A"
                     VerticalAlignment="Center" TextTrimming="CharacterEllipsis" Margin="0,0,16,0"/>
        </DockPanel>
      </Border>
    </Grid>
  </Border>
</Window>
'@

$window = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))
$ui = @{}
foreach ($name in @(
    'TitleBar', 'AdminText', 'MinButton', 'CloseButton',
    'RepairButton', 'RepairLabel', 'RepairStatus', 'RepairDetail', 'CheckButton',
    'LoginToggle', 'ToggleKnob', 'ToggleLabel', 'LoginStatus', 'LoginDetail', 'LoginNote',
    'LogButton', 'FooterLog')) {
    $ui[$name] = $window.FindName($name)
}

function New-Brush([string]$Hex) {
    $brush = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString($Hex))
    $brush.Freeze()
    return $brush
}

$Colors = @{
    Ivory     = New-Brush '#FAF9F5'
    Ink       = New-Brush '#141413'
    Clay      = New-Brush '#A3401A'
    Rust      = New-Brush '#8A3313'
    Moss      = New-Brush '#2F5A2A'
    Body      = New-Brush '#3D3D3A'
    Cream     = New-Brush '#F7F1E3'
    Mist      = New-Brush '#D3DDD0'
    Gold      = New-Brush '#F2C56B'
    TrackOff  = New-Brush '#4A6B5C'
}

# ---------------------------------------------------------------- 工作记录
$script:LogLines = New-Object System.Collections.Generic.List[string]
$script:LogBox = $null

function Add-Log([string]$Message) {
    $line = '{0}  {1}' -f (Get-Date -Format 'HH:mm:ss'), $Message
    $script:LogLines.Add($line)
    $ui.FooterLog.Text = $line
    if ($null -ne $script:LogBox) {
        $script:LogBox.AppendText($line + [Environment]::NewLine)
        $script:LogBox.ScrollToEnd()
    }
}

function Show-LogWindow {
    if ($null -ne $script:LogWindow) {
        $script:LogWindow.Activate() | Out-Null
        return
    }

    $logXaml = [xml]@'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        Title="完整记录 · Codex 修复工具箱" Width="760" Height="460" Background="#FAF9F5"
        WindowStartupLocation="CenterOwner" FontFamily="Microsoft YaHei UI, Segoe UI">
  <Grid Margin="16">
    <TextBox x:Name="LogBox" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
             IsReadOnly="True" TextWrapping="NoWrap" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto"
             FontFamily="Cascadia Mono, Consolas" FontSize="12" Background="#FFFFFF" BorderBrush="#141413" BorderThickness="1.5" Padding="10"/>
  </Grid>
</Window>
'@
    $script:LogWindow = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $logXaml))
    $script:LogWindow.Owner = $window
    $script:LogBox = $script:LogWindow.FindName('LogBox')
    $script:LogBox.Text = (($script:LogLines -join [Environment]::NewLine) + [Environment]::NewLine)
    $script:LogBox.ScrollToEnd()
    $script:LogWindow.add_Closed({
        $script:LogWindow = $null
        $script:LogBox = $null
    })
    $script:LogWindow.Show()
}
$script:LogWindow = $null

function Update-Ui {
    # 让「正在…」之类的提示在同步操作前先画出来。
    $window.Dispatcher.Invoke([Action]{}, [System.Windows.Threading.DispatcherPriority]::Render)
}

# ---------------------------------------------------------------- 问题一：runtime 缓存
$script:RepairState = 'Idle'   # Idle | Busy | Done | Failed
$script:RepairPs = $null
$script:RepairHandle = $null
$script:RepairRunspace = $null
$script:RepairSeen = 0
$script:RepairIsDryRun = $false
$script:CodexInstalled = $true

function Get-RuntimeStatus {
    $package = $null
    try {
        $package = Get-AppxPackage -Name OpenAI.Codex -ErrorAction Stop | Sort-Object Version -Descending | Select-Object -First 1
    } catch {
    }

    $runtimeRoot = Join-Path $env:LOCALAPPDATA 'OpenAI\Codex\runtimes\cua_node'
    $stagingCount = 0
    if (Test-Path -LiteralPath $runtimeRoot) {
        $stagingCount = @(Get-ChildItem -LiteralPath $runtimeRoot -Force -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '^\.staging-' }).Count
    }

    $version = $null
    if ($null -ne $package) { $version = [string]$package.Version }

    return [pscustomobject]@{
        Installed    = ($null -ne $package)
        Version      = $version
        StagingCount = $stagingCount
    }
}

function Set-RepairButton([string]$Label, $Background, $Foreground, [bool]$Enabled) {
    $ui.RepairLabel.Text = $Label
    $ui.RepairButton.Background = $Background
    $ui.RepairButton.Foreground = $Foreground
    $ui.RepairButton.IsEnabled = $Enabled
}

function Update-RuntimeView([switch]$Quiet) {
    $status = Get-RuntimeStatus
    $script:CodexInstalled = $status.Installed

    if ($script:RepairState -eq 'Busy') { return }

    if (-not $status.Installed) {
        Set-RepairButton '一键修复' $Colors.Clay $Colors.Ivory $false
        $ui.CheckButton.IsEnabled = $false
        $ui.RepairStatus.Text = '未检测到 Codex'
        $ui.RepairStatus.Foreground = $Colors.Rust
        $ui.RepairDetail.Text = '只支持 Microsoft Store 安装的 Codex 桌面版'
        if (-not $Quiet) { Add-Log '未检测到 OpenAI.Codex（Microsoft Store 版）' }
        return
    }

    $ui.CheckButton.IsEnabled = $true

    if ($script:RepairState -eq 'Done') {
        Set-RepairButton '已修复' $Colors.Ivory $Colors.Moss $true
        $ui.RepairStatus.Text = 'runtime 已重建'
        $ui.RepairStatus.Foreground = $Colors.Moss
        $ui.RepairDetail.Text = 'Codex 已重新启动'
        return
    }

    if ($script:RepairState -eq 'Failed') {
        Set-RepairButton '再试一次' $Colors.Clay $Colors.Ivory $true
        $ui.RepairStatus.Text = '修复没有完成'
        $ui.RepairStatus.Foreground = $Colors.Rust
        $ui.RepairDetail.Text = '点底部「查看完整记录」看原因'
        return
    }

    Set-RepairButton '一键修复' $Colors.Clay $Colors.Ivory $true
    if ($status.StagingCount -gt 0) {
        $ui.RepairStatus.Text = "发现 $($status.StagingCount) 个未完成目录"
        $ui.RepairStatus.Foreground = $Colors.Rust
        $ui.RepairDetail.Text = 'Codex 可能一直卡在启动'
    } else {
        $ui.RepairStatus.Text = '未发现启动问题'
        $ui.RepairStatus.Foreground = $Colors.Moss
        $ui.RepairDetail.Text = 'Codex 打不开时再点修复'
    }

    if (-not $Quiet) {
        Add-Log ("检测到 OpenAI.Codex {0}，未完成的 runtime 目录：{1} 个" -f $status.Version, $status.StagingCount)
    }
}

$RepairTimer = New-Object System.Windows.Threading.DispatcherTimer
$RepairTimer.Interval = [TimeSpan]::FromMilliseconds(300)

function Start-RuntimeRepair([switch]$DryRun) {
    if ($script:RepairState -eq 'Busy') { return }

    $iss = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
    $iss.ExecutionPolicy = [Microsoft.PowerShell.ExecutionPolicy]::Bypass
    $script:RepairRunspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($iss)
    $script:RepairRunspace.Open()

    $script:RepairPs = [System.Management.Automation.PowerShell]::Create()
    $script:RepairPs.Runspace = $script:RepairRunspace
    [void]$script:RepairPs.AddCommand($RepairScript)
    if (-not $DryRun) {
        [void]$script:RepairPs.AddParameter('Apply')
        [void]$script:RepairPs.AddParameter('Yes')
    }

    $script:RepairIsDryRun = [bool]$DryRun
    $script:RepairSeen = 0
    $script:RepairState = 'Busy'

    if ($DryRun) {
        Add-Log '开始检查 runtime 缓存（dry-run，不改任何文件）'
        $ui.CheckButton.IsEnabled = $false
        $ui.RepairButton.IsEnabled = $false
    } else {
        Add-Log '开始修复 runtime 缓存'
        Set-RepairButton '修复中…' $Colors.Clay $Colors.Ivory $false
        $ui.CheckButton.IsEnabled = $false
        $ui.RepairStatus.Text = '正在重建 runtime'
        $ui.RepairStatus.Foreground = $Colors.Rust
        $ui.RepairDetail.Text = '大约需要一两分钟，请不要关闭'
    }

    $script:RepairHandle = $script:RepairPs.BeginInvoke()
    $RepairTimer.Start()
}

function Receive-RepairOutput {
    $info = $script:RepairPs.Streams.Information
    while ($script:RepairSeen -lt $info.Count) {
        $message = [string]$info[$script:RepairSeen].MessageData
        if (-not [string]::IsNullOrWhiteSpace($message)) { Add-Log $message.Trim() }
        $script:RepairSeen++
    }
}

$RepairTimer.add_Tick({
    if ($null -eq $script:RepairPs) { $RepairTimer.Stop(); return }
    Receive-RepairOutput
    if (-not $script:RepairHandle.IsCompleted) { return }

    $RepairTimer.Stop()
    $failure = $null
    try {
        [void]$script:RepairPs.EndInvoke($script:RepairHandle)
    } catch {
        $failure = $_.Exception
        while ($null -ne $failure.InnerException) { $failure = $failure.InnerException }
    }
    Receive-RepairOutput

    # 原脚本在「没有 .staging 目录」时会抛错退出（此时还没动任何文件）。
    # 对用户来说这代表「目前不需要这项修复」，不算失败。
    $nothingToRepair = ($null -ne $failure) -and ($failure.Message -match 'No \.staging-')

    if (-not $nothingToRepair) {
        foreach ($err in $script:RepairPs.Streams.Error) { Add-Log ("错误：{0}" -f $err) }
        if ($null -ne $failure) { Add-Log ("错误：{0}" -f $failure.Message) }
    }

    $ok = ($null -eq $failure) -and -not $script:RepairPs.HadErrors
    $dryRun = $script:RepairIsDryRun

    $script:RepairPs.Dispose()
    $script:RepairRunspace.Dispose()
    $script:RepairPs = $null
    $script:RepairRunspace = $null

    if ($nothingToRepair) {
        $script:RepairState = 'Idle'
        Add-Log '没有发现未完成的 .staging 目录，目前不需要修复，也没有修改任何文件'
        Add-Log '如果 Codex 之后卡在启动，先打开一次 Codex 等它卡住，再回来点「一键修复」'
        if ($dryRun) { Show-LogWindow }
    } elseif ($dryRun) {
        $script:RepairState = 'Idle'
        Add-Log ($(if ($ok) { '检查完成，没有修改任何文件' } else { '检查没有完成' }))
        Show-LogWindow
    } elseif ($ok) {
        $script:RepairState = 'Done'
        Add-Log 'runtime 修复完成'
    } else {
        $script:RepairState = 'Failed'
        Add-Log 'runtime 修复没有完成'
    }
    Update-RuntimeView -Quiet
})

$ui.RepairButton.add_Click({
    $question = "将要执行：`n`n" +
        "1. 关闭 Codex 桌面端（只关 OpenAI.Codex 的 ChatGPT.exe 进程）`n" +
        "2. 把未完成的 .staging 目录移到带时间戳的备份目录`n" +
        "3. 从 Codex 安装包重建 runtime 缓存并校验`n" +
        "4. 重新打开 Codex`n`n" +
        "不会删除文件，不动聊天记录、登录状态和 Windows 设置。继续吗？"
    $answer = [System.Windows.MessageBox]::Show($window, $question, '一键修复 Codex 启动问题', 'YesNo', 'Question')
    if ($answer -eq 'Yes') { Start-RuntimeRepair }
})

$ui.CheckButton.add_Click({ Start-RuntimeRepair -DryRun })

# ---------------------------------------------------------------- 问题二：登录修复（WinNAT）
$script:LoginOn = $false
$script:WeStopped = $false
$script:Deadline = $null
$script:WinNatExists = $true

$CountdownTimer = New-Object System.Windows.Threading.DispatcherTimer
$CountdownTimer.Interval = [TimeSpan]::FromSeconds(1)

function Set-ToggleVisual([bool]$On) {
    if ($On) {
        $ui.LoginToggle.Background = $Colors.Gold
        $ui.ToggleKnob.HorizontalAlignment = 'Right'
        $ui.ToggleLabel.Text = '开'
        $ui.ToggleLabel.Foreground = $Colors.Ink
        $ui.ToggleLabel.HorizontalAlignment = 'Left'
    } else {
        $ui.LoginToggle.Background = $Colors.TrackOff
        $ui.ToggleKnob.HorizontalAlignment = 'Left'
        $ui.ToggleLabel.Text = '关'
        $ui.ToggleLabel.Foreground = $Colors.Cream
        $ui.ToggleLabel.HorizontalAlignment = 'Right'
    }
    $ui.LoginToggle.SetValue([System.Windows.Automation.AutomationProperties]::NameProperty, $(if ($On) { '登录模式：已开启' } else { '登录模式：已关闭' }))
}

function Format-Remaining {
    if ($null -eq $script:Deadline) { return '' }
    $left = $script:Deadline - (Get-Date)
    if ($left.TotalSeconds -lt 0) { $left = [TimeSpan]::Zero }
    return ('{0} 分 {1:00} 秒后自动恢复' -f [int][math]::Floor($left.TotalMinutes), $left.Seconds)
}

function Get-PortText($Port) {
    switch ($Port.State) {
        'Free'     { return '端口 1455 可用' }
        'Reserved' { return '端口 1455 被系统保留' }
        'InUse'    {
            if ($Port.Owner) { return "端口 1455 被 $($Port.Owner) 占用" }
            return '端口 1455 被其他程序占用'
        }
        default    { return "端口 1455 检测失败（$($Port.ErrorCode)）" }
    }
}

function Update-LoginView($Status) {
    if ($null -eq $Status) { $Status = Get-CodexLoginModeStatus }

    $script:WinNatExists = $Status.WinNat.Exists
    $script:LoginOn = [bool]$Status.LoginModeOn
    Set-ToggleVisual $script:LoginOn
    $ui.LoginToggle.IsEnabled = $Status.WinNat.Exists

    if (-not $Status.WinNat.Exists) {
        $ui.LoginStatus.Text = '未找到 WinNAT 服务'
        $ui.LoginDetail.Text = '10013 可能另有原因：' + (Get-PortText $Status.Port)
        return
    }

    if ($script:LoginOn) {
        $ui.LoginStatus.Text = 'WinNAT 已暂停'
        if ($script:WeStopped) {
            $detail = Format-Remaining
        } else {
            $detail = '不是本工具停止的，不会自动恢复'
        }
        if ($Status.Port.State -ne 'Free') { $detail = (Get-PortText $Status.Port) + '；' + $detail }
        $ui.LoginDetail.Text = $detail
        return
    }

    $ui.LoginStatus.Text = Get-PortText $Status.Port
    switch ($Status.Port.State) {
        'Free'     { $ui.LoginDetail.Text = '现在可以直接登录；登录失败再打开开关' }
        'Reserved' { $ui.LoginDetail.Text = '现在登录大概率失败，打开开关再登录' }
        'InUse'    { $ui.LoginDetail.Text = '可能是上一次登录还没退出，先关掉它' }
        default    { $ui.LoginDetail.Text = '可以先打开开关再试' }
    }
}

function Write-LoginLog($Status, [string]$Prefix) {
    $winNat = if ($Status.WinNat.Exists) { $Status.WinNat.Status } else { '未安装' }
    $range = if ($Status.Port.ExcludedRange) { "，位于系统保留范围 $($Status.Port.ExcludedRange)" } else { '' }
    Add-Log ("{0}WinNAT：{1}；{2}{3}" -f $Prefix, $winNat, (Get-PortText $Status.Port), $range)
}

function Invoke-LoginModeOn {
    $ui.LoginStatus.Text = '正在暂停 WinNAT…'
    $ui.LoginDetail.Text = ''
    Update-Ui
    try {
        $status = Enable-CodexLoginMode
        $script:WeStopped = $true
        $script:Deadline = (Get-Date).AddMinutes($AutoRestoreMinutes)
        $CountdownTimer.Start()
        Write-LoginLog $status 'net stop winnat 成功。'
        Add-Log '现在去 Codex 点「继续登录」，登录成功后回来关掉开关'
        Update-LoginView $status
    } catch {
        Add-Log ("暂停 WinNAT 失败：{0}" -f $_.Exception.Message)
        [System.Windows.MessageBox]::Show($window, "暂停 WinNAT 失败：`n`n$($_.Exception.Message)", '登录修复', 'OK', 'Warning') | Out-Null
        Update-LoginView $null
    }
}

function Invoke-LoginModeOff([string]$Reason) {
    $ui.LoginStatus.Text = '正在恢复 WinNAT…'
    $ui.LoginDetail.Text = ''
    Update-Ui
    try {
        $status = Disable-CodexLoginMode
        $CountdownTimer.Stop()
        $script:WeStopped = $false
        $script:Deadline = $null
        Write-LoginLog $status ("net start winnat 成功（{0}）。" -f $Reason)
        Update-LoginView $status
        return $true
    } catch {
        Add-Log ("恢复 WinNAT 失败：{0}" -f $_.Exception.Message)
        [System.Windows.MessageBox]::Show($window, "恢复 WinNAT 失败：`n`n$($_.Exception.Message)`n`n可以在管理员 PowerShell 里手动执行：net start winnat", '登录修复', 'OK', 'Warning') | Out-Null
        Update-LoginView $null
        return $false
    }
}

$CountdownTimer.add_Tick({
    if (-not $script:WeStopped -or $null -eq $script:Deadline) { $CountdownTimer.Stop(); return }
    if ((Get-Date) -ge $script:Deadline) {
        [void](Invoke-LoginModeOff '超时自动恢复')
        return
    }
    $ui.LoginDetail.Text = Format-Remaining
})

$ui.LoginToggle.add_Click({
    if (-not $script:IsAdmin) {
        [System.Windows.MessageBox]::Show($window, "暂停和恢复 WinNAT 需要管理员权限。`n`n请关闭本窗口，重新双击启动器，并在弹出的权限提示里点「是」。", '需要管理员权限', 'OK', 'Information') | Out-Null
        return
    }
    if ($script:LoginOn) {
        [void](Invoke-LoginModeOff '手动关闭')
    } else {
        Invoke-LoginModeOn
    }
})

# ---------------------------------------------------------------- 窗口
$ui.TitleBar.add_MouseLeftButtonDown({ $window.DragMove() })
$ui.MinButton.add_Click({ $window.WindowState = 'Minimized' })
$ui.CloseButton.add_Click({ $window.Close() })
$ui.LogButton.add_Click({ Show-LogWindow })

$window.add_Closing({
    param($sender, $e)

    if ($script:RepairState -eq 'Busy') {
        $answer = [System.Windows.MessageBox]::Show($window, '修复还在进行中，现在退出会中断修复（旧文件已备份）。确定退出吗？', 'Codex 修复工具箱', 'YesNo', 'Warning')
        if ($answer -ne 'Yes') { $e.Cancel = $true; return }
        try { $script:RepairPs.Stop() } catch { }
    }

    if ($script:WeStopped) {
        $restored = Invoke-LoginModeOff '退出程序'
        if (-not $restored) {
            $answer = [System.Windows.MessageBox]::Show($window, 'WinNAT 没能自动恢复。仍要退出吗？（之后可手动执行 net start winnat）', 'Codex 修复工具箱', 'YesNo', 'Warning')
            if ($answer -ne 'Yes') { $e.Cancel = $true }
        }
    }
})

if ($script:IsAdmin) {
    $ui.AdminText.Text = '管理员'
} else {
    $ui.AdminText.Text = '普通权限'
    $ui.AdminText.Parent.ToolTip = '登录修复开关需要管理员权限'
}

# ---------------------------------------------------------------- 预览渲染（开发用）
if ($RenderPreview) {
    $ui.FooterLog.Text = '10:21:04  检测到 OpenAI.Codex，未完成的 runtime 目录：3 个'
    $ui.RepairStatus.Text = '发现 3 个未完成目录'
    $ui.RepairStatus.Foreground = $Colors.Rust
    $ui.RepairDetail.Text = 'Codex 可能一直卡在启动'
    $ui.LoginStatus.Text = '端口 1455 被系统保留'
    $ui.LoginDetail.Text = '现在登录大概率失败，打开开关再登录'
    $ui.AdminText.Text = '管理员'

    if ($PreviewState -eq 'LoginOn') {
        Set-ToggleVisual $true
        $ui.LoginStatus.Text = 'WinNAT 已暂停'
        $ui.LoginDetail.Text = '9 分 42 秒后自动恢复'
        $ui.FooterLog.Text = '10:22:31  net stop winnat 成功。WinNAT：Stopped；端口 1455 可用'
    }
    if ($PreviewState -eq 'Repaired') {
        Set-RepairButton '已修复' $Colors.Ivory $Colors.Moss $true
        $ui.RepairStatus.Text = 'runtime 已重建'
        $ui.RepairStatus.Foreground = $Colors.Moss
        $ui.RepairDetail.Text = 'Codex 已重新启动'
        $ui.FooterLog.Text = '10:23:12  runtime 修复完成'
    }
    if ($PreviewState -eq 'Live') {
        # 用本机的真实检测结果填充界面（只读，不改任何东西）。
        $ui.AdminText.Text = $(if ($script:IsAdmin) { '管理员' } else { '普通权限' })
        Update-RuntimeView
        $liveStatus = Get-CodexLoginModeStatus
        Write-LoginLog $liveStatus '登录检测：'
        Update-LoginView $liveStatus
    }

    $root = $window.Content
    $window.Content = $null
    $size = New-Object System.Windows.Size 1040, 680
    $root.Measure($size)
    $root.Arrange((New-Object System.Windows.Rect 0, 0, 1040, 680))
    $root.UpdateLayout()
    $bitmap = New-Object System.Windows.Media.Imaging.RenderTargetBitmap 2080, 1360, 192, 192, ([System.Windows.Media.PixelFormats]::Pbgra32)
    $bitmap.Render($root)
    $encoder = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
    $encoder.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
    $stream = [System.IO.File]::Create($RenderPreview)
    try { $encoder.Save($stream) } finally { $stream.Dispose() }
    Write-Host "preview written: $RenderPreview"
    exit 0
}

# ---------------------------------------------------------------- 启动
$window.add_ContentRendered({
    Update-RuntimeView

    $status = Get-CodexLoginModeStatus
    if ($status.StoppedByTool) {
        # 上次运行时暂停了 WinNAT 但没来得及恢复（例如程序被强制结束）。
        $script:WeStopped = $true
        $script:Deadline = (Get-Date).AddMinutes($AutoRestoreMinutes)
        $CountdownTimer.Start()
        Add-Log ("发现上次暂停的 WinNAT 还没恢复，将在 {0} 分钟后自动恢复" -f $AutoRestoreMinutes)
    }
    Write-LoginLog $status '登录检测：'
    Update-LoginView $status

    if (-not $script:IsAdmin) {
        Add-Log '当前是普通权限：登录修复开关需要以管理员身份运行'
    }
})

[void]$window.ShowDialog()
