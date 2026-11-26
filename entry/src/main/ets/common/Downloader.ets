import { common } from '@kit.AbilityKit';
import { fileIo, fileUri } from '@kit.CoreFileKit';
import { filePreview } from '@kit.PreviewKit';
import { request } from '@kit.BasicServicesKit';
import { webview } from '@kit.ArkWeb';
import { UIContext } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Ui } from './Ui';

const DOMAIN: number = 0x0000;
const TAG: string = 'myzcst-download';
const DOWNLOAD_DIR: string = '/downloads';
/** 和 PortalApi 保持一致的移动端 UA，个别服务端会按 UA 决定是否给附件。 */
const UA: string = 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 ' +
  '(KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1';

/**
 * 网页附件下载。
 *
 * 触发点：`Web.onDownloadStart`（WebViewPage / WebTab 都注册了）。学校门户里的
 * 通知附件、导出表格等都会走这个回调；不处理的话点击后没有任何反应。
 *
 * 实现分三步：
 *   1. 从 Content-Disposition / URL / MIME 推导安全文件名；
 *   2. 用 @ohos.request 下载到应用沙箱 `filesDir/downloads/`（无需存储权限），
 *      Cookie 通过 WebCookieManager 复制一份到请求头，保证需要登录的附件也能下；
 *   3. 下载完成后交给 Preview Kit 打开（PDF / Office / 图片 / 文本等），
 *      系统不支持预览时至少给出明确的文件名提示。
 */
export class Downloader {
  /**
   * 开始下载。方法内部吞掉所有异常并 Toast 提示，调用方不需要 await。
   */
  static async start(ui: UIContext, url: string, contentDisposition: string, mimeType: string): Promise<void> {
    const ctx: common.Context | undefined = Ui.context(ui);
    if (ctx === undefined) {
      Ui.toast(ui, '下载失败：无法获取应用上下文');
      return;
    }
    if (url.length === 0) {
      Ui.toast(ui, '下载失败：链接为空');
      return;
    }

    const fileName: string = Downloader.fileName(url, contentDisposition, mimeType);
    const dir: string = ctx.filesDir + DOWNLOAD_DIR;
    try {
      if (!fileIo.accessSync(dir)) {
        fileIo.mkdirSync(dir, true);
      }
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'mkdir %{public}s failed: %{public}s', dir, JSON.stringify(err));
      Ui.toast(ui, '下载失败：无法创建下载目录');
      return;
    }

    const dest: string = Downloader.uniquePath(dir, fileName);
    const header: Record<string, string> = { 'User-Agent': UA };
    try {
      const cookie: string = webview.WebCookieManager.fetchCookieSync(url);
      if (cookie.length > 0) {
        header['Cookie'] = cookie;
      }
    } catch (err) {
      // 没拿到 Cookie 就按匿名下载，不阻断流程。
      hilog.warn(DOMAIN, TAG, 'fetch cookie failed: %{public}s', JSON.stringify(err));
    }

    Ui.toast(ui, '开始下载：' + Downloader.shortName(dest));
    try {
      const config: request.DownloadConfig = {
        url: url,
        filePath: dest,
        header: header,
        title: Downloader.shortName(dest),
        background: false
      };
      const task: request.DownloadTask = await request.downloadFile(ctx, config);
      task.on('progress', (receivedSize: number, totalSize: number) => {
        if (totalSize > 0) {
          const percent: number = Math.floor(receivedSize * 100 / totalSize);
          hilog.info(DOMAIN, TAG, 'progress %{public}d%% (%{public}d/%{public}d)',
            percent, receivedSize, totalSize);
        }
      });
      task.on('complete', () => {
        hilog.info(DOMAIN, TAG, 'download complete: %{public}s', dest);
        Downloader.open(ui, ctx, dest, mimeType);
      });
      task.on('fail', (errCode: number) => {
        hilog.error(DOMAIN, TAG, 'download fail: %{public}d', errCode);
        Ui.toast(ui, '下载失败（' + errCode + '）');
      });
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'downloadFile failed: %{public}s', JSON.stringify(err));
      Ui.toast(ui, '下载失败：' + Downloader.shortName(dest));
    }
  }

  /** 下载完成后打开文件；系统不支持预览时退回提示。 */
  private static open(ui: UIContext, ctx: common.Context, path: string, mimeType: string): void {
    Ui.toast(ui, '下载完成，正在打开：' + Downloader.shortName(path));
    try {
      const uri: string = fileUri.getUriFromPath(path);
      const info: filePreview.PreviewInfo = {
        title: Downloader.shortName(path),
        uri: uri,
        mimeType: Downloader.mimeFor(path, mimeType)
      };
      filePreview.openPreview(ctx, info).catch((err: Error) => {
        hilog.error(DOMAIN, TAG, 'openPreview failed: %{public}s', err.message);
        Ui.toast(ui, '已下载：' + Downloader.shortName(path) + '（当前类型无法预览）');
      });
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'preview failed: %{public}s', JSON.stringify(err));
      Ui.toast(ui, '已下载：' + Downloader.shortName(path) + '（当前类型无法预览）');
    }
  }

  /** 从 Content-Disposition / URL 推导文件名，保证有扩展名且不含非法字符。 */
  static fileName(url: string, contentDisposition: string, mimeType: string): string {
    let name: string = Downloader.fromDisposition(contentDisposition);
    if (name.length === 0) {
      name = Downloader.fromUrl(url);
    }
    name = Downloader.sanitize(name);
    if (name.length === 0) {
      name = 'download_' + Date.now();
    }
    if (name.lastIndexOf('.') <= 0) {
      name = name + Downloader.extensionFor(mimeType);
    }
    if (name.length > 100) {
      const dot: number = name.lastIndexOf('.');
      name = dot > 0 ? name.substring(0, 90) + name.substring(dot) : name.substring(0, 100);
    }
    return name;
  }

  private static fromDisposition(cd: string): string {
    if (cd.length === 0) {
      return '';
    }
    const starAt: number = cd.toLowerCase().indexOf('filename*=');
    if (starAt >= 0) {
      let part: string = cd.substring(starAt + 'filename*='.length);
      const semi: number = part.indexOf(';');
      if (semi >= 0) {
        part = part.substring(0, semi);
      }
      part = part.trim();
      const quoteAt: number = part.indexOf("''");
      if (quoteAt >= 0) {
        part = part.substring(quoteAt + 2);
      }
      try {
        return decodeURIComponent(part);
      } catch (err) {
        return part;
      }
    }
    const plainAt: number = cd.toLowerCase().indexOf('filename=');
    if (plainAt >= 0) {
      let part: string = cd.substring(plainAt + 'filename='.length).trim();
      const semi: number = part.indexOf(';');
      if (semi >= 0) {
        part = part.substring(0, semi);
      }
      if (part.startsWith('"') && part.endsWith('"') && part.length > 1) {
        part = part.substring(1, part.length - 1);
      }
      return part.trim();
    }
    return '';
  }

  private static fromUrl(url: string): string {
    let path: string = url;
    const hash: number = path.indexOf('#');
    if (hash >= 0) {
      path = path.substring(0, hash);
    }
    const query: number = path.indexOf('?');
    if (query >= 0) {
      path = path.substring(0, query);
    }
    const slash: number = path.lastIndexOf('/');
    if (slash >= 0 && slash < path.length - 1) {
      path = path.substring(slash + 1);
    }
    try {
      return decodeURIComponent(path);
    } catch (err) {
      return path;
    }
  }

  private static sanitize(name: string): string {
    let out: string = name.replace(/[\\/:*?"<>|\r\n\t]/g, '_').trim();
    if (out === '.' || out === '..') {
      out = '';
    }
    return out;
  }

  /** 同名文件已存在时插入时间戳，避免覆盖上一次下载。 */
  private static uniquePath(dir: string, name: string): string {
    let path: string = dir + '/' + name;
    try {
      if (fileIo.accessSync(path)) {
        const dot: number = name.lastIndexOf('.');
        const stamp: string = '' + Date.now();
        path = dot > 0
          ? dir + '/' + name.substring(0, dot) + '_' + stamp + name.substring(dot)
          : dir + '/' + name + '_' + stamp;
      }
    } catch (err) {
      // accessSync 在不存在时返回 false，这里的异常按"不存在"处理。
    }
    return path;
  }

  /** 仅供 Toast 展示：去掉目录，避免提示里出现一长串沙箱路径。 */
  private static shortName(path: string): string {
    const slash: number = path.lastIndexOf('/');
    return slash >= 0 ? path.substring(slash + 1) : path;
  }

  private static extensionFor(mimeType: string): string {
    const mime: string = mimeType.toLowerCase();
    if (mime.indexOf('pdf') >= 0) {
      return '.pdf';
    }
    if (mime.indexOf('wordprocessingml') >= 0 || mime === 'application/msword') {
      return '.docx';
    }
    if (mime.indexOf('spreadsheetml') >= 0 || mime === 'application/vnd.ms-excel') {
      return '.xlsx';
    }
    if (mime.indexOf('presentationml') >= 0 || mime === 'application/vnd.ms-powerpoint') {
      return '.pptx';
    }
    if (mime === 'image/jpeg') {
      return '.jpg';
    }
    if (mime === 'image/png') {
      return '.png';
    }
    if (mime === 'image/gif') {
      return '.gif';
    }
    if (mime.indexOf('text/') === 0) {
      return '.txt';
    }
    if (mime.indexOf('zip') >= 0) {
      return '.zip';
    }
    return '.bin';
  }

  /** 根据扩展名修正 MIME，Preview Kit 靠它选择预览器。 */
  private static mimeFor(path: string, fallback: string): string {
    const dot: number = path.lastIndexOf('.');
    const ext: string = dot >= 0 ? path.substring(dot + 1).toLowerCase() : '';
    if (ext === 'pdf') {
      return 'application/pdf';
    }
    if (ext === 'doc' || ext === 'docx') {
      return 'application/msword';
    }
    if (ext === 'xls' || ext === 'xlsx') {
      return 'application/vnd.ms-excel';
    }
    if (ext === 'ppt' || ext === 'pptx') {
      return 'application/vnd.ms-powerpoint';
    }
    if (ext === 'jpg' || ext === 'jpeg') {
      return 'image/jpeg';
    }
    if (ext === 'png') {
      return 'image/png';
    }
    if (ext === 'gif') {
      return 'image/gif';
    }
    if (ext === 'webp') {
      return 'image/webp';
    }
    if (ext === 'txt' || ext === 'log' || ext === 'csv' || ext === 'json' || ext === 'xml') {
      return 'text/plain';
    }
    if (ext === 'mp4') {
      return 'video/mp4';
    }
    if (ext === 'mp3') {
      return 'audio/mpeg';
    }
    return fallback.length > 0 ? fallback : 'application/octet-stream';
  }
}
