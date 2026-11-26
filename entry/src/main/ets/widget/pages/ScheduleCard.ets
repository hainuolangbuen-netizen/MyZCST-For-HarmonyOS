/**
 * 桌面卡片：今日课程（对齐掌上猪科课程卡片的视觉）。
 *
 * 卡片 UI 只能读 LocalStorage 里的字段（数据由 EntryFormAbility 通过
 * formBindingData 注入），卡片自身不能联网、不能用 setTimeout。
 *
 * 数据格式（CourseSync 写入）：
 *   scheduleSubtitle = "11月26日 · 星期四 · 第13周"
 *   scheduleLines    = "08:10|09:50|1-2|软件工程专业导论|博文楼阶梯D301|周瑞洪|3-18周\n..."
 * 兼容旧数据：没有 "|" 的行按纯文本展示。
 *
 * 完成状态在卡片渲染时按当前时间计算：下课时间已过 → 整张课程卡片变浅；
 * 未上课/正在上课保持原色。
 */
@Entry
@Component
struct ScheduleCard {
  @LocalStorageProp('scheduleTitle') scheduleTitle: string = '今日课程';
  @LocalStorageProp('scheduleSubtitle') scheduleSubtitle: string = '';
  @LocalStorageProp('scheduleLines') scheduleLines: string = '打开「我的珠科」并登录后自动同步';
  @LocalStorageProp('updatedText') updatedText: string = '';

  private lines(): string[] {
    const raw: string = this.scheduleLines;
    if (raw.length === 0) {
      return [];
    }
    return raw.split('\n');
  }

  private structured(line: string): boolean {
    return line.indexOf('|') > 0;
  }

  private part(line: string, index: number): string {
    const parts: string[] = line.split('|');
    return index < parts.length ? parts[index] : '';
  }

  private toMinutes(hhmm: string): number {
    if (hhmm.length === 0) {
      return -1;
    }
    const colon: number = hhmm.indexOf(':');
    if (colon <= 0) {
      return -1;
    }
    const h: number = Number(hhmm.substring(0, colon));
    const m: number = Number(hhmm.substring(colon + 1));
    if (isNaN(h) || isNaN(m)) {
      return -1;
    }
    return h * 60 + m;
  }

  /** 下课时间已过 → 已完成（颜色变浅）。 */
  private completed(line: string): boolean {
    const end: number = this.toMinutes(this.part(line, 1));
    if (end < 0) {
      return false;
    }
    const now = new Date();
    return now.getHours() * 60 + now.getMinutes() >= end;
  }

  private meta(line: string): string {
    const items: string[] = [];
    const room: string = this.part(line, 4);
    const teacher: string = this.part(line, 5);
    const weeks: string = this.part(line, 6);
    if (room.length > 0) {
      items.push(room);
    }
    if (teacher.length > 0) {
      items.push(teacher);
    }
    if (weeks.length > 0) {
      items.push(weeks);
    }
    return items.join(' · ');
  }

  private courseBackground(index: number, done: boolean): string {
    if (done) {
      // 已完成：低饱和的浅灰蓝，和未上课的彩色卡片区分开（视觉上"变浅"）。
      return '#1A2330';
    }
    const tones: string[] = ['#17352D', '#2A2340', '#1B2F45', '#3A2B1E', '#1D2B3A'];
    return tones[index % tones.length];
  }

  private courseAccent(index: number, done: boolean): string {
    if (done) {
      return '#566273';
    }
    const tones: string[] = ['#4FD1A5', '#A88BE8', '#62A6E8', '#E0A45E', '#7FB8D8'];
    return tones[index % tones.length];
  }

  @Builder
  courseCard(line: string, index: number) {
    Row() {
      // 左侧：开始时间 + 节次
      Column() {
        Text(this.part(line, 0).length > 0 ? this.part(line, 0) : '--:--')
          .fontSize(19)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.completed(line) ? '#8A95A5' : '#F2F6FC')
        Text(this.part(line, 2) + '节')
          .fontSize(10)
          .fontColor(this.completed(line) ? '#778394' : '#AAB8CA')
          .margin({ top: 3 })
      }
      .width(62)
      .alignItems(HorizontalAlign.Start)

      // 左侧色条：区分课程，已完成时变浅
      Column()
        .width(3)
        .height(52)
        .borderRadius(2)
        .backgroundColor(this.courseAccent(index, this.completed(line)))
        .margin({ left: 2, right: 10 })

      // 右侧：课程名 + 完成徽标 + 教室/教师/周次 + 下课时间
      Column() {
        Row() {
          Text(this.part(line, 3))
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.completed(line) ? '#8A95A5' : '#F2F6FC')
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          if (this.completed(line)) {
            Text('✓ 已完成')
              .fontSize(9)
              .fontColor('#8A95A5')
              .backgroundColor('#243040')
              .borderRadius(9)
              .padding({ left: 7, right: 7, top: 3, bottom: 3 })
              .margin({ left: 6 })
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)

        if (this.meta(line).length > 0) {
          Text(this.meta(line))
            .fontSize(12)
            .fontColor(this.completed(line) ? '#778394' : '#AAB8CA')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 5 })
            .width('100%')
        }

        if (this.part(line, 1).length > 0) {
          Text('至 ' + this.part(line, 1))
            .fontSize(11)
            .fontColor(this.completed(line) ? '#778394' : '#AAB8CA')
            .margin({ top: 4 })
            .width('100%')
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 10, bottom: 10 })
    .backgroundColor(this.courseBackground(index, this.completed(line)))
    .borderRadius(14)
    .margin({ top: 8 })
  }

  build() {
    Column() {
      // 标题 + 日期/周次
      Row() {
        Text(this.scheduleTitle)
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor('#F2F6FC')
        Blank()
        Text(this.scheduleSubtitle)
          .fontSize(10)
          .fontColor('#AAB8CA')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
          .textAlign(TextAlign.End)
          .margin({ left: 8 })
      }
      .width('100%')

      // 课程列表 / 空态
      if (this.lines().length === 0) {
        Column() {
          Text('今天没有课程')
            .fontSize(13)
            .fontColor('#AAB8CA')
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        Column() {
          ForEach(this.lines(), (line: string, index: number) => {
            if (this.structured(line)) {
              this.courseCard(line, index)
            } else {
              Text(line)
                .fontSize(12)
                .fontColor('#AAB8CA')
                .width('100%')
                .maxLines(3)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .margin({ top: 10 })
            }
          }, (line: string, index: number) => index + '-' + line)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Start)
        .alignItems(HorizontalAlign.Start)
      }

      if (this.updatedText.length > 0) {
        Text(this.updatedText)
          .fontSize(8)
          .fontColor('#5E6B7D')
          .width('100%')
          .textAlign(TextAlign.End)
          .margin({ top: 4 })
      }
    }
    .width('100%')
    .height('100%')
    .padding({ left: 16, right: 16, top: 14, bottom: 12 })
    .backgroundColor('#0C1420')
    .borderRadius(20)
    .onClick(() => {
      postCardAction(this, {
        action: 'router',
        abilityName: 'EntryAbility',
        params: { target: 'schedule' }
      });
    })
  }
}
