/**
 * 页面间传参用的数据类。
 *
 * ArkTS 的 router.pushUrl 只能传可序列化对象，且不允许匿名对象字面量带隐式类型，
 * 所以统一在这里定义成 class，push 与 getParams 两端共用同一份定义。
 */
export class WebPageParams {
  /** 顶栏标题。 */
  title: string = '';
  /** 要打开的地址。 */
  url: string = '';

  constructor(title: string, url: string) {
    this.title = title;
    this.url = url;
  }
}
