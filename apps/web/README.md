# LyraNest Web

LyraNest（律巢）的 Web 前端，使用 React、TypeScript 与 Vite 构建。默认通过同源 `/api` 与 `/healthz` 代理访问后端，也支持在界面里配置自定义服务器 URL。

## 本地运行

```bash
npm install
npm run dev
```

开发代理默认指向 `http://127.0.0.1:8080`，可通过 `VITE_API_PROXY_TARGET=http://host:port npm run dev` 覆盖。

## 构建与测试

```bash
npm run test
npm run build
```

## 容器部署

```bash
docker build -t harmony-music-web ./apps/web
docker run --rm -p 8081:80 --network deploy_default harmony-music-web
```

Nginx 会把 `/api/` 和 `/healthz` 代理到 Compose 服务名 `music-server:8080`，并保留 Range 请求头以支持 HTML5 Audio 拖动进度。

## API 契约

已落地接口：

- `GET /healthz`：返回 `{ "status": "ok" }`。
- `GET /api/v1/tracks`：返回 `{ "tracks": Track[], "total": number }`。
- `GET /api/v1/tracks/{id}/stream`：返回音频流，需支持浏览器 Range 请求。
- `GET /api/v1/tracks/{id}/lyrics`：返回 `{ "track_id", "encoding", "content" }`；歌词不存在时返回 `404`，Web 显示“暂无歌词”且不影响播放。

Web 已按以下管理契约实现；若后端尚未落地，会展示友好错误并标明缺失接口：

- `POST /api/v1/library/scan`：响应 `{ "tracks", "total", "scanned_at" }`。
- `GET /api/v1/library/status`：响应 `{ "directory", "track_count", "scanning", "last_scanned_at", "last_error" }`。
- `POST /api/v1/tracks/{id}/scrape/search`：请求体 `{}`，响应 `{ "track_id": string, "candidates": ScrapeCandidate[] }`；候选包含 `id`、`provider`、`confidence`、`metadata`、`differences`。
- `POST /api/v1/tracks/{id}/scrape/apply`：请求体 `{ "candidate_id": string, "provider": string, "fields": string[] }`，响应包含更新后的 `track`、`applied_fields`、`applied_at`。
