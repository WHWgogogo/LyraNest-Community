# 部署验收

`scripts/verify-deployment.ps1` 通过公开 HTTP 接口验证 LyraNest Community（律巢社区版）的部署状态。脚本只读取数据，唯一的写操作是调用一次 `POST /api/v1/library/scan` 来验证音乐库扫描端点；它不会调用任何 scrape apply 接口。

## 运行

默认目标是 `http://192.168.0.107:8080`，默认跳过外部抓取搜索：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify-deployment.ps1
```

指定部署地址与预期曲目数量：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify-deployment.ps1 `
  -BaseUrl 'http://192.168.0.107:8080' `
  -ExpectedTrackCount 42
```

当部署环境允许访问抓取上游时，可启用只读的 scrape 搜索验证。脚本只会对首曲调用 `POST /api/v1/tracks/{id}/scrape/search`，绝不会调用 `/scrape/apply`：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify-deployment.ps1 `
  -BaseUrl 'http://192.168.0.107:8080' `
  -SkipScrape:$false
```

## 参数

- `BaseUrl`：待验收服务的 HTTP/HTTPS 根地址，默认 `http://192.168.0.107:8080`。
- `TimeoutSeconds`：每个 HTTP 请求的超时，默认 `30`。
- `MaximumResponseBytes`：根页面和 JSON 响应的最大响应体大小，默认 `1048576` 字节；完整音频 GET 仅验证响应头，避免下载整首歌曲。
- `LyricsSampleSize`：检查歌词的前 N 首曲目数量，默认 `10`。
- `ExpectedTrackCount`：大于零时，要求曲目列表数量精确匹配该值；默认 `0` 表示不额外限制数量。
- `SkipScrape`：是否跳过抓取搜索，默认 `$true`；接受 `$true`/`$false`、`true`/`false` 或 `1`/`0`。

## 验收项目

脚本按服务实际 API 协议执行下列检查：

1. `GET /` 使用 `Accept: text/html`，返回 `200`、`text/html` 和非空页面。
2. `GET /healthz` 返回 `200` 与 JSON `status: "ok"`。
3. `GET /api/v1/tracks` 返回非空曲目列表；`total` 与列表长度一致，且所有曲目 `id` 非空且唯一。
4. 首曲 `/stream` 的 `GET`、`HEAD` 和 `Range: bytes=0-0` 请求分别返回 `200`、`200` 和 `206`；Range 响应必须具有有效 `Content-Range`。
5. 对前 `LyricsSampleSize` 首曲的歌词端点，`404` 代表该曲无歌词且合法；至少一首必须返回 `200` 且 `content` 非空。
6. `GET /api/v1/library/status` 返回与曲目列表一致的数量且不处于扫描中。
7. `POST /api/v1/library/scan` 返回成功、非空且 ID 唯一的扫描结果；随后再次确认库状态。
8. 当 `SkipScrape` 为 `$false` 时，对首曲执行 scrape 搜索并验证返回的 `track_id`；不调用 apply。

## 结果与退出码

每项会输出 `[PASS]`、`[FAIL]` 或 `[INFO]`。全部通过时末行是 `PASS: ...`，进程退出码为 `0`；任一检查、解析或网络请求失败时末行是 `FAIL: ...`，进程退出码为 `1`，可直接用于部署流水线。

脚本兼容 Windows PowerShell 5.1，不依赖 PowerShell 7 的 Web cmdlet 参数。
