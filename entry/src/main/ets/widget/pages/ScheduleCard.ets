/**
 * 桌面卡片：今日课表。
 *
 * 卡片 UI 只能读 LocalStorage 里的字段（数据由 EntryFormAbility 通过
 * formBindingData 注入），卡片自身不能联网、不能用 setTimeout，也不支持
 * ImmersiveMaterial（uiMaterial 的 ImmersiveMaterial 没有 @form 标记）。
 *
 * 数据格式（CardData 写入）：
 *   scheduleSubtitle = "第13周 · 11-26 周四"
 *   scheduleLines    = "1-2|软件工程专业导论|博文楼阶梯D301\n3-4|习近平...|至善楼阶梯I203"
 * 兼容旧数据：没有 "|" 的行按整行展示。
 */
@Entry
@Component
struct ScheduleCard {
  @LocalStorageProp('scheduleTitle') scheduleTitle: string = '今日课表';
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

  @Builder
  courseRow(line: string) {
    Row() {
      Text(this.part(line, 0))
        .fontSize(10)
        .fontColor('#8A8F99')
        .width(32)

      Column()
        .width(3)
        .height(30)
        .borderRadius(2)
        .backgroundColor('#011F5B')
        .margin({ right: 8 })

      Column() {
        Text(this.part(line, 1))
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor('#1F2937')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        if (this.part(line, 2).length > 0) {
          Text(this.part(line, 2))
            .fontSize(10)
            .fontColor('#8A8F99')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 2 })
            .width('100%')
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .margin({ top: 8 })
  }

  build() {
    Column() {
      Row() {
        Text(this.scheduleTitle)
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor('#1F2937')
        Blank()
        Text(this.updatedText)
          .fontSize(9)
          .fontColor('#8A8F99')
          .maxLines(1)
      }
      .width('100%')

      if (this.scheduleSubtitle.length > 0) {
        Text(this.scheduleSubtitle)
          .fontSize(10)
          .fontColor('#8A8F99')
          .width('100%')
          .margin({ top: 2 })
      }

      Divider()
        .color('#EEF1F5')
        .strokeWidth(0.5)
        .margin({ top: 8, bottom: 2 })

      if (this.lines().length === 0) {
        Column() {
          Text('今天没有课程')
            .fontSize(12)
            .fontColor('#8A8F99')
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        Column() {
          ForEach(this.lines(), (line: string, index: number) => {
            if (this.structured(line)) {
              this.courseRow(line)
            } else {
              // 兼容旧版写入的纯文本行 / 加载提示
              Text(line)
                .fontSize(11)
                .fontColor('#6B7280')
                .width('100%')
                .maxLines(3)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .margin({ top: 8 })
            }
          }, (line: string, index: number) => index + '-' + line)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Start)
        .alignItems(HorizontalAlign.Start)
      }
    }
    .width('100%')
    .height('100%')
    .padding({ left: 14, right: 14, top: 12, bottom: 12 })
    .backgroundColor('#FFFFFF')
    .borderRadius(16)
    .onClick(() => {
      postCardAction(this, {
        action: 'router',
        abilityName: 'EntryAbility',
        params: { target: 'schedule' }
      });
    })
  }
}
