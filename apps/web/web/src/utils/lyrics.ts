export interface LyricLine {
  id: string;
  time: number | null;
  text: string;
}

const timestampPattern = /\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\]/g;

export function parseLyrics(content: string): LyricLine[] {
  const lines: LyricLine[] = [];

  content.split(/\r?\n/).forEach((rawLine, lineIndex) => {
    const timestamps = Array.from(rawLine.matchAll(timestampPattern));
    const text = rawLine.replace(timestampPattern, "").trim();

    if (timestamps.length === 0) {
      if (text && !/^\[[a-z]+:/i.test(text)) {
        lines.push({ id: `plain-${lineIndex}`, time: null, text });
      }
      return;
    }

    timestamps.forEach((match, timestampIndex) => {
      const minutes = Number(match[1] ?? 0);
      const seconds = Number(match[2] ?? 0);
      const fractionText = match[3] ?? "0";
      const fraction = Number(fractionText) / 10 ** fractionText.length;
      lines.push({
        id: `timed-${lineIndex}-${timestampIndex}`,
        time: minutes * 60 + seconds + fraction,
        text: text || "♪",
      });
    });
  });

  const hasTimedLines = lines.some((line) => line.time !== null);
  if (!hasTimedLines) {
    return lines;
  }

  return lines.sort((left, right) => {
    if (left.time === null) {
      return 1;
    }
    if (right.time === null) {
      return -1;
    }
    return left.time - right.time;
  });
}

export function activeLyricIndex(
  lines: LyricLine[],
  currentTime: number,
): number {
  let activeIndex = -1;
  for (let index = 0; index < lines.length; index += 1) {
    const line = lines[index];
    if (line?.time !== null && line?.time !== undefined) {
      if (line.time > currentTime + 0.08) {
        break;
      }
      activeIndex = index;
    }
  }
  return activeIndex;
}
