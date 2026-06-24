// Small-viewport layout smoke tests for Roll Feathers web.
//
// Mirrors integration_test/narrow_screen_test.dart: loads the app at several
// small viewport sizes and verifies the key overflow-prone surfaces (home
// screen, dddice dialog) still render their controls.
//
// Note: Flutter's debug-mode RenderFlex overflow assertion isn't observable in
// a release web build (it clips visually instead of throwing, and isn't exposed
// to the DOM). So these assert the expected controls are present/usable at each
// size rather than catching the Flutter assertion the way the widget-level
// integration test does.

import { test, expect } from '@playwright/test';
import { enableA11y, openSettingsItem } from './helpers';

const viewports = [
  { width: 360, height: 800 }, // narrow phone portrait
  { width: 800, height: 360 }, // phone landscape
  { width: 728, height: 900 }, // half-screen desktop
  { width: 360, height: 450 }, // quarter-screen / small snapped window
];

for (const vp of viewports) {
  test.describe(`narrow layout (${vp.width}×${vp.height})`, () => {
    test.use({ viewport: { width: vp.width, height: vp.height } });

    test('home screen renders core controls', async ({ page }) => {
      await page.goto('/');
      await enableA11y(page);
      await expect(page.getByRole('button', { name: 'Add Die' })).toBeVisible();
    });

    test('dddice dialog (unauthenticated) renders sign-in options', async ({ page }) => {
      await page.goto('/');
      await enableA11y(page);
      await openSettingsItem(page, /dddice Settings/);
      await expect(page.getByText('Use guest account')).toBeVisible();
    });
  });
}
