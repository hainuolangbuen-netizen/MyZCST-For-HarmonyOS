import { common } from '@kit.AbilityKit';
import { webview } from '@kit.ArkWeb';
import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { CardData } from './CardData';
import { CardStore } from './CardStore';

const DOMAIN: number = 0x0000;
const TAG: string = 'myzcst-todo';
const TODO_URL: string =
  'https://mapp.zcst.edu.cn/_web/_plugs/notes/queryRemindGroupSettingListByNotesGroupId.rst'
    + '?_p=YXM9MSZwPTEmbT1OJg__&notesGroupId=1';
const TTL_MS: number = 30 * 60 * 1000;

interface TodoItem {
  title: string;
  content: string;
}

/**
 * 「我的待办」数据同步。
 *
 * 接口来自官方 RN 版「我的」页（见 analysis/zhuke/02-rn-modules.md 6.3）：
 *   GET <app_store_url>/_web/_plugs/notes/queryRemindGroupSettingListByNotesGroupId.rst
 *       ?_p=YXM9MSZwPTEmbT1OJg__&notesGroupId=1
 *   返回 { result:"1", data:[{title,content,icon}] }
 * 不伪造数据：接口没数据就写「暂无待办」；失败保留上次快照。
 */
export class TodoSync {
  private static syncing: boolean = false;
  private static lastAttempt: number = 0;

  static async ensureFresh(context: common.Context): Promise<void> {
    const last: number = Number(CardStore.getSync(context, CardStore.KEY_TODO_SYNC_AT));
    if (!isNaN(last) && last > 0 && Date.now() - last < TTL_MS) {
      return;
    }
    if (Date.now() - TodoSync.lastAttempt < 60 * 1000) {
      return;
    }
    await TodoSync.sync(context);
  }

  static async sync(context: common.Context): Promise<boolean> {
    if (TodoSync.syncing) {
      return false;
    }
    TodoSync.syncing = true;
    TodoSync.lastAttempt = Date.now();
    try {
      return await TodoSync.doSync(context);
    } finally {
      TodoSync.syncing = false;
    }
  }

  private static async doSync(context: common.Context): Promise<boolean> {
    const cookie: string = TodoSync.cookie();
    if (cookie.length === 0) {
      hilog.info(DOMAIN, TAG, 'skip: no cookie');
      return false;
    }
    const request = http.createHttp();
    try {
      const response: http.HttpResponse = await request.request(TODO_URL, {
        method: http.RequestMethod.GET,
        header: {
          'Accept': 'application/json,text/plain,*/*',
          'Cookie': cookie,
          'User-Agent': 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Mobile Safari/537.36'
        },
        connectTimeout: 15000,
        readTimeout: 15000
      });
      if (response.responseCode !== 200 || typeof response.result !== 'string') {
        return false;
      }
      const text: string = response.result as string;
      if (text.indexOf('{') < 0) {
        return false;
      }
      const root: Record<string, Object> = JSON.parse(text) as Record<string, Object>;
      const result: string = TodoSync.str(root['result']);
      if (result !== '1') {
        hilog.warn(DOMAIN, TAG, 'result=%{public}s', result);
        return false;
      }
      const raw: Object | undefined = root['data'];
      const items: TodoItem[] = [];
      if (Array.isArray(raw)) {
        for (const obj of raw as Object[]) {
          if (obj === null || obj === undefined || typeof obj !== 'object') {
            continue;
          }
          const rec: Record<string, Object> = obj as Record<string, Object>;
          const title: string = TodoSync.clean(TodoSync.str(rec['title']));
          const content: string = TodoSync.clean(TodoSync.str(rec['content']));
          if (title.length === 0 && content.length === 0) {
            continue;
          }
          items.push({ title: title, content: content });
        }
      }
      const lines: string[] = [];
      if (items.length === 0) {
        lines.push('暂无待办');
      } else {
        for (const item of items.slice(0, 12)) {
          lines.push(item.title + '|' + item.content);
        }
      }
      await CardStore.put(context, CardStore.KEY_TODO, lines.join('\n'));
      await CardStore.put(context, CardStore.KEY_TODO_UPDATED, TodoSync.stamp());
      await CardStore.put(context, CardStore.KEY_TODO_SYNC_AT, String(Date.now()));
      await CardData.updateAll(context);
      hilog.info(DOMAIN, TAG, 'sync ok items=%{public}d', items.length);
      return true;
    } catch (err) {
      const e = err as BusinessError;
      hilog.warn(DOMAIN, TAG, 'sync failed: %{public}d %{public}s', e.code, e.message);
      return false;
    } finally {
      request.destroy();
    }
  }

  private static cookie(): string {
    try {
      const mapp: string = webview.WebCookieManager.fetchCookieSync('https://mapp.zcst.edu.cn/');
      if (mapp.length > 0) {
        return mapp;
      }
    } catch (err) {
      // 忽略
    }
    try {
      return webview.WebCookieManager.fetchCookieSync('https://my.zcst.edu.cn/');
    } catch (err) {
      return '';
    }
  }

  private static str(value: Object | undefined): string {
    return typeof value === 'string' ? (value as string).trim() : (typeof value === 'number' ? String(value) : '');
  }

  /** 待办内容里可能带 <span> 等标签，卡片只显示纯文本。 */
  private static clean(text: string): string {
    return text.replace(/<[^>]+>/g, '').replace(/\s+/g, ' ').trim();
  }

  private static stamp(): string {
    const d = new Date();
    const p = (n: number): string => (n < 10 ? '0' + n : String(n));
    return p(d.getMonth() + 1) + '-' + p(d.getDate()) + ' ' + p(d.getHours()) + ':' + p(d.getMinutes()) + ' 已同步';
  }
}
