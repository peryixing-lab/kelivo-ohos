import { AbilityConstant, Configuration, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { backgroundGenerationManager } from '../core/BackgroundGeneration';
import { publishIncomingOpenChatWant, publishIncomingShareWant } from '../core/SystemBridge';
import { AppWindowController } from '../core/WindowController';

import { initPlanStorage } from '../core/ChatGptSession';
import { initOpenCodeGoStorage } from '../core/OpenCodeGoSession';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  private winCtrl: AppWindowController = new AppWindowController();

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
    initPlanStorage(this.context);
    initOpenCodeGoStorage(this.context);
    backgroundGenerationManager.attachContext(this.context);
    AppStorage.setOrCreate('appInBackground', false);
    publishIncomingShareWant(want);
    publishIncomingOpenChatWant(want);
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onNewWant');
    publishIncomingShareWant(want);
    publishIncomingOpenChatWant(want);
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
    backgroundGenerationManager.stopAll();
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Main window is created, set main page for this ability
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');
    backgroundGenerationManager.attachContext(this.context);

    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }

    const isDark = this.context.config?.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    AppStorage.setOrCreate('systemIsDark', isDark);

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');
      windowStage.getMainWindow().then((win: window.Window) => {
        this.winCtrl.attach(win, isDark).catch(() => {});
      }).catch(() => {});
    });
  }

  onConfigurationUpdate(newConfig: Configuration): void {
    const isDark = newConfig.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    AppStorage.setOrCreate('systemIsDark', isDark);
    this.winCtrl.syncSystemBarAppearance(isDark);
  }

  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
    this.winCtrl.detach();
  }

  onForeground(): void {
    // Ability has brought to foreground
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
    backgroundGenerationManager.onForeground();
  }

  onBackground(): void {
    // Ability has back to background
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
    backgroundGenerationManager.onBackground();
  }

  onBackPressed(): boolean {
    return true;
  }
}