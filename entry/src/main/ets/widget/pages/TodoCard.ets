/**
 * 桌面卡片：我的待办。
 *
 * 数据来自门户「我的」页的待办接口（TodoSync 写入 CardStore），
 * 每行格式 title|content；没有 "|" 的旧数据按纯文本展示。
 */
@Entry
@Component
struct TodoCard {
  @LocalStorageProp('todoTitle') todoTitle: string = '我的待办';
  @LocalStorageProp('todoLines') todoLines: string = '暂无待办';
  @LocalStorageProp('todoUpdatedText') todoUpdated: string = '';

  private items(): string[] {
    if (this.todoLines.length === 0) {
      return [];
    }
    return this.todoLines.split('\n');
  }

  private structured(line: string): boolean {
    return line.indexOf('|') >= 0;
  }

  private part(line: string, index: number): string {
    const parts: string[] = line.split('|');
    return index < parts.length ? parts[index] : '';
  }

  @Builder
  todoRow(line: string, index: number) {
    Row() {
      Column() {
        Text((index + 1).toString())
          .fontSize(10)
          .fontColor('#0C1420')
          .textAlign(TextAlign.Center)
      }
      .width(20)
      .height(20)
      .borderRadius(10)
      .backgroundColor('#7FB8D8')
      .justifyContent(FlexAlign.Center)

      Column() {
        Text(this.part(line, 0).length > 0 ? this.part(line, 0) : line)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor('#F2F6FC')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        if (this.part(line, 1).length > 0) {
          Text(this.part(line, 1))
            .fontSize(11)
            .fontColor('#AAB8CA')
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 3 })
            .width('100%')
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 10 })
    }
    .width('100%')
    .padding({ left: 10, right: 10, top: 9, bottom: 9 })
    .backgroundColor('#172231')
    .borderRadius(12)
    .margin({ top: 8 })
  }

  build() {
    Column() {
      Row() {
        Text(this.todoTitle)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor('#F2F6FC')
        Blank()
        Text(this.todoUpdated)
          .fontSize(9)
          .fontColor('#AAB8CA')
          .maxLines(1)
      }
      .width('100%')

      if (this.items().length === 0 || this.todoLines === '暂无待办') {
        Column() {
          Text('暂无待办')
            .fontSize(13)
            .fontColor('#AAB8CA')
          Text('在「我的珠科」门户产生的待办会自动同步')
            .fontSize(10)
            .fontColor('#6F7B8B')
            .margin({ top: 5 })
            .textAlign(TextAlign.Center)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        List({ space: 0 }) {
          ForEach(this.items(), (line: string, index: number) => {
            ListItem() {
              if (this.structured(line)) {
                this.todoRow(line, index)
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
        params: { target: 'todo' }
      });
    })
  }
}
