import { useMemo } from "react";
import type { ListeningHeatmapCell, ListeningReport } from "../api/types";
import { displayArtist, formatDuration } from "../utils/format";
import { AlbumArt } from "../components/AlbumArt";
import { Icon } from "../components/Icon";

interface ListeningReportPageProps {
  report: ListeningReport | null;
  error: string | null;
  loading: boolean;
  onRefresh(): void;
  onPlay(trackId: string): void;
}

export function ListeningReportPage({
  report,
  error,
  loading,
  onRefresh,
  onPlay,
}: ListeningReportPageProps) {
  return (
    <div className="report-page">
      <section className="report-hero">
        <div>
          <span className="eyebrow">LISTENING REPORT</span>
          <h1>{report?.year ?? new Date().getFullYear()} 听歌报告</h1>
          <p>只统计在此账号下真实播放并累计的聆听事件。</p>
        </div>
        <button
          className="button button--secondary"
          disabled={loading}
          onClick={onRefresh}
          type="button"
        >
          <Icon className={loading ? "spin" : ""} name="refresh" size={18} />
          刷新报告
        </button>
      </section>

      {error && (
        <div className="inline-error">
          <Icon name="alert" />
          <div>
            <strong>报告加载失败</strong>
            <span>{error}</span>
          </div>
          <button
            className="button button--secondary button--compact"
            onClick={onRefresh}
            type="button"
          >
            重试
          </button>
        </div>
      )}

      {loading && !report && <ReportSkeleton />}

      {!error && report && (
        <>
          <section className="report-stats" aria-label="听歌统计">
            <Stat label="播放次数" value={report.total_plays.toLocaleString("zh-CN")} />
            <Stat label="聆听时长" value={formatListeningTime(report.total_listened_ms)} />
            <Stat label="活跃天数" value={`${report.listening_days} 天`} />
            <Stat label="听过曲目" value={`${report.unique_tracks} 首`} />
          </section>

          <section className="report-panel">
            <div className="section-heading">
              <div>
                <h2>年度热力图</h2>
                <p>颜色越深，代表当天累计的真实聆听越多。</p>
              </div>
              <span className="section-count">{report.heatmap.length} 天有记录</span>
            </div>
            <ListeningHeatmap year={report.year} cells={report.heatmap} />
          </section>

          <section className="report-panel">
            <div className="section-heading">
              <div>
                <h2>热门榜</h2>
                <p>按播放次数与累计聆听时长汇总。</p>
              </div>
              <span className="section-count">{report.top_tracks.length} 首</span>
            </div>
            {report.top_tracks.length > 0 ? (
              <div className="report-ranking">
                {report.top_tracks.map((item, index) => (
                  <button
                    className="report-ranking__item"
                    key={item.track.id}
                    onClick={() => onPlay(item.track.id)}
                    type="button"
                  >
                    <b>{index + 1}</b>
                    <AlbumArt size="small" track={item.track} />
                    <span>
                      <strong>{item.track.title}</strong>
                      <small>{displayArtist(item.track)}</small>
                    </span>
                    <em>
                      {item.play_count} 次
                      <small>{formatDuration(item.listened_ms / 1_000)}</small>
                    </em>
                    <Icon name="play" size={17} />
                  </button>
                ))}
              </div>
            ) : (
              <div className="discovery-empty">
                还没有足够的播放记录，开始听歌后会生成热门榜。
              </div>
            )}
          </section>
        </>
      )}
    </div>
  );
}

function Stat({ label, value }: { label: string; value: string }) {
  return (
    <article>
      <span>{label}</span>
      <strong>{value}</strong>
    </article>
  );
}

function ListeningHeatmap({
  year,
  cells,
}: {
  year: number;
  cells: ListeningHeatmapCell[];
}) {
  const days = useMemo(() => {
    const totals = new Map(
      cells.map((cell) => [
        cell.date.slice(0, 10),
        Math.max(cell.listened_ms, cell.play_count),
      ]),
    );
    const maximum = Math.max(1, ...totals.values());
    const start = new Date(year, 0, 1);
    const end = new Date(year + 1, 0, 1);
    const values: Array<{ date: string; level: number; value: number }> = [];
    for (
      let cursor = start;
      cursor.getTime() < end.getTime();
      cursor = new Date(cursor.getFullYear(), cursor.getMonth(), cursor.getDate() + 1)
    ) {
      const date = cursor.toISOString().slice(0, 10);
      const value = totals.get(date) ?? 0;
      const level =
        value === 0 ? 0 : Math.min(4, Math.max(1, Math.ceil((value / maximum) * 4)));
      values.push({ date, level, value });
    }
    return values;
  }, [cells, year]);

  return (
    <div className="report-heatmap" aria-label={`${year} 年听歌热力图`}>
      {days.map((day) => (
        <span
          className={`report-heatmap__day level-${day.level}`}
          key={day.date}
          title={`${day.date}：${day.value ? `${day.value} 秒或播放次数` : "无记录"}`}
        />
      ))}
    </div>
  );
}

function formatListeningTime(milliseconds: number): string {
  if (!Number.isFinite(milliseconds) || milliseconds <= 0) {
    return "0 分钟";
  }
  const minutes = Math.floor(milliseconds / 60_000);
  if (minutes < 60) {
    return `${minutes} 分钟`;
  }
  const hours = Math.floor(minutes / 60);
  return `${hours} 小时 ${minutes % 60} 分`;
}

function ReportSkeleton() {
  return (
    <div className="report-skeleton" aria-label="正在加载听歌报告">
      {Array.from({ length: 6 }, (_, index) => (
        <span key={index} />
      ))}
    </div>
  );
}
