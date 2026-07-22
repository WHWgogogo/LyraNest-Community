# Windows/Android 客户端构建与交付

Flutter 客户端位于 `apps/player`，默认服务地址为：

```text
http://192.168.0.107:8080
```

## 一键构建

在仓库根目录执行：

```powershell
.\scripts\build-clients.ps1
```

覆盖默认服务地址：

```powershell
.\scripts\build-clients.ps1 -DefaultServerUrl "http://192.168.0.107:8080"
```

脚本会传入：

```text
--dart-define=DEFAULT_SERVER_URL=<DefaultServerUrl>
```

仓库路径包含非 ASCII 字符时，脚本会把 `apps/player` 源文件复制到
`C:\hmb\b-<8位十六进制ID>` 专用短路径工作区，并复制
`dist/build-cache/media-kit/android-audio/v1.1.8` 缓存后构建。短根路径用于避免
MSVC 的 260 字符 tlog/中间目录限制。原仓库只提供源码和持久缓存，Flutter 生成文件
不会写回客户端源码目录。脚本仍会通过临时 `subst` 盘符复用原仓库的 Gradle 缓存。

脚本会先在工作区执行 `flutter clean`，避免旧 CMakeCache 污染本次 Windows 构建；
该操作不会删除原仓库的 `dist/build-cache`。随后依次执行 Windows 与 Android release
构建，并在打包完成后删除临时工作区。清理前会验证目标绝对路径位于专用
`C:\hmb` 根目录内且目录名严格匹配 `b-<8位十六进制ID>`。

已知 Windows 构建环境可按以下方式显式配置后执行：

```powershell
$env:Path = 'C:\Users\admin\development\flutter\bin;' + $env:Path
$env:JAVA_HOME = 'C:\Program Files\Android\Android Studio\jbr'
$env:ANDROID_SDK_ROOT = 'C:\Users\admin\AppData\Local\Android\Sdk'
$env:ANDROID_HOME = $env:ANDROID_SDK_ROOT

powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\build-clients.ps1 `
  -DefaultServerUrl 'http://192.168.0.107:8080'
```

Windows PowerShell 5.1 在 `$ErrorActionPreference = 'Stop'` 时，直接执行
`java -version 2>&1` 会把 Java 写入 stderr 的正常版本信息转换为
`NativeCommandError`。构建脚本通过 `System.Diagnostics.Process` 分离捕获 stdout、
stderr 和退出码，不依赖 PowerShell 的原生命令错误流转换。

## Windows media_kit 原生缓存

`media_kit_libs_windows_audio 1.0.9` 的 Windows CMake 项目使用以下官方产物：

```text
https://github.com/media-kit/libmpv-win32-audio-build/releases/download/2023-09-24/mpv-dev-x86_64-20230924-git-652a1dd.7z
```

上游插件内置 MD5 为 `cd738e16e2a19626d7cfa48801524f8c`。项目同时固定文件大小和
SHA256：

```text
Size: 5392413 bytes
SHA256: 583af5a291fc99ae2641794ede1955c368eb4c19dc05f4f0a9c7f9456edeb6a8
```

持久缓存位置：

```text
dist/build-cache/media-kit/windows-audio/2023-09-24/mpv-dev-x86_64-20230924-git-652a1dd.7z
```

在线获取并校验官方产物：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\cache-media-kit-windows.ps1
```

仅使用本机已有可信产物：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\cache-media-kit-windows.ps1 -Offline
```

从指定离线目录导入：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\cache-media-kit-windows.ps1 `
  -Offline `
  -SourceDirectory D:\trusted-cache\media-kit-windows
```

通过代理访问官方 GitHub：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\cache-media-kit-windows.ps1 `
  -Proxy http://127.0.0.1:7890
```

使用组织批准的 HTTPS 镜像：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\cache-media-kit-windows.ps1 `
  -BaseUrl https://mirror.example.com/media-kit/libmpv-win32-audio-build/2023-09-24
```

缓存脚本会拒绝大小、SHA256 或 MD5 任一不匹配的文件，并清理持久缓存或旧构建目录中的
损坏副本。`build-clients.ps1` 在构建前以 `-Offline` 模式校验 Windows 与 Android
缓存；Windows 缓存会在 `flutter clean` 后复制到 `build/windows/x64`，因此 CMake
不会在构建期下载文件。

## Android media_kit 原生缓存

`media_kit_libs_android_audio 1.3.8` 的 Gradle 项目原本在配置期间执行
`:media_kit_libs_android_audio:downloadDependencies`，从 GitHub Release 下载四个
`libmpv-android-audio-build v1.1.8` JAR。网络不可达时会长时间阻塞；在 Gradle 9
中，该插件声明的空 `Exec` task 还会以 `command 'null'` 失败。

项目现在使用可复用缓存：

```text
dist/build-cache/media-kit/android-audio/v1.1.8
```

构建前从仓库根目录执行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\cache-media-kit.ps1
```

脚本会按以下顺序取得文件：

1. 已存在且校验通过的持久缓存。
2. `-SourceDirectory` 指定的离线可信目录。
3. 旧构建目录 `apps/player/build/media_kit_libs_android_audio/v1.1.8` 或 `output`。
4. 官方 GitHub Release，或 `-BaseUrl` 指定的组织可信 HTTPS 镜像。

仅使用本机已有可信产物，不访问网络：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\cache-media-kit.ps1 -Offline
```

从指定离线目录导入：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\cache-media-kit.ps1 `
  -Offline `
  -SourceDirectory D:\trusted-cache\libmpv-android-audio-build\v1.1.8
```

通过 HTTP/HTTPS 代理访问官方 GitHub：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\cache-media-kit.ps1 `
  -Proxy http://127.0.0.1:7890
```

使用组织批准的 HTTPS 镜像时，镜像目录必须直接包含四个同名 JAR：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\cache-media-kit.ps1 `
  -BaseUrl https://mirror.example.com/media-kit/libmpv-android-audio-build/v1.1.8
```

`-BaseUrl` 必须使用 HTTPS。无论文件来自本地、官方地址、代理还是镜像，脚本都会同时
校验固定 SHA256 和上游插件内置 MD5；Gradle 构建还会再次校验 SHA256。校验不匹配时
立即失败，不允许绕过。

如需把缓存放到其他目录，可使用 Gradle property 或环境变量：

```powershell
$env:MEDIA_KIT_ANDROID_AUDIO_CACHE_DIR = 'D:\trusted-cache\media-kit\android-audio'
```

或：

```powershell
.\apps\player\android\gradlew.bat `
  -PmediaKitAndroidAudioCacheDir=D:\trusted-cache\media-kit\android-audio `
  assembleRelease
```

缓存根目录下仍需包含 `v1.1.8` 子目录。

## 上游 URL 与校验值

原始下载地址：

```text
https://github.com/media-kit/libmpv-android-audio-build/releases/download/v1.1.8/default-arm64-v8a.jar
https://github.com/media-kit/libmpv-android-audio-build/releases/download/v1.1.8/default-armeabi-v7a.jar
https://github.com/media-kit/libmpv-android-audio-build/releases/download/v1.1.8/default-x86_64.jar
https://github.com/media-kit/libmpv-android-audio-build/releases/download/v1.1.8/default-x86.jar
```

固定 SHA256：

```text
0481a64b5e246774da22573d7a4e67f9fb3d89a68630864d8819d3ff3a08bb09  default-arm64-v8a.jar
1bba852f5b7f0098c54ab8c3a945866d2b730b9e146b472a6ffaa80fc0dceae9  default-armeabi-v7a.jar
ddffa0465e2dbb42d52937dae08516dbe07c534d489e9ea995f36a02d31a7106  default-x86_64.jar
824deeee316dfa3085832c6308e2953425bd428ba7eeeefd59bb51101b7ce8b7  default-x86.jar
```

Gradle 会把 `media_kit_libs_android_audio` 的 `buildDir` 指向持久缓存。插件配置期仍会执行
其原有 MD5 校验并把 JAR 复制到 `output`，因此真实播放库会正常打入 AAR/APK；仅跳过无
命令且没有实际下载逻辑的空 `Exec` task。

## Android release 命令

确保 Flutter、JDK 17+ 和 Android SDK 可用后，在 `apps/player` 执行：

```powershell
flutter build apk --release --dart-define=DEFAULT_SERVER_URL=http://192.168.0.107:8080
```

仓库路径包含中文和空格时，Android Gradle 配置已启用路径检查兼容项；一键构建脚本会
在 ASCII 临时工作区中执行 Windows 与 Android 构建。

成功产物：

```text
apps/player/build/app/outputs/flutter-apk/app-release.apk
```

## 交付打包

一键构建成功后会调用：

```powershell
.\scripts\package-delivery.ps1
```

也可在已有 release 产物时单独执行。交付文件输出到：

```text
dist/delivery
```

包含 Windows release ZIP、Android APK 和 `SHA256SUMS.txt`。校验文件使用无 BOM 的
ASCII 编码，打包日志同时输出两个产物的绝对路径、字节数与 SHA256。

## 工具链要求

- Flutter SDK，`flutter` 可在 `PATH` 中执行。
- JDK 17 或更高版本，配置 `JAVA_HOME` 或 `java`。
- Android SDK，包含 `platforms`、`build-tools`、`platform-tools`。
- Windows 构建需要 Visual Studio 2022/Build Tools 的“使用 C++ 的桌面开发”工作负载。

## PowerShell 语法检查

```powershell
$files = @(
  '.\scripts\build-clients.ps1',
  '.\scripts\cache-media-kit.ps1',
  '.\scripts\cache-media-kit-windows.ps1',
  '.\scripts\package-delivery.ps1'
)

foreach ($file in $files) {
  $errors = $null
  [System.Management.Automation.Language.Parser]::ParseFile(
    (Resolve-Path $file),
    [ref]$null,
    [ref]$errors
  ) | Out-Null
  if ($errors.Count) {
    $errors | Format-List
    exit 1
  }
}
```
