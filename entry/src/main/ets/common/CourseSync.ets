import { common } from '@kit.AbilityKit';
import { http } from '@kit.NetworkKit';
import { webview } from '@kit.ArkWeb';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { CardData } from './CardData';
import { CardStore } from './CardStore';

const DOMAIN: number = 0x0000;
const TAG: string = 'myzcst-course';

/**
 * 今日课表同步。
 *
 * 数据源与官方安卓版 RN 课表模块一致（旧 iPortal 移动接口，走 mapp 域名）：
 *   1. GET .../schedule/mobile/termAndWeek/inquirySchoolWeeks_2.rst  → 当前教学周
 *   2. GET .../schedule/mobile/student/inquiryStudentSchedule.rst?week=<周> → 当周课程
 * 返回字段（实测自 classes.bundle）：zj 星期、jc 起始节、jccd 连堂节数、
 * kcmc 课程名、jsdd 教室。
 *
 * ⚠️ 这是学校私有接口，没有公开文档；学校升级轻应用或改字段时同步会失败。
 * 失败时只写日志、不覆盖已有卡片数据，卡片继续显示上次同步结果。
 */
const WEEKS_URL: string =
  'https://mapp.zcst.edu.cn/_web/_lightapp/schedule/mobile/termAndWeek/inquirySchoolWeeks_2.rst';
const SCHEDULE_URL: string =
  'https://mapp.zcst.edu.cn/_web/_lightapp/schedule/mobile/student/inquiryStudentSchedule.rst?week=';
const UA: string = 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 ' +
  '(KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1';
/** 同一份数据 30 分钟内不重复拉取（卡片本身的系统刷新周期也是 30 分钟）。 */
const SYNC_TTL_MS: number = 30 * 60 * 1000;

class Lesson {
  day: number = 0;
  start: number = 0;
  span: number = 2;
  name: string = '';
  room: string = '';
}

export class CourseSync {
  /** 避免登录页与 Index.onPageShow 同时触发导致重复请求。 */
  private static syncing: boolean = false;
  /** 上次尝试时间（毫秒），失败后 1 分钟内不再重试，防止每次切页签都打接口。 */
  private static lastAttempt: number = 0;

  /** 页签切回前台/登录返回时调用：按 TTL 决定是否真正联网。 */
  static async ensureFresh(context: common.Context): Promise<void> {
    const raw: string = CardStore.getSync(context, CardStore.KEY_SYNC_AT);
    const last: number = Number(raw);
    if (!isNaN(last) && last > 0 && Date.now() - last < SYNC_TTL_MS) {
      return;
    }
    if (Date.now() - CourseSync.lastAttempt < 60 * 1000) {
      return;
    }
    await CourseSync.sync(context);
  }

  /**
   * 拉取并写入今日课程。返回 true 表示这次确实拿到了合法 JSON 并写入了数据。
   */
  static async sync(context: common.Context): Promise<boolean> {
    if (CourseSync.syncing) {
      hilog.info(DOMAIN, TAG, 'skip: another sync is running');
      return false;
    }
    CourseSync.syncing = true;
    CourseSync.lastAttempt = Date.now();
    try {
      return await CourseSync.doSync(context);
    } finally {
      CourseSync.syncing = false;
    }
  }

  private static async doSync(context: common.Context): Promise<boolean> {
    const cookie: string = CourseSync.cookie();
    if (cookie.length === 0) {
      hilog.info(DOMAIN, TAG, 'skip: no session cookie');
      return false;
    }
    const weeksText: string = await CourseSync.get(WEEKS_URL, cookie);
    if (!CourseSync.looksJson(weeksText)) {
      hilog.warn(DOMAIN, TAG, 'weeks api not json (len=%{public}d)', weeksText.length);
      return false;
    }
    const week: number = CourseSync.currentWeek(weeksText);
    const scheduleText: string = await CourseSync.get(SCHEDULE_URL + (week > 0 ? week : 1), cookie);
    if (!CourseSync.looksJson(scheduleText)) {
      hilog.warn(DOMAIN, TAG, 'schedule api not json (week=%{public}d len=%{public}d)',
        week, scheduleText.length);
      return false;
    }
    const lessons: Lesson[] = CourseSync.parseLessons(scheduleText);
    if (lessons.length === 0) {
      hilog.warn(DOMAIN, TAG, 'no lesson parsed');
      return false;
    }

    const today: number = CourseSync.today();
    const todayLessons: Lesson[] = [];
    for (const lesson of lessons) {
      if (lesson.day === today) {
        todayLessons.push(lesson);
      }
    }
    todayLessons.sort((a: Lesson, b: Lesson) => a.start - b.start);
    const lines: string[] = [];
    if (todayLessons.length === 0) {
      lines.push('今天没有课程');
    } else {
      for (const lesson of todayLessons.slice(0, 6)) {
        const range: string = lesson.start + '-' + (lesson.start + lesson.span - 1);
        lines.push('第' + range + '节 ' + lesson.name +
          (lesson.room.length > 0 ? ' · ' + lesson.room : ''));
      }
    }

    await CardStore.put(context, CardStore.KEY_SCHEDULE, lines.join('\n'));
    await CardStore.put(context, CardStore.KEY_UPDATED, CourseSync.stamp());
    await CardStore.put(context, CardStore.KEY_SYNC_AT, String(Date.now()));
    await CardData.updateAll(context);
    hilog.info(DOMAIN, TAG, 'sync ok: week=%{public}d today=%{public}d lessons=%{public}d',
      week, today, todayLessons.length);
    return true;
  }

  /** 站点 Cookie 由 Web 组件维护；mapp 没有时退回主门户域再找一次。 */
  private static cookie(): string {
    try {
      const mapp: string = webview.WebCookieManager.fetchCookieSync('https://mapp.zcst.edu.cn/');
      if (mapp.length > 0) {
        return mapp;
      }
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'cookie(mapp) failed');
    }
    try {
      return webview.WebCookieManager.fetchCookieSync('https://my.zcst.edu.cn/');
    } catch (err) {
      return '';
    }
  }

  private static async get(url: string, cookie: string): Promise<string> {
    const request = http.createHttp();
    try {
      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.GET,
        header: {
          'User-Agent': UA,
          'Cookie': cookie,
          'Accept': 'application/json, text/plain, */*',
          'Referer': 'https://mapp.zcst.edu.cn/'
        },
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 10000,
        readTimeout: 15000
      };
      const response = await request.request(url, options);
      if (response.responseCode !== 200 || typeof response.result !== 'string') {
        return '';
      }
      return response.result as string;
    } catch (err) {
      const e = err as BusinessError;
      hilog.warn(DOMAIN, TAG, 'GET %{public}s failed: %{public}d', url, e.code);
      return '';
    } finally {
      request.destroy();
    }
  }

  /** 登录页是 HTML，只有 JSON 才继续解析。 */
  private static looksJson(text: string): boolean {
    const trimmed: string = text.replace(/^\s+/, '');
    return trimmed.startsWith('{') || trimmed.startsWith('[');
  }

  private static today(): number {
    const day: number = new Date().getDay();
    return day === 0 ? 7 : day;
  }

  private static stamp(): string {
    const d = new Date();
    const mm: string = d.getMonth() + 1 < 10 ? '0' + (d.getMonth() + 1) : '' + (d.getMonth() + 1);
    const dd: string = d.getDate() < 10 ? '0' + d.getDate() : '' + d.getDate();
    const hh: string = d.getHours() < 10 ? '0' + d.getHours() : '' + d.getHours();
    const mi: string = d.getMinutes() < 10 ? '0' + d.getMinutes() : '' + d.getMinutes();
    return mm + '-' + dd + ' ' + hh + ':' + mi + ' 已同步';
  }

  /** 在响应里递归找 currentWeek（不同版本可能叫 zc/week）。 */
  private static currentWeek(text: string): number {
    try {
      const root: Object = JSON.parse(text) as Object;
      return CourseSync.findNumber(root, ['currentWeek', 'currentWeekNum', 'week'], 0);
    } catch (err) {
      return -1;
    }
  }

  private static findNumber(node: Object, keys: string[], depth: number): number {
    if (depth > 6 || node === null || node === undefined) {
      return -1;
    }
    if (Array.isArray(node)) {
      for (const item of node as Object[]) {
        const hit: number = CourseSync.findNumber(item as Object, keys, depth + 1);
        if (hit > 0) {
          return hit;
        }
      }
      return -1;
    }
    if (typeof node !== 'object') {
      return -1;
    }
    const rec: Record<string, Object> = node as Record<string, Object>;
    for (const key of keys) {
      const value: Object = rec[key];
      if (typeof value === 'number' && (value as number) > 0) {
        return value as number;
      }
      if (typeof value === 'string' && (value as string).length > 0) {
        const n: number = Number(value as string);
        if (!isNaN(n) && n > 0) {
          return n;
        }
      }
    }
    for (const key of Object.keys(rec)) {
      const child: Object = rec[key];
      if (child !== null && child !== undefined && typeof child === 'object') {
        const hit: number = CourseSync.findNumber(child, keys, depth + 1);
        if (hit > 0) {
          return hit;
        }
      }
    }
    return -1;
  }

  /** 递归收集课程对象，兼容 data 数组和直接数组两种包裹。 */
  private static parseLessons(text: string): Lesson[] {
    const out: Lesson[] = [];
    try {
      const root: Object = JSON.parse(text) as Object;
      CourseSync.collect(root, out, 0);
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'parseLessons failed');
    }
    return out;
  }

  private static collect(node: Object, out: Lesson[], depth: number): void {
    if (depth > 6 || node === null || node === undefined) {
      return;
    }
    if (Array.isArray(node)) {
      for (const item of node as Object[]) {
        CourseSync.collect(item as Object, out, depth + 1);
      }
      return;
    }
    if (typeof node !== 'object') {
      return;
    }
    const rec: Record<string, Object> = node as Record<string, Object>;
    const name: string = CourseSync.pick(rec, ['kcmc', 'courseName', 'lessonName', 'name']);
    if (name.length > 0) {
      const lesson = new Lesson();
      lesson.name = name;
      lesson.day = CourseSync.num(rec, ['zj', 'weekDay', 'day'], 0);
      lesson.start = CourseSync.num(rec, ['jc', 'startSection', 'start', 'sectionStart'], 0);
      lesson.span = CourseSync.num(rec, ['jccd', 'sectionCount', 'span', 'step'], 2);
      lesson.room = CourseSync.pick(rec, ['jsdd', 'roomName', 'room', 'classRoom']);
      // 根节点/包裹层也可能带 name 字段（学期名等），只有同时有星期和节次才算课程。
      if (lesson.day > 0 && lesson.start > 0) {
        if (!CourseSync.duplicated(out, lesson)) {
          out.push(lesson);
        }
        return;
      }
    }
    for (const key of Object.keys(rec)) {
      const child: Object = rec[key];
      if (child !== null && child !== undefined && typeof child === 'object') {
        CourseSync.collect(child, out, depth + 1);
      }
    }
  }

  private static pick(rec: Record<string, Object>, keys: string[]): string {
    for (const key of keys) {
      const value: Object = rec[key];
      if (typeof value === 'string') {
        const s: string = (value as string).trim();
        if (s.length > 0) {
          return s;
        }
      }
    }
    return '';
  }

  private static num(rec: Record<string, Object>, keys: string[], fallback: number): number {
    for (const key of keys) {
      const value: Object = rec[key];
      if (typeof value === 'number') {
        return value as number;
      }
      if (typeof value === 'string') {
        const n: number = Number(value as string);
        if (!isNaN(n)) {
          return n;
        }
      }
    }
    return fallback;
  }

  private static duplicated(list: Lesson[], lesson: Lesson): boolean {
    for (const item of list) {
      if (item.day === lesson.day && item.start === lesson.start && item.name === lesson.name) {
        return true;
      }
    }
    return false;
  }
}
