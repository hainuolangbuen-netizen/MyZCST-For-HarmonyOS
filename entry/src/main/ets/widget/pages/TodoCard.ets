/**
 * 桌面卡片：我的待办 + 未读消息。
 * 数据来源与刷新方式见 ScheduleCard.ets 顶部注释。
 */
@Entry
@Component
struct TodoCard {
  @LocalStorageProp('todoTitle') todoTitle: string = '我的待办';
  @LocalStorageProp('todoLines') todoLines: string = '打开「我的珠科」并登录后自动同步';
  @LocalStorageProp('updatedText') updatedText: string = '';

  build() {
    Column() {
      Row() {
        Text(this.todoTitle)
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor('#182331')
        Blank()
        Text(this.updatedText)
          .fontSize(9)
          .fontColor('#8A8F99')
      }
      .width('100%')

      Text(this.todoLines)
        .fontSize(12)
        .lineHeight(18)
        .fontColor('#182431')
        .maxLines(6)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .margin({ top: 8 })
        .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .padding(12)
    .backgroundColor('#FFFFFF')
    .borderRadius(16)
    .onClick(() => {
      postCardAction(this, {
        action: 'router',
        abilityName: 'EntryAbility',
        params: { target: 'todo' }
      });
    })
  }
}
