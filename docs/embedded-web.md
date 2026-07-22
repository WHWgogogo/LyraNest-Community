# 单端口嵌入式 Web 资源

`server/internal/webui` 使用 `go:embed` 将 Web 构建产物编译进 Go 二进制。服务端可以在同一个 `8080` 端口提供 UI 与 API，运行时不需要挂载 `apps/web/dist`，也不依赖 nginx 镜像，适合 scratch 单二进制部署。

## 构建并同步资源

从仓库根目录运行：

```powershell
.\scripts\embed-web-assets.ps1
```

脚本按顺序在 `apps/web` 执行：

```text
npm.cmd install
npm.cmd test
npm.cmd run build
```

如需跳过 Web 测试：

```powershell
.\scripts\embed-web-assets.ps1 -SkipTest
```

构建成功且确认 `apps/web/dist/index.html` 存在后，脚本才会清空并复制资源到 `server/internal/webui/dist`。删除前会将目标转换为绝对路径，并验证目标严格等于工作区内的 `server/internal/webui/dist`；目标目录或其直接子项若为 reparse point，脚本会拒绝删除。

## 占位资源

仓库保留 `server/internal/webui/dist/index.html` 作为最小占位文件。因此即使尚未运行 Web 构建，`go:embed` 仍有可匹配文件，`go test` 和 `go build` 可以正常编译。运行同步脚本后，占位文件会被真实 Vite 构建产物覆盖。

## HTTP 行为

`webui.NewHandler()` 返回独立的 `http.Handler`：

- `/` 和 `/index.html` 返回应用入口，并使用 `Cache-Control: no-cache`。
- 已存在的静态文件按扩展名返回正确 MIME；带 Vite 内容哈希的文件使用一年 `immutable` 缓存，其他静态文件使用一小时缓存。
- 不存在的无扩展名页面路径回退到 `index.html`，支持 SPA history 路由。
- 不存在的 `/assets/...` 或其他带扩展名的文件请求返回 `404`，不会错误返回应用入口。
- `/api`、`/api/...`、`/healthz` 和 `/healthz/...` 即使误传给 Web Handler 也返回 `404`，不会被 SPA fallback 吞掉。
- 仅接受 `GET` 和 `HEAD`；其他方法返回 `405`。

## 路由集成

主服务应让 API 路由优先于 Web 根路由，例如：

```go
apiHandler := handler.Routes()
mux := http.NewServeMux()
mux.Handle("/api/", apiHandler)
mux.Handle("/healthz", apiHandler)
mux.Handle("/", webui.NewHandler())
```

这样 `/api/v1/...` 与 `/healthz` 继续进入现有 API Handler，其余请求由嵌入式 Web Handler 处理。

## 验证

Go 包格式和测试：

```powershell
Set-Location .\server
gofmt -d .\internal\webui
go test .\internal\webui
```

PowerShell 脚本语法：

```powershell
$tokens = $null
$errors = $null
[System.Management.Automation.Language.Parser]::ParseFile(
    (Resolve-Path .\scripts\embed-web-assets.ps1),
    [ref]$tokens,
    [ref]$errors
) | Out-Null
if ($errors.Count) { $errors | Format-List; exit 1 }
```
