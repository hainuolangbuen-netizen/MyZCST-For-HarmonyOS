/**
 * 桌面卡片：宿舍水电。
 *
 * 数据来自完美校园 SWEAServlet（FeeSync 写入 CardStore）：
 *   feeRoom  = 房间名
 *   feeLines = 每行 "电费|178.75|度|6391.25|0"
 *              （名称|余额|单位|已用|低余额告警）
 * 卡片只展示，不直接联网；主 App 在设置学号后同步。
 */
@Entry
@Component
struct FeeCard {
  @LocalStorageProp('feeTitle') feeTitle: string = '宿舍水电';
  @LocalStorageProp('feeRoom') feeRoom: string = '';
  @LocalStorageProp('feeLines') feeLines: string = '尚未获取水电数据';
  @LocalStorageProp('feeUpdatedText') feeUpdated: string = '';

  private rows(): string[] {
    if (this.feeLines.length === 0) {
      return [];
    }
    return this.feeLines.split('\n');
  }

  private structured(line: string): boolean {
    return line.indexOf('|') >= 0;
  }

  private part(line: string, index: number): string {
    const parts: string[] = line.split('|');
    return index < parts.length ? parts[index] : '';
  }

  private urgent(line: string): boolean {
    return this.part(line, 4) === '1';
  }

  private hasUsed(line: string): boolean {
    const used: number = Number(this.part(line, 3));
    return !isNaN(used) && used > 0;
  }

  @Builder
  feeRow(line: string) {
    Row() {
      Column() {
        Text(this.part(line, 0))
          .fontSize(12)
          .fontColor('#AAB8CA')
          .maxLines(1)
        if (this.hasUsed(line)) {
          Text('已用 ' + this.part(line, 3) + this.part(line, 2))
            .fontSize(9)
            .fontColor('#6F7B8B')
            .margin({ top: 2 })
            .maxLines(1)
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Text(this.part(line, 1))
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.urgent(line) ? '#E86A5E' : '#F2F6FC')
        .maxLines(1)
      Text(this.part(line, 2))
        .fontSize(10)
        .fontColor(this.urgent(line) ? '#E86A5E' : '#AAB8CA')
        .margin({ left: 3 })
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 10, bottom: 10 })
    .backgroundColor(this.urgent(line) ? '#2C1D1D' : '#172231')
    .borderRadius(12)
    .margin({ top: 8 })
  }

  build() {
    Column() {
      Row() {
        Text(this.feeTitle)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor('#F2F6FC')
        Blank()
        if (this.feeRoom.length > 0) {
          Text(this.feeRoom)
            .fontSize(9)
            .fontColor('#AAB8CA')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
            .textAlign(TextAlign.End)
            .margin({ left: 8 })
        }
      }
      .width('100%')

      if (this.rows().length === 0 || !this.structured(this.feeLines)) {
        Column() {
          Text(this.feeRoom.length > 0 ? '暂未获取到余额' : '尚未获取水电数据')
            .fontSize(13)
            .fontColor('#AAB8CA')
          Text('设置里填学号，或打开应用内「智能水电」页面自动读取')
            .fontSize(10)
            .fontColor('#6F7B8B')
            .margin({ top: 5 })
            .textAlign(TextAlign.Center)
            .maxLines(2)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        List({ space: 0 }) {
          ForEach(this.rows(), (line: string, index: number) => {
            ListItem() {
              if (this.structured(line)) {
                this.feeRow(line)
              } else {
                Text(line)
                  .fontSize(12)
                  .fontColor('#AAB8CA')
                  .width('100%')
                  .maxLines(3)
                  .margin({ top: 10 })
              }
            }
            .width('100%')
          }, (line: string, index: number) => index + '-' + line)
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .alignListItem(ListItemAlign.Start)
      }

      if (this.feeUpdated.length > 0) {
        Text(this.feeUpdated)
          .fontSize(8)
          .fontColor('#5E6B7D')
          .width('100%')
          .textAlign(TextAlign.End)
          .margin({ top: 4 })
      }
    }
    .width('100%')
    .height('100%')
    .padding({ left: 14, right: 14, top: 12, bottom: 12 })
    .backgroundColor('#0C1420')
    .borderRadius(20)
    .onClick(() => {
      postCardAction(this, {
        action: 'router',
        abilityName: 'EntryAbility',
        params: { target: 'fee' }
      });
    })
  }
}
