/**
 * 桌面卡片：今日课表。
 *
 * 卡片 UI 只能读 LocalStorage 里的字段（数据由 EntryFormAbility 通过
 * formBindingData 注入），卡片自身不能联网、不能用 setTimeout，也不支持
 * ImmersiveMaterial（uiMaterial 的 ImmersiveMaterial 没有 @form 标记）。
 * 所以这里只做展示 + 点击拉起主应用。
 */
@Entry
@Component
struct ScheduleCard {
  @LocalStorageProp('scheduleTitle') scheduleTitle: string = '今日课表';
  @LocalStorageProp('scheduleLines') scheduleLines: string = '打开「我的珠科」并登录后自动同步';
  @LocalStorageProp('updatedText') updatedText: string = '';

  build() {
    Column() {
      Row() {
        Text(this.scheduleTitle)
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor('#182431')
        Blank()
        Text(this.updatedText)
          .fontSize(9)
          .fontColor('#8A8F99')
      }
      .width('100%')

      Text(this.scheduleLines)
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
        params: { target: 'schedule' }
      });
    })
  }
}
