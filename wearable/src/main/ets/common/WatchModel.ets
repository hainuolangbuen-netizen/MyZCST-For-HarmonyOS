/** 一节课在手表上的视图模型。 */
export class WatchLesson {
  /** 开始分钟（当天 0 点起算）。 */
  startMin: number = 0;
  /** 结束分钟。 */
  endMin: number = 0;
  /** 节次文本，如「1-2 节」。 */
  range: string = '';
  name: string = '';
  room: string = '';
  /** 11:05 样式。 */
  startText: string = '';
  endText: string = '';
}

/** 水电读数行。 */
export class WatchFeeItem {
  label: string = '';
  value: string = '';
  unit: string = '';
  used: string = '';
  urgent: boolean = false;
}

/** 本周某天的课表块。 */
export class WatchDayBlock {
  day: number = 0;
  lessons: WatchLesson[] = [];
}

/**
 * 课表与水电的解析。
 *
 * 输入是手机端 CardStore 里那两行文本（手表通过 Wear Engine 收到的就是同一份内容），
 * 格式与手机端小组件完全一致，避免两端各写一套解析：
 *
 *   课表一行：`开始|结束|节次|课程|教室|教师|周次`
 *   水电一行：`名称|数值|单位|已用|告警`（例如 `剩余电量|148.20|度|10.03|0`）
 *
 * 这里的解析刻意做成"宽容"的：字段不足的行只取能认出来的部分，不抛异常，
 * 因为学校的接口字段经常变，手表现在只是展示终端，不值得为一行脏数据整体失败。
 */
export class WatchModel {
  private static toMin(text: string): number {
    const p: string[] = text.trim().split(':');
    if (p.length < 2) {
      return -1;
    }
    const h: number = Number(p[0]);
    const m: number = Number(p[1]);
    if (isNaN(h) || isNaN(m) || h < 0 || m < 0 || m > 59) {
      return -1;
    }
    return h * 60 + m;
  }

  static minText(min: number): string {
    const v: number = ((min % 1440) + 1440) % 1440;
    const h: number = Math.floor(v / 60);
    const m: number = v % 60;
    return (h < 10 ? '0' + h : String(h)) + ':' + (m < 10 ? '0' + m : String(m));
  }

  /** 今天的所有课，按开始时间升序。今天没有课时返回空数组。 */
  static today(scheduleText: string, weekday: number): WatchLesson[] {
    if (weekday < 1 || weekday > 7) {
      return [];
    }
    const out: WatchLesson[] = [];
    for (const line of scheduleText.split('\n')) {
      const cells: string[] = line.split('|');
      if (cells.length < 2) {
        continue;
      }
      const start: number = WatchModel.toMin(cells[0]);
      const end: number = WatchModel.toMin(cells[1]);
      if (start < 0 || end <= start) {
        continue;
      }
      const lesson: WatchLesson = new WatchLesson();
      lesson.startMin = start;
      lesson.endMin = end;
      lesson.startText = cells[0].trim();
      lesson.endText = cells[1].trim();
      lesson.range = cells.length > 2 ? cells[2].trim() : '';
      lesson.name = cells.length > 3 ? cells[3].trim() : '';
      lesson.room = cells.length > 4 ? cells[4].trim() : '';
      if (lesson.name.length === 0) {
        continue;
      }
      out.push(lesson);
    }
    out.sort((a: WatchLesson, b: WatchLesson) => a.startMin - b.startMin);
    return out;
  }

  /** 这一行的课属于星期几需要看来源；手机端只推今天，所以这里只做排序。 */

  static parseFee(feeText: string): WatchFeeItem[] {
    const out: WatchFeeItem[] = [];
    for (const line of feeText.split('\n')) {
      const cells: string[] = line.split('|');
      if (cells.length < 3) {
        continue;
      }
      const unit: string = cells[2].trim();
      // 手机端历史版本可能把「元」也写进来，手表只看度/吨。
      if (unit !== '度' && unit !== '吨' && unit !== 'm³') {
        continue;
      }
      const item: WatchFeeItem = new WatchFeeItem();
      item.label = cells[0].trim();
      item.value = cells[1].trim();
      item.unit = unit === 'm³' ? '吨' : unit;
      item.used = cells.length > 3 ? cells[3].trim() : '';
      item.urgent = cells.length > 4 && cells[4].trim() === '1';
      if (item.label.length === 0) {
        continue;
      }
      out.push(item);
    }
    return out;
  }

  /** 距离下课的剩余分钟；已下课返回 -1。 */
  static minutesLeft(lesson: WatchLesson, nowMin: number): number {
    if (nowMin < lesson.startMin || nowMin >= lesson.endMin) {
      return -1;
    }
    return lesson.endMin - nowMin;
  }

  /** 距离上课还有多少分钟；已经开始返回 -1。 */
  static minutesTo(lesson: WatchLesson, nowMin: number): number {
    if (nowMin >= lesson.startMin) {
      return -1;
    }
    return lesson.startMin - nowMin;
  }

  /** 当前时间对应的分钟数。 */
  static nowMinute(): number {
    const d: Date = new Date();
    return d.getHours() * 60 + d.getMinutes();
  }

  /** 1=周一 … 7=周日。 */
  static weekday(): number {
    const d: number = new Date().getDay();
    return d === 0 ? 7 : d;
  }

  /** 11月26日 · 周四，手表顶部用的短标签。 */
  static dateLabel(): string {
    const d: Date = new Date();
    const names: string[] = ['日', '一', '二', '三', '四', '五', '六'];
    return (d.getMonth() + 1) + '月' + d.getDate() + '日 · 周' + names[d.getDay()];
  }
}