import { common } from '@kit.AbilityKit';
import { WatchModel, WatchLesson, WatchFeeItem } from '../common/WatchModel';
import { WatchPrefs } from '../common/WatchPrefs';

/**
 * 手表主页（Huawei Watch 系列，466×466 圆屏）。
 *
 * 只做两件事：看今天/本周的课、看宿舍还剩多少水电。
 *
 * 圆屏约定：
 *   · 内容区左右各留 44vp，避开圆弧；底部留 26vp 给页签指示；
 *   · 主信息用 19~30vp，辅助信息 9~11vp，一路减下去，抬腕一眼能读；
 *   · 页面纯黑底，圆外不露色块。
 *
 * 数据不在这里联网：手表没有登录态，课表与水电由手机同步后写进 WatchPrefs，
 * 本页只负责解析与呈现；没有数据时给出「等待手机同步」的明确提示。
 */
@Entry
@Component
struct WatchHome {
  @State ready: boolean = false;
  @State page: number = 0;
  @State clock: string = '--:--';
  @State dateLabel: string = '';
  @State subtitle: string = '';
  @State updated: string = '';
  /** 课程页：正在上 / 下一节。 */
  @State focusName: string = '';
  @State focusMeta: string = '';
  @State focusTip: string = '';
  @State focusTag: string = '';
  @State restUrl: string[] = [];
  /** 课表页：今天全部课程。 */
  @State allLessons: string[] = [];
  /** 水电页。 */
  @State feeItems: WatchFeeItem[] = [];
  @State feeRoom: string = '';
  @State feeUpdated: string = '';
  @State hasData: boolean = false;

  private timer: number = -1;

  aboutToAppear(): void {
    const context = getContext(this) as common.Context;
    WatchPrefs.init(context);
    this.readData();
    this.tick();
    this.timer = setInterval(() => {
      this.tick();
    }, 15000);
    this.ready = true;
  }

  aboutToDisappear(): void {
    if (this.timer >= 0) {
      clearInterval(this.timer);
      this.timer = -1;
    }
  }

  onPageShow(): void {
    this.readData();
    this.tick();
  }

  /** 从首选项读出手表缓存，重新解析成可展示的结构。 */
  private readData(): void {
    const schedule: string = WatchPrefs.str('schedule_text', '');
    this.subtitle = WatchPrefs.str('subtitle_text', '');
    this.updated = WatchPrefs.str('updated_text', '');
    this.feeRoom = WatchPrefs.str('fee_room', '');
    this.feeUpdated = WatchPrefs.str('fee_updated_text', '');
    const lessons: WatchLesson[] = WatchModel.today(schedule, WatchModel.weekday());
    this.hasData = lessons.length > 0 || this.feeRoom.length > 0 || this.updated.length > 0;
    this.allLessons = [];
    for (const lesson of lessons) {
      this.allLessons.push(lesson.startText + ' - ' + lesson.endText + '  ' + lesson.name +
        (lesson.room.length > 0 ? ' | ' + lesson.room : ''));
    }
    this.feeItems = WatchModel.parseFee(WatchPrefs.str('fee_lines', ''));
    this.applyFocus(lessons, WatchModel.nowMinute());
  }

  private tick(): void {
    const d: Date = new Date();
    const h: number = d.getHours();
    const m: number = d.getMinutes();
    this.clock = (h < 10 ? '0' + h : String(h)) + ':' + (m < 10 ? '0' + m : String(m));
    this.dateLabel = WatchModel.dateLabel();
    const lessons: WatchLesson[] = WatchModel.today(WatchPrefs.str('schedule_text', ''), WatchModel.weekday());
    this.applyFocus(lessons, h * 60 + m);
  }

  /** 正在上的课 > 下一节 > 今天没有课。 */
  private applyFocus(lessons: WatchLesson[], nowMin: number): void {
    if (lessons.length === 0) {
      this.focusName = '';
      this.focusMeta = '';
      this.focusTip = WatchModel.weekday() > 5 ? '周末没有课' : '今天没有课';
      this.focusTag = '';
      this.restUrl = [];
      return;
    }
    let current: WatchLesson | null = null;
    let next: WatchLesson | null = null;
    for (const lesson of lessons) {
      if (WatchModel.minutesLeft(lesson, nowMin) >= 0) {
        current = lesson;
        break;
      }
    }
    if (current === null) {
      for (const lesson of lessons) {
        if (WatchModel.minutesTo(lesson, nowMin) >= 0) {
          next = lesson;
          break;
        }
      }
    }
    if (current !== null) {
      const left: number = WatchModel.minutesLeft(current, nowMin);
      this.focusTag = '正在上课';
      this.focusName = current.name;
      this.focusMeta = (current.room.length > 0 ? current.room + ' · ' : '') +
        current.startText + '-' + current.endText;
      this.focusTip = left <= 1 ? '马上下课' : '还有 ' + left + ' 分钟下课';
    } else if (next !== null) {
      const left: number = WatchModel.minutesTo(next, nowMin);
      this.focusTag = '下一节';
      this.focusName = next.name;
      this.focusMeta = (next.room.length > 0 ? next.room + ' · ' : '') +
        next.startText + '-' + next.endText;
      this.focusTip = left <= 1 ? '马上上课' : left + ' 分钟后上课';
    } else {
      this.focusTag = '';
      this.focusName = '';
      this.focusMeta = '';
      this.focusTip = '今天没有课了';
    }
    const rest: string[] = [];
    for (const lesson of lessons) {
      if (rest.length >= 2) {
        break;
      }
      if (WatchModel.minutesTo(lesson, nowMin) > 0) {
        rest.push(lesson.startText + ' ' + lesson.name);
      }
    }
    this.restUrl = rest;
  }

  @Builder
  pageDots() {
    Row() {
      ForEach([0, 1, 2], (i: number) => {
        Row()
          .width(this.page === i ? 14 : 5)
          .height(5)
          .borderRadius(2.5)
          .margin({ left: 3, right: 3 })
          .backgroundColor(this.page === i ? '#4FC3A1' : '#333D4E')
      }, (i: number) => String(i))
    }
    .width('100%')
    .height(10)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  topBar() {
    Row() {
      Text(this.clock)
        .fontSize(11)
        .fontColor('#8FA3BF')
      Blank()
      Text(this.page === 2 && this.feeUpdated.length > 0 ? this.feeUpdated
        : (this.updated.length > 0 ? this.updated : this.dateLabel))
        .fontSize(9)
        .fontColor('#5A667A')
        .maxLines(1)
    }
    .width('100%')
    .padding({ left: 52, right: 52, top: 18, bottom: 2 })
  }

  @Builder
  coursePage() {
    Column() {
      if (!this.hasData) {
        Text('等待手机同步')
          .fontSize(13)
          .fontColor('#8FA3BF')
        Text('在手机上打开「我的珠科」登录后会自动推送')
          .fontSize(8)
          .fontColor('#5A667A')
          .maxLines(2)
          .textAlign(TextAlign.Center)
          .margin({ top: 4 })
      } else if (this.focusName.length > 0) {
        if (this.focusTag.length > 0) {
          Text(this.focusTag)
            .fontSize(9)
            .fontColor('#4FC3A1')
            .margin({ bottom: 2 })
        }
        Text(this.focusName)
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor('#F2F5FA')
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .textAlign(TextAlign.Center)
          .width('100%')
        Text(this.focusMeta)
          .fontSize(9)
          .fontColor('#8FA3BF')
          .maxLines(1)
          .textAlign(TextAlign.Center)
          .width('100%')
          .margin({ top: 2 })
        Text(this.focusTip)
          .fontSize(12)
          .fontColor('#4FC3A1')
          .margin({ top: 3 })
      } else {
        Text('今日课程')
          .fontSize(9)
          .fontColor('#4FC3A1')
        Text(this.focusTip)
          .fontSize(15)
          .fontColor('#F2F5FA')
          .margin({ top: 3 })
        Text(this.allLessons.length > 0 ? '共 ' + this.allLessons.length + ' 节' : '')
          .fontSize(9)
          .fontColor('#5A667A')
          .margin({ top: 2 })
      }
      if (this.restUrl.length > 0) {
        Column() {
          ForEach(this.restUrl, (line: string) => {
            Text(line)
              .fontSize(8.5)
              .fontColor('#6F7E95')
              .maxLines(1)
              .width('100%')
              .textAlign(TextAlign.Center)
          }, (line: string) => line)
        }
        .width('100%')
        .margin({ top: 8 })
      }
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .padding({ left: 46, right: 46 })
  }

  @Builder
  weekPage() {
    Column() {
      Row() {
        Text('今日课表')
          .fontSize(10)
          .fontColor('#4FC3A1')
        Blank()
        Text(this.allLessons.length > 0 ? this.allLessons.length + ' 节' : '')
          .fontSize(8)
          .fontColor('#5A667A')
      }
      .width('100%')
      .padding({ bottom: 4 })

      if (this.allLessons.length === 0) {
        Text(this.hasData ? '今天没有课' : '等待手机同步')
          .fontSize(12)
          .fontColor('#8FA3BF')
          .margin({ top: 16 })
      } else {
        List() {
          ForEach(this.allLessons, (line: string) => {
            ListItem() {
              Text(line)
                .fontSize(9)
                .fontColor('#DCE4F3')
                .maxLines(2)
                .width('100%')
                .padding({ top: 5, bottom: 5 })
            }
          }, (line: string) => line)
        }
        .layoutWeight(1)
        .width('100%')
        .scrollBar(BarState.Off)
        .margin({ top: 2 })
      }
    }
    .width('100%')
    .height('100%')
    .padding({ left: 40, right: 40, top: 2 })
  }

  @Builder
  feePage() {
    Column() {
      Text('宿舍水电')
        .fontSize(9)
        .fontColor('#4FC3A1')
      if (this.feeItems.length === 0) {
        Text(this.hasData ? '暂无水电数据' : '等待手机同步')
          .fontSize(13)
          .fontColor('#8FA3BF')
          .margin({ top: 6 })
      } else {
        ForEach(this.feeItems, (item: WatchFeeItem) => {
          Column() {
            Text(item.label)
              .fontSize(9)
              .fontColor('#8FA3BF')
            Row() {
              Text(item.value)
                .fontSize(item.urgent ? 24 : 21)
                .fontWeight(FontWeight.Bold)
                .fontColor(item.urgent ? '#E8A33D' : '#F2F5FA')
              Text(item.unit)
                .fontSize(9)
                .fontColor('#8FA3BF')
                .margin({ left: 2, bottom: 4 })
            }
          }
          .width('100%')
          .alignItems(HorizontalAlign.Center)
          .margin({ top: 4 })
        }, (item: WatchFeeItem) => item.label)
      }
      if (this.feeRoom.length > 0) {
        Text(this.feeRoom)
          .fontSize(8)
          .fontColor('#5A667A')
          .maxLines(1)
          .margin({ top: 6 })
      }
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .padding({ left: 46, right: 46 })
  }

  build() {
    Column() {
      if (!this.ready) {
        Text('载入中')
          .fontSize(10)
          .fontColor('#8FA3BF')
      } else {
        this.topBar()
        Swiper() {
          this.coursePage()
          this.weekPage()
          this.feePage()
        }
        .loop(false)
        .indicator(false)
        .layoutWeight(1)
        .width('100%')
        .onChange((index: number) => {
          this.page = index;
        })
        this.pageDots()
        Row().height(18)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#000000')
  }
}