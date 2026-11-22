import { BrandIconId, formatContextWindowShort, resolveBrandIconId } from '../core/BrandIcons';
import { ImmersiveMaterialStyle } from '../core/ImmersiveMaterialStyle';
import { ModelSpec, Provider, isProviderConfigured, providerEnabledModels } from '../core/Models';
import { KelivoAvatarBadge } from './KelivoChrome';

interface ModelPickerGroup {
  groupId: string;
  providerId: string;
  providerName: string;
  items: ModelPickerRow[];
}

interface ModelPickerRow {
  rowKey: string;
  provider: Provider;
  spec: ModelSpec;
  brandId: BrandIconId;
  favorite: boolean;
}

@Component
export struct ModelSelectSheet {
  @Prop providers: Provider[] = [];
  @Prop currentProviderId: string = '';
  @Prop currentModelId: string = '';
  @Prop favoriteModels: string[] = [];
  @Prop immersiveLightEnabled: boolean = true;

  onSelectModel: (providerId: string, modelId: string) => void = () => {};
  onToggleFavorite: (providerId: string, modelId: string) => void = () => {};
  onOpenProviders: () => void = () => {};

  @State queryText: string = '';
  @State selectedFilterProviderId: string = '';

  private favKey(providerId: string, modelId: string): string {
    return `${providerId}::${modelId}`;
  }

  private enabledProviders(): Provider[] {
    const ready = this.providers.filter((p: Provider): boolean =>
      p.enabled !== false && isProviderConfigured(p) && providerEnabledModels(p).length > 0
    );
    const active = ready.filter((p: Provider): boolean => p.id === this.currentProviderId);
    const others = ready.filter((p: Provider): boolean => p.id !== this.currentProviderId);
    return [...active, ...others];
  }

  private matchesSearch(prov: Provider, spec: ModelSpec, q: string): boolean {
    if (q.length === 0) return true;
    return (
      prov.name.toLowerCase().indexOf(q) >= 0 ||
      spec.id.toLowerCase().indexOf(q) >= 0 ||
      (spec.displayName || '').toLowerCase().indexOf(q) >= 0
    );
  }

  private providerSpecs(prov: Provider): ModelSpec[] {
    return providerEnabledModels(prov);
  }

  private pickerGroups(): ModelPickerGroup[] {
    const q = this.queryText.trim().toLowerCase();
    const groups: ModelPickerGroup[] = [];
    const favRows: ModelPickerRow[] = [];
    const allProvs = this.enabledProviders();

    for (let i = 0; i < allProvs.length; i++) {
      const p = allProvs[i];
      if (this.selectedFilterProviderId.length > 0 && p.id !== this.selectedFilterProviderId) {
        continue;
      }
      const specs = this.providerSpecs(p);
      const rows: ModelPickerRow[] = [];
      for (let j = 0; j < specs.length; j++) {
        const spec = specs[j];
        if (!this.matchesSearch(p, spec, q)) continue;
        const fKey = this.favKey(p.id, spec.id);
        const isFav = this.favoriteModels.includes(fKey);
        const brand = resolveBrandIconId(`${spec.id} ${p.name}`, p.family);
        const row: ModelPickerRow = {
          rowKey: `${p.id}::${spec.id}::${j}`,
          provider: p,
          spec,
          brandId: brand,
          favorite: isFav
        };
        rows.push(row);
        if (isFav && this.selectedFilterProviderId.length === 0) {
          favRows.push({
            rowKey: `fav::${p.id}::${spec.id}::${j}`,
            provider: p,
            spec,
            brandId: brand,
            favorite: true
          });
        }
      }
      if (rows.length > 0) {
        groups.push({
          groupId: p.id,
          providerId: p.id,
          providerName: p.name,
          items: rows
        });
      }
    }

    if (favRows.length > 0) {
      return [
        { groupId: '__favorites__', providerId: '', providerName: '收藏模型', items: favRows },
        ...groups
      ];
    }
    return groups;
  }

  private modalityText(spec: ModelSpec): string {
    return spec.vision ? 'T · 图 → T' : 'T → T';
  }

  @Builder
  private modelItemRow(item: ModelPickerRow) {
    Row({ space: 10 }) {
      KelivoAvatarBadge({
        brandId: item.brandId,
        avatarText: '',
        fallbackLetter: item.provider.name,
        badgeSize: 36
      })

      Column({ space: 4 }) {
        Row({ space: 6 }) {
          Text(item.spec.displayName || item.spec.id)
            .fontSize(15)
            .fontWeight(item.provider.id === this.currentProviderId && item.spec.id === this.currentModelId
              ? FontWeight.Bold
              : FontWeight.Medium)
            .fontColor(item.provider.id === this.currentProviderId && item.spec.id === this.currentModelId
              ? $r('app.color.accent')
              : $r('app.color.ink'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
        }

        Flex({ wrap: FlexWrap.Wrap }) {
          Text(item.spec.imageGen ? '生图' : 'Chat')
            .fontSize(10)
            .fontColor($r('app.color.accent'))
            .backgroundColor($r('app.color.tint'))
            .padding({ left: 7, right: 7, top: 2, bottom: 2 })
            .borderRadius(999)
            .margin({ right: 5, bottom: 3 })

          Text(this.modalityText(item.spec))
            .fontSize(10)
            .fontColor($r('app.color.muted'))
            .backgroundColor(ImmersiveMaterialStyle.sheetCardBackground(this.immersiveLightEnabled))
            .padding({ left: 7, right: 7, top: 2, bottom: 2 })
            .borderRadius(999)
            .margin({ right: 5, bottom: 3 })

          if (item.spec.tools) {
            Row() {
              SymbolGlyph($r('sys.symbol.wrench_and_screwdriver'))
                .fontSize(10)
                .fontColor([$r('app.color.accent')])
            }
            .padding({ left: 6, right: 6, top: 3, bottom: 3 })
            .borderRadius(999)
            .backgroundColor($r('app.color.tint'))
            .margin({ right: 5, bottom: 3 })
          }

          if (item.spec.reasoning) {
            Row() {
              SymbolGlyph($r('sys.symbol.lightbulb'))
                .fontSize(10)
                .fontColor([$r('app.color.accent')])
            }
            .padding({ left: 6, right: 6, top: 3, bottom: 3 })
            .borderRadius(999)
            .backgroundColor($r('app.color.tint'))
            .margin({ right: 5, bottom: 3 })
          }

          if (item.spec.contextWindow > 0) {
            Text(formatContextWindowShort(item.spec.contextWindow))
              .fontSize(10)
              .fontColor($r('app.color.muted'))
              .backgroundColor(ImmersiveMaterialStyle.sheetCardBackground(this.immersiveLightEnabled))
              .padding({ left: 7, right: 7, top: 2, bottom: 2 })
              .borderRadius(999)
              .margin({ right: 5, bottom: 3 })
          }
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      if (item.provider.id === this.currentProviderId && item.spec.id === this.currentModelId) {
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(16)
          .fontColor([$r('app.color.accent')])
      }

      Button({ type: ButtonType.Circle }) {
        SymbolGlyph(item.favorite ? $r('sys.symbol.heart_fill') : $r('sys.symbol.heart'))
          .fontSize(17)
          .fontColor([item.favorite ? $r('app.color.warning') : $r('app.color.muted')])
      }
      .width(34)
      .height(34)
      .padding(0)
      .backgroundColor(Color.Transparent)
      .accessibilityText(item.favorite ? '取消收藏' : '收藏模型')
      .onClick(() => { this.onToggleFavorite(item.provider.id, item.spec.id); })
    }
    .width('100%')
    .padding({ left: 10, right: 6, top: 9, bottom: 9 })
    .borderRadius(12)
    .backgroundColor(item.provider.id === this.currentProviderId && item.spec.id === this.currentModelId
      ? $r('app.color.tint')
      : Color.Transparent)
    .onClick(() => { this.onSelectModel(item.provider.id, item.spec.id); })
  }

  build() {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.magnifyingglass'))
          .fontSize(17)
          .fontColor([$r('app.color.muted')])
        TextInput({ text: this.queryText, placeholder: '搜索模型或服务商' })
          .layoutWeight(1)
          .height(36)
          .backgroundColor(Color.Transparent)
          .padding(0)
          .fontSize(14)
          .fontColor(ImmersiveMaterialStyle.isActive(this.immersiveLightEnabled) ? $r('sys.color.font_primary') : $r('app.color.ink'))
          .placeholderColor(ImmersiveMaterialStyle.isActive(this.immersiveLightEnabled) ? $r('sys.color.font_secondary') : $r('app.color.muted'))
          .onChange((v: string) => { this.queryText = v; })
        if (this.queryText.length > 0) {
          Button({ type: ButtonType.Circle }) {
            SymbolGlyph($r('sys.symbol.xmark'))
              .fontSize(13)
              .fontColor([$r('app.color.muted')])
          }
          .width(26)
          .height(26)
          .padding(0)
          .backgroundColor(Color.Transparent)
          .onClick(() => { this.queryText = ''; })
        }
      }
      .width('100%')
      .height(42)
      .padding({ left: 14, right: 10 })
      .borderRadius(21)
      .backgroundColor(ImmersiveMaterialStyle.sheetCardBackground(this.immersiveLightEnabled))

      Scroll() {
        Column({ space: 12 }) {
          ForEach(this.pickerGroups(), (grp: ModelPickerGroup) => {
            Column({ space: 4 }) {
              Text(grp.providerName)
                .fontSize(12)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.muted'))
                .padding({ left: 6, bottom: 2 })
              Column({ space: 2 }) {
                ForEach(grp.items, (row: ModelPickerRow) => {
                  this.modelItemRow(row)
                }, (row: ModelPickerRow) => row.rowKey + (row.favorite ? ':1' : ':0') + (this.currentModelId))
              }
              .width('100%')
              .padding(4)
              .borderRadius(14)
              .backgroundColor(ImmersiveMaterialStyle.sheetCardBackground(this.immersiveLightEnabled))
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
          }, (grp: ModelPickerGroup) => grp.groupId + '_' + grp.items.length)

          if (this.pickerGroups().length === 0) {
            Column({ space: 10 }) {
              Text(this.queryText.trim().length > 0
                ? '未找到匹配的模型，请调整关键词或前往“供应商”添加模型。'
                : '暂无可用模型，请先在供应商中配置 API 密钥并添加模型。')
                .fontSize(13)
                .fontColor($r('app.color.muted'))
                .textAlign(TextAlign.Center)
              Button('配置供应商')
                .type(ButtonType.Normal)
                .height(36)
                .fontSize(13)
                .borderRadius(18)
                .padding({ left: 16, right: 16 })
                .backgroundColor($r('app.color.tint'))
                .fontColor($r('app.color.accent'))
                .onClick(() => { this.onOpenProviders(); })
            }
            .width('100%')
            .padding(24)
            .alignItems(HorizontalAlign.Center)
          }
        }
        .width('100%')
        .padding({ bottom: 6 })
      }
      .constraintSize({ maxHeight: 380 })
      .width('100%')
      .edgeEffect(EdgeEffect.Spring)

      Row({ space: 8 }) {
        Scroll() {
          Row({ space: 6 }) {
            Button('全部')
              .type(ButtonType.Normal)
              .height(32)
              .fontSize(12)
              .padding({ left: 12, right: 12 })
              .borderRadius(16)
              .backgroundColor(this.selectedFilterProviderId === ''
                ? $r('app.color.accent')
                : ImmersiveMaterialStyle.sheetCardBackground(this.immersiveLightEnabled))
              .fontColor(this.selectedFilterProviderId === '' ? $r('app.color.on_accent') : $r('app.color.ink'))
              .onClick(() => { this.selectedFilterProviderId = ''; })

            ForEach(this.enabledProviders(), (p: Provider) => {
              Row({ space: 5 }) {
                KelivoAvatarBadge({
                  brandId: resolveBrandIconId(p.name, p.family),
                  avatarText: '',
                  fallbackLetter: p.name,
                  badgeSize: 18
                })
                Text(p.name)
                  .fontSize(12)
                  .fontColor(this.selectedFilterProviderId === p.id ? $r('app.color.on_accent') : $r('app.color.ink'))
                  .maxLines(1)
              }
              .height(32)
              .padding({ left: 8, right: 10 })
              .borderRadius(16)
              .backgroundColor(this.selectedFilterProviderId === p.id
                ? $r('app.color.accent')
                : ImmersiveMaterialStyle.sheetCardBackground(this.immersiveLightEnabled))
              .onClick(() => {
                this.selectedFilterProviderId = this.selectedFilterProviderId === p.id ? '' : p.id;
              })
            }, (p: Provider) => p.id)
          }
          .padding({ right: 8 })
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .layoutWeight(1)

        Button('管理')
          .type(ButtonType.Normal)
          .height(32)
          .fontSize(12)
          .padding({ left: 12, right: 12 })
          .borderRadius(16)
          .backgroundColor($r('app.color.tint'))
          .fontColor($r('app.color.accent'))
          .onClick(() => { this.onOpenProviders(); })
      }
      .width('100%')
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 4, bottom: 20 })
  }
}
